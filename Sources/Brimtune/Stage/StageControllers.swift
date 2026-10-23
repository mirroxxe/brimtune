import AppKit
import Combine
import SwiftUI

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class LockPanel: NSPanel {
    // Never take keyboard focus from the login window's password field.
    override var canBecomeKey: Bool { false }
}

/// The full-screen "now playing" stage, opened from the island or the menu bar.
@MainActor
final class StageController {
    private let center: NowPlayingCenter
    private let audio: AudioMonitor
    private let preferences: Preferences
    private let history: HistoryStore
    private let presentation = StagePresentation()
    private var window: NSWindow?
    private var keyMonitor: Any?
    var onSettings: (() -> Void)?
    var onHistory: (() -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?

    var isShown: Bool { window?.isVisible == true }

    init(center: NowPlayingCenter, audio: AudioMonitor, preferences: Preferences, history: HistoryStore) {
        self.center = center
        self.audio = audio
        self.preferences = preferences
        self.history = history
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard let screen = NSScreen.main else { return }
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1
        }
        presentation.show()
        onVisibilityChange?(true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53: self?.hide(); return nil                                  // esc
            case 49: self?.center.perform(.togglePlayPause); return nil        // space
            case 124: self?.center.perform(.next); return nil                  // →
            case 123: self?.center.perform(.previous); return nil              // ←
            default: return event
            }
        }
    }

    func hide() {
        guard let window else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        presentation.hide()
        onVisibilityChange?(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { window.orderOut(nil) }
        })
    }

    private func makeWindow() -> NSWindow {
        let window = KeyableWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .statusBar
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let presentation = presentation, center = center, audio = audio, preferences = preferences, history = history
        window.contentView = NSHostingView(rootView: MountGate(presentation: presentation) {
            StageView(
                context: .player, center: center, audio: audio, preferences: preferences, presentation: presentation, history: history,
                onClose: { [weak self] in self?.hide() },
                onSettings: { [weak self] in self?.hide(); self?.onSettings?() },
                onHistory: { [weak self] in self?.hide(); self?.onHistory?() }
            )
        })
        return window
    }
}

/// Shows now playing over the lock screen, either as a floating glass card or as
/// the full stage, and hides it the moment the session unlocks.
@MainActor
final class LockScreenController {
    private let center: NowPlayingCenter
    private let preferences: Preferences
    private let lock: LockMonitor
    private let cardPresentation = StagePresentation()
    private let stagePresentation = StagePresentation()
    private let cardPanel: LockPanel
    private let stagePanel: LockPanel
    private var cancellables: Set<AnyCancellable> = []
    private var previewWork: DispatchWorkItem?
    private let cardSize = CGSize(width: 420, height: 260)

    @Published private(set) var isPreviewing = false

    init(center: NowPlayingCenter, audio: AudioMonitor, preferences: Preferences, lock: LockMonitor, history: HistoryStore) {
        self.center = center
        self.preferences = preferences
        self.lock = lock

        cardPanel = Self.makePanel()
        let card = cardPresentation, stage = stagePresentation
        cardPanel.contentView = FirstMouseHostingView(rootView: MountGate(presentation: card) {
            LockCardView(center: center, audio: audio, presentation: card)
        })
        stagePanel = Self.makePanel()
        stagePanel.contentView = FirstMouseHostingView(rootView: MountGate(presentation: stage) {
            StageView(context: .lockScreen, center: center, audio: audio, preferences: preferences, presentation: stage,
                      history: history)
        })

        layout()
        // Windows must be on screen once before they can move into the lock-screen space.
        for panel in [cardPanel, stagePanel] {
            panel.orderFrontRegardless()
            LockScreenSpace.adopt(panel)
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }

        Publishers.CombineLatest4(lock.$isLocked, $isPreviewing, preferences.$lockScreenEnabled, preferences.$lockScreenStyle)
            .combineLatest(center.$track.map { $0 != nil }.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] values, hasTrack in
                let (locked, previewing, enabled, style) = values
                self?.apply(show: (locked && enabled || previewing) && hasTrack, style: style)
            }
            .store(in: &cancellables)
    }

    func preview() {
        isPreviewing.toggle()
        previewWork?.cancel()
        guard isPreviewing else { return }
        let work = DispatchWorkItem { [weak self] in self?.isPreviewing = false }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    private static func makePanel() -> LockPanel {
        let panel = LockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let f = screen.frame
        // The band between the system clock (top) and the user picture / password field (bottom).
        stagePanel.setFrame(NSRect(x: f.minX, y: f.minY + f.height * 0.2, width: f.width, height: f.height * 0.52), display: true)
        // Below the system clock, above the unlock prompt.
        cardPanel.setFrame(NSRect(x: f.midX - cardSize.width / 2, y: f.minY + f.height * 0.36 - cardSize.height / 2,
                                  width: cardSize.width, height: cardSize.height), display: true)
    }

    private func apply(show: Bool, style: LockScreenStyle) {
        set(cardPanel, cardPresentation, visible: show && style == .card)
        set(stagePanel, stagePresentation, visible: show && style == .stage)
    }

    private func set(_ panel: NSPanel, _ presentation: StagePresentation, visible: Bool) {
        guard presentation.isVisible != visible else { return }
        if visible { presentation.show() } else { presentation.hide() }
        panel.ignoresMouseEvents = !visible
        brimtuneLog("lock-screen player %@", visible ? "shown" : "hidden")
        if visible {
            // The SwiftUI content animates itself in; the window just has to be there.
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            // Re-assert lock-screen membership in case the window server reset it.
            LockScreenSpace.adopt(panel)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                panel.animator().alphaValue = 0
            }
        }
    }
}
