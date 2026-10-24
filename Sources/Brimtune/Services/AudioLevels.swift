import Accelerate
import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Live loudness of what the Mac is playing, split into a few frequency bands for
/// the waveform. Uses a Core Audio process tap (macOS 14.2+) on the system output,
/// which macOS asks permission for once; audio is analysed in memory and never stored.
@MainActor
final class AudioLevels: ObservableObject {
    static let shared = AudioLevels()
    static let bandCount = 5

    /// 0…1 per band, smoothed. Empty while not listening.
    @Published private(set) var bands: [Float] = []

    /// True when real sound has come through recently, so views can trust `bands`.
    var isLive: Bool { !bands.isEmpty && Date().timeIntervalSince(lastSound) < 0.6 }

    private var tap: Tap?
    private var lastSound = Date.distantPast

    func setListening(_ on: Bool) {
        if on, tap == nil {
            guard #available(macOS 14.2, *) else { return }
            tap = Tap { [weak self] levels in
                Task { @MainActor in self?.receive(levels) }
            }
            if tap?.start() != true { tap = nil }
            AudioActivity.setRunning(tap != nil)
        } else if !on, let tap {
            tap.stop()
            self.tap = nil
            AudioActivity.setRunning(false)
            bands = []
        }
    }

    private func receive(_ levels: [Float]) {
        if levels.contains(where: { $0 > 0.02 }) { lastSound = Date() }
        // Skip frames the eye can't tell apart; every publish redraws the waveforms.
        guard bands.count != levels.count || zip(bands, levels).contains(where: { abs($0 - $1) > 0.015 }) else { return }
        bands = levels
    }
}

/// Whether the Mac is actually making sound, readable from any thread. Lets the
/// title-only browser source notice a pause made in the browser itself.
enum AudioActivity {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var running = false
    nonisolated(unsafe) private static var heardSomething = false
    nonisolated(unsafe) private static var lastSound = Date.distantPast

    static func setRunning(_ on: Bool) {
        lock.withLock { running = on; heardSomething = false }
    }

    static func report(_ loudest: Float) {
        guard loudest > 0.04 else { return }
        lock.withLock { heardSomething = true; lastSound = Date() }
    }

    /// True only when the tap works (it has heard sound before) and has now been quiet a while.
    static var isSilent: Bool {
        lock.withLock { running && heardSomething && Date().timeIntervalSince(lastSound) > 2.5 }
    }
}

// MARK: - Tap

private final class Tap {
    private let onLevels: ([Float]) -> Void
    private let queue = DispatchQueue(label: "brimtune.audio-tap", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    private let fftSize = 1024
    private lazy var fft = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))
    private lazy var window: [Float] = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
    private var ring: [Float] = []
    private var smoothed = [Float](repeating: 0, count: AudioLevels.bandCount)
    private var sampleRate: Double = 48_000
    private var lastEmit = Date.distantPast

    init(onLevels: @escaping ([Float]) -> Void) {
        self.onLevels = onLevels
    }

    @available(macOS 14.2, *)
    func start() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return false }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Brimtune Waveform",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            stop()
            return false
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input)
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        if let fft { vDSP_destroy_fftsetup(fft) }
    }

    /// Mixes whatever layout arrives down to mono Float32 and analyses full windows.
    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(Int(first.mNumberChannels), 1)
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        let samples = data.assumingMemoryBound(to: Float.self)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels { sum += samples[f * channels + c] }
            ring.append(sum / Float(channels))
        }
        while ring.count >= fftSize {
            analyse(Array(ring.prefix(fftSize)))
            ring.removeFirst(fftSize / 2)
        }
    }

    private func analyse(_ chunk: [Float]) {
        guard let fft else { return }
        let half = fftSize / 2
        let windowed = vDSP.multiply(chunk, window)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, vDSP_Length(10), FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Log-spaced bands from bass to treble.
        let edges: [Double] = [40, 150, 400, 1_200, 3_500, 10_000]
        let binHz = sampleRate / Double(fftSize)
        var levels = [Float](repeating: 0, count: AudioLevels.bandCount)
        for b in 0..<AudioLevels.bandCount {
            let lo = max(1, Int(edges[b] / binHz)), hi = min(half - 1, max(lo + 1, Int(edges[b + 1] / binHz)))
            let peak = magnitudes[lo...hi].max() ?? 0
            let db = 20 * log10(max(peak / Float(fftSize), 1e-7))
            levels[b] = min(max((db + 62) / 50, 0), 1)
        }
        // Fast attack, slower release: punchy but not jittery.
        for b in 0..<levels.count {
            let k: Float = levels[b] > smoothed[b] ? 0.6 : 0.18
            smoothed[b] += (levels[b] - smoothed[b]) * k
        }
        AudioActivity.report(levels.max() ?? 0)
        let now = Date()
        guard now.timeIntervalSince(lastEmit) > 1.0 / 24 else { return }
        lastEmit = now
        onLevels(smoothed)
    }
}
