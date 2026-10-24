import AudioToolbox
import Combine
import Foundation

/// The Mac's output volume, read and set on the default output device, and kept in
/// step when it changes elsewhere (keyboard keys, Control Center, switching headphones).
@MainActor
final class SystemVolume: ObservableObject {
    static let shared = SystemVolume()

    /// 0...1.
    @Published private(set) var level: Float = 0
    @Published private(set) var isMuted = false
    /// False for outputs with no software volume (some HDMI and DisplayPort monitors).
    @Published private(set) var isAdjustable = false

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private static let virtualVolume = AudioObjectPropertyAddress(
        mSelector: 0x766D7663 /* 'vmvc' */, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static let mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    private init() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    func set(_ value: Float) {
        guard isAdjustable else { return }
        var v = min(1, max(0, value))
        var address = Self.virtualVolume
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &v)
        if isMuted && v > 0 { setMuted(false) }
        level = v
    }

    func toggleMute() {
        if level == 0 { set(0.3) } else { setMuted(!isMuted) }
    }

    private func setMuted(_ on: Bool) {
        var address = Self.mute
        guard AudioObjectHasProperty(device, &address) else { return set(on ? 0 : 0.3) }
        var v: UInt32 = on ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        isMuted = on
    }

    /// Follows the current default output device.
    private func attach() {
        for (var address, block) in deviceListeners { AudioObjectRemovePropertyListenerBlock(device, &address, .main, block) }
        deviceListeners = []

        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        device = id
        var volumeAddress = Self.virtualVolume
        isAdjustable = id != kAudioObjectUnknown && AudioObjectHasProperty(id, &volumeAddress)
        refresh()
        guard isAdjustable else { return }
        for var watched in [Self.virtualVolume, Self.mute] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &watched, .main, block) == noErr { deviceListeners.append((watched, block)) }
        }
    }

    private func refresh() {
        guard isAdjustable else { return }
        var v: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var address = Self.virtualVolume
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &v) == noErr, abs(v - level) > 0.001 { level = v }
        var m: UInt32 = 0
        var msize = UInt32(MemoryLayout<UInt32>.size)
        var maddress = Self.mute
        let muted = AudioObjectHasProperty(device, &maddress)
            && AudioObjectGetPropertyData(device, &maddress, 0, nil, &msize, &m) == noErr && m != 0
        if muted != isMuted { isMuted = muted }
    }
}
