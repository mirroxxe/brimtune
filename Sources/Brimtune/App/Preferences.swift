import Foundation
import ServiceManagement

enum LockScreenStyle: String, CaseIterable, Identifiable {
    case card, stage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .card: "Glass card"
        case .stage: "Full stage"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var islandEnabled: Bool { didSet { defaults.set(islandEnabled, forKey: "islandEnabled") } }
    @Published var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: "expandOnHover") } }
    @Published var showHUDs: Bool { didSet { defaults.set(showHUDs, forKey: "showHUDs") } }
    @Published var showTrackPeek: Bool { didSet { defaults.set(showTrackPeek, forKey: "showTrackPeek") } }
    @Published var lockScreenEnabled: Bool { didSet { defaults.set(lockScreenEnabled, forKey: "lockScreenEnabled") } }
    @Published var lockScreenStyle: LockScreenStyle { didSet { defaults.set(lockScreenStyle.rawValue, forKey: "lockScreenStyle") } }
    @Published var lyricsEnabled: Bool { didSet { defaults.set(lyricsEnabled, forKey: "lyricsEnabled") } }
    @Published var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: "calendarEnabled") } }
    @Published var liveWaveform: Bool { didSet { defaults.set(liveWaveform, forKey: "liveWaveform") } }
    @Published var externalDisplays: Bool { didSet { defaults.set(externalDisplays, forKey: "externalDisplays") } }
    @Published var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: "hideInFullScreen") } }

    /// The app used to be called Isle (bundle id app.isle.nowplaying). Bring its
    /// settings and history along once, so the rename costs the user nothing.
    private static func migrateFromIsle() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromIsle") else { return }
        defaults.set(true, forKey: "migratedFromIsle")
        // Login-item state belongs to the old app; Brimtune registers itself fresh.
        let skip: Set<String> = ["launchAtLoginConfigured"]
        for (key, value) in defaults.persistentDomain(forName: "app.isle.nowplaying") ?? [:]
        where defaults.object(forKey: key) == nil && !skip.contains(key) {
            defaults.set(value, forKey: key)
        }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("Isle"), new = support.appendingPathComponent("Brimtune")
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private init() {
        Self.migrateFromIsle()
        defaults.register(defaults: [
            "islandEnabled": true,
            "expandOnHover": true,
            "showHUDs": true,
            "showTrackPeek": true,
            "lockScreenEnabled": true,
            "lockScreenStyle": LockScreenStyle.stage.rawValue,
            "lyricsEnabled": true,
            "calendarEnabled": true,
            "liveWaveform": true,
            "externalDisplays": true,
            "hideInFullScreen": true,
        ])
        islandEnabled = defaults.bool(forKey: "islandEnabled")
        expandOnHover = defaults.bool(forKey: "expandOnHover")
        showHUDs = defaults.bool(forKey: "showHUDs")
        showTrackPeek = defaults.bool(forKey: "showTrackPeek")
        lockScreenEnabled = defaults.bool(forKey: "lockScreenEnabled")
        lockScreenStyle = LockScreenStyle(rawValue: defaults.string(forKey: "lockScreenStyle") ?? "") ?? .card
        lyricsEnabled = defaults.bool(forKey: "lyricsEnabled")
        calendarEnabled = defaults.bool(forKey: "calendarEnabled")
        liveWaveform = defaults.bool(forKey: "liveWaveform")
        externalDisplays = defaults.bool(forKey: "externalDisplays")
        hideInFullScreen = defaults.bool(forKey: "hideInFullScreen")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // On by default: turned on once on first run; after that the Settings toggle decides.
        if !defaults.bool(forKey: "launchAtLoginConfigured") {
            defaults.set(true, forKey: "launchAtLoginConfigured")
            // didSet doesn't run inside init, so register here directly.
            try? SMAppService.mainApp.register()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
