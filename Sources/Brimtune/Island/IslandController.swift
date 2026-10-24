import AppKit
import Combine
import SwiftUI

enum IslandMode: Equatable {
    case hidden, idle, compact, peek, alert, expanded
}

/// Short-lived things the island drops down to announce.
enum IslandAlert: Equatable {
    case device(AudioOutput, battery: Int?)
    case timerDone
    case meeting(ActivityCenter.Meeting, startingNow: Bool)
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .idle
    @Published var alert: IslandAlert?
    /// The notch on built-in displays; a virtual gap between the wings on floating islands.
    @Published var notch = CGSize(width: 190, height: 32)
    @Published var hasNotch = true
    /// External displays get a detached, iPhone-style pill instead of a notch.
    @Published var floating = false
    /// 0…1 progress of the colour shimmer that runs across the island when a new
    /// cover lands; 1 is at rest (nothing visible).
    @Published var shimmer: CGFloat = 1

    // What the expanded island has to fit.
    @Published var hasTrack = false
    @Published var expandedTall = true
    @Published var hasQueue = false
    @Published var activityRows = 0
    /// The compact island shows a countdown on its right wing.
    @Published var compactActivity = false
    /// Measured height of the expanded content; 0 until it has been laid out once.
    @Published var expandedContentHeight: CGFloat = 0

    /// A playlist opened from the shelf; the expanded island shows its songs.
    @Published var openPlaylist: Playlist?

    // Song search at the bottom of the expanded island.
    @Published var searchQuery = ""
    @Published var searchResults: [SearchResult] = []
    @Published var searchFocused = false
    @Published var searchLoading = false
    /// While the user is searching the island stays open even if the pointer wanders off.
    var isSearching: Bool { searchFocused || !searchQuery.isEmpty }

    private var searchHeight: CGFloat {
        46 + (searchResults.isEmpty ? 0 : 8 + CGFloat(searchResults.count) * 44)
    }

    static let floatingInset: CGFloat = 6

    func size(for mode: IslandMode) -> CGSize {
        let w = notch.width, h = notch.height
        switch mode {
        case .hidden: return CGSize(width: w * 0.7, height: h)
        case .idle: return notch
        case .compact: return CGSize(width: w + 2 * (h + 16) + (compactActivity ? 44 : 0), height: h)
        case .peek: return CGSize(width: w + 2 * 96, height: h + 50)
        case .alert: return CGSize(width: w + 2 * 96, height: topReserve + 52)
        case .expanded:
            let rows = CGFloat(activityRows) * 44
            let body: CGFloat = (hasTrack
                ? (expandedTall ? 140 : 116) + (hasQueue ? 64 : 0) + rows
                : (activityRows > 0 ? 18 + rows : 96)) + searchHeight
            let height = expandedContentHeight > 0 ? expandedContentHeight : topReserve + body
            return CGSize(width: max(w + 2 * 120, 440), height: height)
        }
    }

    func radii(for mode: IslandMode) -> (top: CGFloat, bottom: CGFloat) {
        switch mode {
        case .hidden, .idle: (6, 10)
        case .compact: (8, 12)
        case .peek, .alert: (12, 24)
        case .expanded: (14, 34)
        }
    }
}

/// Takes keyboard focus only while the search field is in use; a click on play or
/// a playlist must not steal typing from the app you're working in.
private final class IslandPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
}

/// Owns one display's island panel: picks the island's mode from playback, hover,
/// activities and alerts, and keeps the panel click-through except over the island.
@MainActor
final class IslandController {
    let model = IslandModel()
    let screen: NSScreen
    private let panel: IslandPanel
    private let center: NowPlayingCenter
    private let audio: AudioMonitor
    private let activities: ActivityCenter
    private let preferences: Preferences
    private var cancellables: Set<AnyCancellable> = []

    private var hovering = false
    private var pinnedOpen = false
    private var peeking = false
    private var hoverWork: DispatchWorkItem?
    private var alertWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var lingerWork: DispatchWorkItem?
    private var monitors: [Any] = []
    private let panelSize = CGSize(width: 820, height: 720)
    private var searchTask: Task<Void, Never>?
    private static let pauseLinger: TimeInterval = 1.1

    /// Set while the full-screen player is up, which has its own controls.
    var suppressed = false {
        didSet { if suppressed != oldValue { update() } }
    }

    /// Set while an app is full screen on this island's display.
    var fullScreenHidden = false {
        didSet { if fullScreenHidden != oldValue { update() } }
    }

