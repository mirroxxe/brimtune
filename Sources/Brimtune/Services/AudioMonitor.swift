import AppKit
import AudioToolbox
import Combine
import CoreAudio
import IOBluetooth

struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    var symbol: String {
        let n = name.lowercased()
        let candidates: [String]
        if n.contains("airpods max") { candidates = ["airpods.max", "airpodsmax"] }
        else if n.contains("airpods pro") { candidates = ["airpods.pro", "airpodspro"] }
        else if n.contains("airpods") { candidates = ["airpods.gen3", "airpods"] }
        else if n.contains("beats") { candidates = ["beats.headphones", "headphones"] }
        else if isBluetooth { candidates = ["headphones"] }
        else if transport == kAudioDeviceTransportTypeBuiltIn { candidates = ["laptopcomputer"] }
        else if transport == kAudioDeviceTransportTypeAirPlay { candidates = ["airplay.audio", "airplayaudio"] }
        else if transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort { candidates = ["tv"] }
        else { candidates = ["hifispeaker"] }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "speaker.wave.2"
    }
}

enum HUDEvent: Equatable {
    case volume(Float, muted: Bool)
    case device(AudioOutput, battery: Int?)
}

/// Watches the default output device and its volume through CoreAudio.
@MainActor
final class AudioMonitor: ObservableObject {
    @Published private(set) var outputs: [AudioOutput] = []
    @Published private(set) var current: AudioOutput?
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false

    let events = PassthroughSubject<HUDEvent, Never>()

    private var watchedDevice: AudioDeviceID?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var suppressVolumeUntil = Date().addingTimeInterval(1)

    init() {
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.defaultDeviceChanged(announce: true)
        }
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) { [weak self] in
            self?.reloadOutputs()
        }
        reloadOutputs()
        defaultDeviceChanged(announce: false)
    }

    func select(_ output: AudioOutput) {
        var id = output.id
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    func setVolume(_ value: Float) {
        guard let id = current?.id else { return }
        var v = max(0, min(1, value))
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &v)
    }

    // MARK: Private

    private func defaultDeviceChanged(announce: Bool) {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return }
        let output = Self.output(for: id)
        current = output
        watchVolume(of: id)
        readVolume()
        suppressVolumeUntil = Date().addingTimeInterval(0.6)
        if announce, let output {
            events.send(.device(output, battery: output.isBluetooth ? Self.bluetoothBattery(named: output.name) : nil))
        }
    }

    private func reloadOutputs() {
        var addr = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return }
        outputs = ids.filter(Self.hasOutput).compactMap(Self.output(for:))
    }

    private func watchVolume(of id: AudioDeviceID) {
        if let old = watchedDevice {
            var v = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
            var m = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
            if let volumeListener { AudioObjectRemovePropertyListenerBlock(old, &v, .main, volumeListener) }
            if let muteListener { AudioObjectRemovePropertyListenerBlock(old, &m, .main, muteListener) }
        }
        watchedDevice = id
        volumeListener = listen(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput) { [weak self] in
            self?.volumeChanged()
        }
        muteListener = listen(id, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) { [weak self] in
            self?.volumeChanged()
        }
    }

    private func volumeChanged() {
        readVolume()
        guard Date() > suppressVolumeUntil else { return }
        events.send(.volume(volume, muted: muted))
    }

    private func readVolume() {
        guard let id = watchedDevice else { return }
        var v = Float(0), m = UInt32(0)
        var size = UInt32(MemoryLayout<Float>.size)
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr { volume = v }
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        muted = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &m) == noErr && m != 0
    }

    @discardableResult
    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ handler: @escaping @MainActor () -> Void) -> AudioObjectPropertyListenerBlock {
        var addr = Self.address(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        AudioObjectAddPropertyListenerBlock(object, &addr, .main, block)
        return block
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func output(for id: AudioDeviceID) -> AudioOutput? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr,
              let deviceName = name?.takeRetainedValue() as String? else { return nil }
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = address(kAudioDevicePropertyTransportType)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
        return AudioOutput(id: id, name: deviceName, transport: transport)
    }

    /// AirPods expose their battery through undocumented IOBluetoothDevice properties;
    /// probe them defensively and give up quietly if they're missing.
    private static func bluetoothBattery(named name: String) -> Int? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let device = devices.first(where: { $0.isConnected() && $0.name == name }) else { return nil }
        func read(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let v = device.value(forKey: key) as? Int, v > 0, v <= 100 else { return nil }
            return v
        }
        if let single = read("batteryPercentSingle") ?? read("batteryPercentCombined") { return single }
        let buds = [read("batteryPercentLeft"), read("batteryPercentRight")].compactMap { $0 }
        return buds.min()
    }
}
