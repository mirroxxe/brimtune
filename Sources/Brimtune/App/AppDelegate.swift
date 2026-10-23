import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences.shared
    private var center: NowPlayingCenter!
    private var audio: AudioMonitor!
    private var lock: LockMonitor!
    private var activities: ActivityCenter!
    private var history: HistoryStore!
    private var islands: [IslandController] = []
    private var stage: StageController!
    private var lockScreen: LockScreenController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        center = NowPlayingCenter(preferences: preferences)
        audio = AudioMonitor()
        lock = LockMonitor()
        activities = ActivityCenter(preferences: preferences)
        history = HistoryStore(center: center)
        center.startPlaylistRefresh()
        stage = StageController(center: center, audio: audio, preferences: preferences, history: history)
        lockScreen = LockScreenController(center: center, audio: audio, preferences: preferences, lock: lock, history: history)

        stage.onSettings = { [weak self] in self?.showSettings() }
        stage.onHistory = { [weak self] in self?.showHistory() }
        stage.onVisibilityChange = { [weak self] shown in self?.islands.forEach { $0.suppressed = shown } }

        rebuildIslands()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIslands() }
        }
        preferences.$externalDisplays.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildIslands() } }
            .store(in: &cancellables)

        // The audio tap only runs while music plays, so the recording indicator isn't on all day.
        // Exception: a title-only browser tab can't report "resumed", so after a pause the tap
        // keeps listening for a while to hear the music come back.
        center.$track.combineLatest(center.$pausedAt, preferences.$liveWaveform)
            .map { track, pausedAt, enabled -> Bool in
                guard enabled, let track else { return false }
                if track.isPlaying { return true }
                return track.note != nil && (pausedAt.map { Date().timeIntervalSince($0) < 600 } ?? false)
            }
            .removeDuplicates()
            .sink { AudioLevels.shared.setListening($0) }
            .store(in: &cancellables)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Brimtune")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// One island per display: hugging the notch on the built-in screen, floating
    /// iPhone-style on external ones.
    private func rebuildIslands() {
        let screens = NSScreen.screens.filter { preferences.externalDisplays || $0.safeAreaInsets.top > 0 }
        let wanted = screens.isEmpty ? [NSScreen.main].compactMap { $0 } : screens
        let current = islands.map(\.screen)
        guard wanted.map(\.frame) != current.map(\.frame) else { return }
        islands.forEach { $0.tearDown() }
        islands = wanted.map { screen in
            let island = IslandController(screen: screen, center: center, audio: audio, activities: activities, preferences: preferences)
            island.onOpenStage = { [weak self] in self?.stage.show() }
            island.onOpenSettings = { [weak self] in self?.showSettings() }
            island.suppressed = stage.isShown
            return island
        }
    }

    // Rebuilt on open so the title and play state are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let track = center.track {
            let header = NSMenuItem(title: "\(track.title) — \(track.artist)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(item(track.isPlaying ? "Pause" : "Play", #selector(playPause)))
            menu.addItem(item("Next Track", #selector(nextTrack)))
            menu.addItem(item("Previous Track", #selector(previousTrack)))
        } else {
            let header = NSMenuItem(title: "Nothing Playing", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        menu.addItem(.separator())
        menu.addItem(timerMenuItem())
        if activities.stopwatch == nil {
            menu.addItem(item("Start Stopwatch", #selector(startStopwatch)))
        } else {
            menu.addItem(item(activities.stopwatch?.isRunning == true ? "Pause Stopwatch" : "Resume Stopwatch", #selector(toggleStopwatch)))
            menu.addItem(item("Reset Stopwatch", #selector(resetStopwatch)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Full-Screen Player", #selector(openStage), key: "f"))
        menu.addItem(item("Listening History…", #selector(openHistory), key: "y"))
        let preview = item("Preview Lock Screen", #selector(previewLock), key: "l")
        preview.state = lockScreen.isPreviewing ? .on : .off
        menu.addItem(preview)
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Brimtune", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func playPause() { center.perform(.togglePlayPause) }
    @objc private func nextTrack() { center.perform(.next) }
    @objc private func previousTrack() { center.perform(.previous) }
    @objc private func openStage() { stage.show() }
    @objc private func previewLock() { lockScreen.preview() }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openHistory() { showHistory() }
    @objc private func startStopwatch() { activities.startStopwatch() }
    @objc private func toggleStopwatch() { activities.toggleStopwatch() }
    @objc private func resetStopwatch() { activities.resetStopwatch() }
    @objc private func cancelTimer() { activities.cancelTimer() }
    @objc private func startTimer(_ sender: NSMenuItem) { activities.startTimer(minutes: Double(sender.tag)) }

    private func timerMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: activities.timer == nil ? "Timer" : "Timer (running)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for minutes in [1, 3, 5, 10, 15, 25, 30, 45, 60] {
            let entry = item(minutes == 60 ? "1 hour" : "\(minutes) min", #selector(startTimer(_:)))
            entry.tag = minutes
            sub.addItem(entry)
        }
        if activities.timer != nil {
            sub.addItem(.separator())
            sub.addItem(item("Cancel Timer", #selector(cancelTimer)))
        }
        root.submenu = sub
        return root
    }

    private func showHistory() {
        if historyWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Listening History"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: HistoryView(history: history))
            window.center()
            historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Brimtune Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(
                preferences: preferences,
                previewLockScreen: { [weak self] in self?.lockScreen.preview() }
            ))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