    var onOpenStage: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(screen: NSScreen, center: NowPlayingCenter, audio: AudioMonitor, activities: ActivityCenter, preferences: Preferences) {
        self.screen = screen
        self.center = center
        self.audio = audio
        self.activities = activities
        self.preferences = preferences

        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the lock-screen player panels (screen-saver level), so they never show through an open island.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        let root = IslandView(
            model: model, center: center, activities: activities,
            openStage: { [weak self] in self?.collapse(); self?.onOpenStage?() },
            openSettings: { [weak self] in self?.collapse(); self?.onOpenSettings?() },
            tapped: { [weak self] in self?.tapped() },
            playSearch: { [weak self] result in
                self?.center.play(result)
                self?.collapse()
            },
            dismissSearch: { [weak self] in self?.collapse() },
            requestKeyboard: { [weak self] in
                guard let self else { return }
                self.panel.allowsKey = true
                // A panel of an inactive app can look focused yet never get the keystrokes, which is
                // why the field needed several clicks; typing needs the app active.
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKey()
            }
        )
        panel.contentView = FirstMouseHostingView(rootView: root)

        layout()
        panel.orderFrontRegardless()
        adoptLockScreenSpace()

        observe()
        installMouseTracking()
        update(animated: false)
    }

    func tearDown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancellables.removeAll()
        panel.orderOut(nil)
    }

    // MARK: Layout

    /// The lock-screen space lives on the primary display (the one at the origin): a window
    /// moved into it from another display isn't drawn at all, so other displays keep a normal panel.
    private func adoptLockScreenSpace() {
        guard screen.frame.origin == .zero else { return }
        LockScreenSpace.adopt(panel)
    }

    private func layout() {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notch = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
            model.hasNotch = true
            model.floating = false
        } else {
            // A virtual gap between the wings, sized so the compact island is a wide pill.
            model.notch = CGSize(width: 96, height: 36)
            model.hasNotch = false
            model.floating = true
        }
        panel.setFrame(NSRect(x: frame.midX - panelSize.width / 2, y: frame.maxY - panelSize.height,
                              width: panelSize.width, height: panelSize.height), display: true)
        update(animated: false)
    }

    /// The island's current outline in screen coordinates.
    private func islandRect(for mode: IslandMode) -> NSRect {
        let frame = screen.frame
        let size = model.size(for: mode == .hidden ? .idle : mode)
        let top = model.floating ? IslandModel.floatingInset : 0
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - top - size.height, width: size.width, height: size.height)
    }

    // MARK: State

    private func observe() {
        center.$track.combineLatest(center.$pausedAt)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, pausedAt in
                self?.scheduleLinger(pausedAt)
                self?.refreshLayoutFlags()
                self?.update()
            }
            .store(in: &cancellables)

        center.trackChanged
            .dropFirst()
            .sink { [weak self] _ in self?.peek() }
            .store(in: &cancellables)

        // A new cover washes the island in the album's colour for a moment.
        center.$artwork
            .compactMap { $0.map(ObjectIdentifier.init) }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.flash() }
            .store(in: &cancellables)

        audio.events
            .sink { [weak self] event in
                guard case let .device(output, battery) = event else { return }
                self?.show(.device(output, battery: battery), for: 3.4)
            }
            .store(in: &cancellables)

        activities.alerts
            .sink { [weak self] alert in
                switch alert {
                case .timerDone: self?.show(.timerDone, for: 6)
                case let .meeting(meeting, now): self?.show(.meeting(meeting, startingNow: now), for: 6)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(activities.$timer, activities.$stopwatch, activities.$meeting)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refreshLayoutFlags()
                self?.update()
            }
            .store(in: &cancellables)

        model.$searchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(320), scheduler: RunLoop.main)
            .sink { [weak self] query in self?.search(query) }
            .store(in: &cancellables)

        model.$searchResults.map(\.count).removeDuplicates()
            .combineLatest(model.$searchFocused)
            .sink { [weak self] _, _ in self?.refreshMouseThrough() }
            .store(in: &cancellables)

        preferences.$islandEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
    }

    private func refreshLayoutFlags() {
        let track = center.track
        let rows = [activities.timer != nil, activities.stopwatch != nil, activities.meeting != nil].filter { $0 }.count
        withAnimation(Motion.snappy) {
            if model.hasTrack != (track != nil) { model.hasTrack = track != nil }
            if model.expandedTall != ((track?.duration ?? 0) > 0) { model.expandedTall = (track?.duration ?? 0) > 0 }
            if model.hasQueue != !(track?.upNext.isEmpty ?? true) { model.hasQueue = !(track?.upNext.isEmpty ?? true) }
            if model.activityRows != rows { model.activityRows = rows }
            if model.compactActivity != activities.hasLiveActivity { model.compactActivity = activities.hasLiveActivity }
        }
    }

    private var hasActivePlayback: Bool {
        guard let track = center.track else { return false }
        if track.isPlaying { return true }
        // Hold the paused state just long enough to see it, then tuck back into the notch.
        return center.pausedAt.map { Date().timeIntervalSince($0) < Self.pauseLinger } ?? false
    }

    private func resolveMode() -> IslandMode {
        guard preferences.islandEnabled, !suppressed, !fullScreenHidden else { return .hidden }
        if hovering || pinnedOpen { return .expanded }
        if model.alert != nil { return .alert }
        if peeking, center.track != nil { return .peek }
        if hasActivePlayback || activities.hasLiveActivity { return .compact }
        // Floating, the idle island stays as a small pill: something to see and hover.
        return .idle
    }

    private func update(animated: Bool = true) {
        let next = resolveMode()
        guard next != model.mode else { return }
        let growing = model.size(for: next).height > model.size(for: model.mode).height
            || model.size(for: next).width > model.size(for: model.mode).width
        if animated {
            withAnimation(growing ? Motion.open : Motion.close) { model.mode = next }
        } else {
            model.mode = next
        }
        if next == .expanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        refreshMouseThrough()
    }

    private func scheduleLinger(_ pausedAt: Date?) {
        lingerWork?.cancel()
        guard let pausedAt else { return }
        let work = DispatchWorkItem { [weak self] in self?.update() }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, Self.pauseLinger + 0.05 - Date().timeIntervalSince(pausedAt)), execute: work)
    }

    private func peek() {
        guard preferences.showTrackPeek, model.mode != .expanded else { return }
        peeking = true
        update()
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.peeking = false; self?.update() }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    private func flash() {
        guard model.mode != .hidden, model.mode != .idle else { return }
        model.shimmer = 0
        withAnimation(.easeInOut(duration: 1.6)) { model.shimmer = 1 }
    }

    private func show(_ alert: IslandAlert, for duration: TimeInterval) {
        guard preferences.islandEnabled, model.mode != .expanded else { return }
        if case .device = alert, !preferences.showHUDs { return }
        if model.alert != nil, model.mode == .alert {
            withAnimation(Motion.snappy) { model.alert = alert }
        } else {
            model.alert = alert
        }
        update()
        alertWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.model.alert = nil
            self?.update()
        }
        alertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            withAnimation(Motion.snappy) { model.searchResults = []; model.searchLoading = false }
            return
        }
        model.searchLoading = true
        searchTask = Task { [weak self] in
            let results = await MusicSearch.search(trimmed)
            guard !Task.isCancelled, let self, self.model.searchQuery.trimmingCharacters(in: .whitespaces) == trimmed else { return }
            withAnimation(Motion.open) {
                self.model.searchResults = results
                self.model.searchLoading = false
            }
        }
    }

    func collapse() {
        hovering = false
        pinnedOpen = false
        searchTask?.cancel()
        model.openPlaylist = nil
        if model.isSearching || !model.searchResults.isEmpty {
            model.searchQuery = ""
            model.searchResults = []
            model.searchFocused = false
            model.searchLoading = false
        }
        // Hand the keyboard back to the app that had it: the field shouldn't keep catching keystrokes.
        let wasKey = panel.isKeyWindow
        panel.makeFirstResponder(nil)
        panel.allowsKey = false
        // Give the keyboard back to the app that had it, unless a Brimtune window of its own is open.
        if wasKey, !NSApp.windows.contains(where: { $0 !== panel && $0.isVisible && $0.canBecomeKey }) {
            NSApp.deactivate()
        }
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
            adoptLockScreenSpace()
        }
        update()
    }

    private func tapped() {
        if model.mode == .alert {
            // Tapping an alert dismisses it.
            alertWork?.perform()
            return
        }
        guard model.mode != .expanded else { return }
        pinnedOpen = true
        update()
    }

    // MARK: Mouse

    private func installMouseTracking() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }) { monitors.append(m) }
        // A click anywhere else closes a pinned island.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pinnedOpen || self.model.isSearching, !self.isMouseInside(margin: 0) else { return }
                self.collapse()
            }
        }) { monitors.append(m) }
    }

    private func isMouseInside(margin: CGFloat) -> Bool {
        islandRect(for: model.mode).insetBy(dx: -margin, dy: -margin).contains(NSEvent.mouseLocation)
    }

    private func refreshMouseThrough() {
        // Called on every pointer move system-wide; touching the window when nothing
        // changed costs a window-server round trip each time.
        let ignore = !(model.mode != .hidden && isMouseInside(margin: 2))
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    private func mouseMoved() {
        // Far below the top of this island's screen nothing here can change; bail out cheaply.
        let mouse = NSEvent.mouseLocation
        let nearTop = screen.frame.contains(mouse) && mouse.y > screen.frame.maxY - model.size(for: model.mode).height - 40
        guard nearTop || hovering || pinnedOpen || !panel.ignoresMouseEvents else { return }
        refreshMouseThrough()
        guard preferences.islandEnabled, model.mode != .hidden || model.hasNotch else { return }
        let inside = isMouseInside(margin: model.mode == .expanded ? 12 : 2)
        if inside == (hovering || pinnedOpen) { hoverWork?.cancel(); return }
        // With something typed or found the island stays put (a click elsewhere or Esc closes it);
        // an empty field that merely has focus must not hold the island open.
        let typing = !model.searchQuery.isEmpty || !model.searchResults.isEmpty
        if !inside && typing { hoverWork?.cancel(); return }
        if inside && !preferences.expandOnHover { return }

        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let stillInside = self.isMouseInside(margin: self.model.mode == .expanded ? 12 : 2)
            guard stillInside == inside else { return }
            self.hovering = inside
            if !inside {
                self.pinnedOpen = false
                if self.model.searchFocused { self.collapse(); return }
            }
            self.update()
        }
        hoverWork = work
        // Open quickly; close after a short beat so brushing past the edge doesn't snap it shut.
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.05 : 0.1), execute: work)
    }
}
