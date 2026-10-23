import AppKit
import CoreBluetooth
import CoreServices
import EventKit
import SwiftUI

/// Live state of everything the setup guide asks for, re-checked every second
/// while the guide is open so rows flip to "Allowed" the moment macOS agrees.
@MainActor
final class PermissionStatus: ObservableObject {
    enum State: Equatable { case unknown, needed, granted, denied, unavailable }

    /// May Brimtune send Apple Events to each browser (System Settings → Automation).
    @Published private(set) var automation: [BrowserSource.Browser: State] = [:]
    /// Has "Allow JavaScript from Apple Events" been switched on in each browser.
    @Published private(set) var javaScript: [BrowserSource.Browser: Bool] = [:]
    @Published private(set) var calendar: State = .unknown
    @Published private(set) var bluetooth: State = .unknown
    @Published var audioRequested = UserDefaults.standard.bool(forKey: "audioCaptureAsked")

    private let center: NowPlayingCenter
    private var timer: Timer?

    init(center: NowPlayingCenter) {
        self.center = center
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        calendar = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .needed
        default: .denied
        }
        bluetooth = switch CBCentralManager.authorization {
        case .allowedAlways: .granted
        case .notDetermined: .needed
        default: .denied
        }
        for browser in BrowserSource.Browser.allCases {
            let reading = center.hasPageAccess(in: browser)
            AppleScriptQueue.shared.async { [weak self] in
                let state = Self.automationState(for: browser.bundleID, ask: false)
                // Only probe once macOS has said yes: probing earlier would bring up its prompt.
                let works = reading || (state == .granted && Self.javaScriptWorks(in: browser))
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.automation[browser] != state { self.automation[browser] = state }
                    if self.javaScript[browser] != works { self.javaScript[browser] = works }
                }
            }
        }
    }

    /// Runs a one-line script in the browser's front tab: browsers refuse with an error
    /// until "Allow JavaScript from Apple Events" is on. A page Brimtune follows counts too
    /// (see `NowPlayingCenter.hasPageAccess`), for when the front tab is a blank one.
    nonisolated static func javaScriptWorks(in browser: BrowserSource.Browser) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { return false }
        let source = switch browser {
        case .safari: "tell application id \"com.apple.Safari\" to do JavaScript \"1+1\" in current tab of front window"
        case .chrome: "tell application id \"com.google.Chrome\" to execute active tab of front window javascript \"1+1\""
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && (result?.int32Value == 2 || result?.stringValue == "2")
    }

    /// Whether we may send Apple Events to an app. macOS can only answer while
    /// that app is running; asking shows the system prompt.
    nonisolated static func automationState(for bundleID: String, ask: Bool) -> State {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return .unavailable }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .needed }
        var target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc!.pointee
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .needed
        }
    }

    // MARK: Requests

    func requestAutomation(for browser: BrowserSource.Browser) {
        let id = browser.bundleID
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            // macOS can only ask about an app that is running.
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            let state = Self.automationState(for: id, ask: true)
            await MainActor.run { self?.automation[browser] = state }
        }
    }

    private var bluetoothManager: CBCentralManager?

    func requestBluetooth() {
        // Creating a manager is what makes macOS ask.
        bluetoothManager = CBCentralManager(delegate: nil, queue: nil)
    }

    func requestAudio() {
        // Starting the tap once brings up the "capture audio" prompt.
        UserDefaults.standard.set(true, forKey: "audioCaptureAsked")
        audioRequested = true
        AudioLevels.shared.setListening(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [center] in
            if center.track?.isPlaying != true { AudioLevels.shared.setListening(false) }
        }
    }

    func open(_ browser: BrowserSource.Browser) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func isInstalled(_ browser: BrowserSource.Browser) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil
    }

    func openSystemSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Shows the setup guide on first launch, and again from the menu.
@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private let center: NowPlayingCenter
    private let activities: ActivityCenter
    private let preferences: Preferences

    init(center: NowPlayingCenter, activities: ActivityCenter, preferences: Preferences) {
        self.center = center
        self.activities = activities
        self.preferences = preferences
    }

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "onboardingDone") else { return }
        show()
    }

    func show() {
        if window == nil {
            let status = PermissionStatus(center: center)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            // Always dark, like the island itself: text colours then match the
            // background whatever the system theme is.
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // The blur is the window's own content view, so it always fills the window;
            // SwiftUI sits on top of it.
            let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 620, height: 520))
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            let hosting = NSHostingView(rootView: OnboardingView(
                status: status, preferences: preferences, activities: activities,
                finish: { [weak self] in self?.finish() }
            ))
            hosting.frame = blur.bounds
            hosting.autoresizingMask = [.width, .height]
            blur.addSubview(hosting)
            window.contentView = blur
            window.center()
            self.window = window
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    status.stop()
                    UserDefaults.standard.set(true, forKey: "onboardingDone")
                }
            }
            status.start()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        window?.close()
    }
}

// MARK: - Views

private struct OnboardingView: View {
    @ObservedObject var status: PermissionStatus
    @ObservedObject var preferences: Preferences
    let activities: ActivityCenter
    var finish: () -> Void

    @State private var page = 0
    @State private var forward = true
    @StateObject private var listening = Listening()

    private enum Step { case welcome, music, browserSwitch, extras, done }

    /// The browser page only appears for people who listen in a browser.
    private var steps: [Step] {
        listening.browsers.isEmpty ? [.welcome, .music, .extras, .done] : [.welcome, .music, .browserSwitch, .extras, .done]
    }
    private var pages: Int { steps.count }
    private var step: Step { steps[min(page, steps.count - 1)] }

    /// On the browser page, every chosen browser must have its switch on (or the user says so).
    private var canContinue: Bool {
        step != .browserSwitch || listening.browsers.allSatisfy { status.javaScript[$0] == true || listening.confirmed.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: WelcomePage()
                case .music: MusicPage(status: status, listening: listening)
                case .browserSwitch: BrowserSwitchPage(status: status, listening: listening)
                case .extras: ExtrasPage(status: status, preferences: preferences, activities: activities)
                case .done: DonePage()
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .clipped()

            HStack {
                if page > 0 {
                    Button("Back") { go(-1) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: i == page ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
                Spacer()
                Button(page == pages - 1 ? "Start Using Brimtune" : "Continue") {
                    page == pages - 1 ? finish() : go(1)
                }
                .disabled(!canContinue)
                .help(canContinue ? "" : "Turn the switch on in each browser, or tick “I've turned it on”.")
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 620, height: 520)
        .background {
            // The icon's glow: deep night with pink, violet and blue light.
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.09).opacity(0.72)
                RadialGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.55).opacity(0.28), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color(red: 0.35, green: 0.45, blue: 1).opacity(0.26), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color(red: 1, green: 0.62, blue: 0.25).opacity(0.14), .clear],
                               center: .bottom, startRadius: 0, endRadius: 300)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { page = max(0, min(pages - 1, page + delta)) }
    }
}

private struct PageHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title).font(.system(size: 24, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            VStack(spacing: 8) {
                Text("Welcome to Brimtune").font(.system(size: 28, weight: .bold))
                Text("Your notch, playing along. Music, lyrics and little live moments, right at the top of your screen.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "music.note", tint: .pink, title: "Now playing in the notch",
                        text: "Apple Music, Spotify and YouTube Music. Hover to open, click to control.")
                Feature(symbol: "quote.bubble.fill", tint: .orange, title: "Lyrics that follow along",
                        text: "Word by word, on the full-screen player and the lock screen.")
                Feature(symbol: "lock.fill", tint: .blue, title: "On the lock screen",
                        text: "Your player, playlists and lyrics before you even sign in.")
            }
            .padding(.top, 4)
        }
    }

    private struct Feature: View {
        let symbol: String
        let tint: Color
        let title: String
        let text: String

        var body: some View {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One permission: what it's for, and where it stands.
private struct PermissionRow<Action: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action()
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StateBadge: View {
    let state: PermissionStatus.State
    var ask: () -> Void
    var fix: () -> Void = {}

    var body: some View {
        switch state {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .denied:
            Button("Open Settings", action: fix).controlSize(.small)
        case .unavailable:
            Text("Not installed").font(.system(size: 12)).foregroundStyle(.tertiary)
        case .needed, .unknown:
            Button("Allow", action: ask).controlSize(.small).buttonStyle(.borderedProminent)
        }
    }
}

/// Where the user listens, remembered for the browser page that follows.
@MainActor
private final class Listening: ObservableObject {
    @Published var safari: Bool { didSet { UserDefaults.standard.set(safari, forKey: "listensInSafari") } }
    @Published var chrome: Bool { didSet { UserDefaults.standard.set(chrome, forKey: "listensInChrome") } }
    @Published var apps: Bool { didSet { UserDefaults.standard.set(apps, forKey: "listensInApps") } }
    /// Browsers whose switch the user says is on, though we couldn't see it yet.
    @Published var confirmed: Set<BrowserSource.Browser> = []

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["listensInSafari": true, "listensInChrome": false, "listensInApps": false])
        safari = d.bool(forKey: "listensInSafari")
        chrome = d.bool(forKey: "listensInChrome")
        apps = d.bool(forKey: "listensInApps")
    }

    var browsers: [BrowserSource.Browser] {
        (safari ? [.safari] : []) + (chrome ? [.chrome] : [])
    }
}

private struct MusicPage: View {
    @ObservedObject var status: PermissionStatus
    @ObservedObject var listening: Listening

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(symbol: "music.note.house.fill", tint: .pink, title: "Where do you listen?",
                       subtitle: "Pick everything you use. For YouTube Music or Spotify on the web,\nBrimtune needs your browser's OK.")
            HStack(spacing: 10) {
                Choice(title: "Safari", symbol: "safari.fill", on: $listening.safari, enabled: status.isInstalled(.safari))
                Choice(title: "Chrome", symbol: "globe", on: $listening.chrome, enabled: status.isInstalled(.chrome))
                Choice(title: "Music or Spotify app", symbol: "music.note", on: $listening.apps, enabled: true)
            }
            VStack(spacing: 10) {
                ForEach(listening.browsers, id: \.self) { browser in
                    PermissionRow(symbol: browser == .safari ? "safari.fill" : "globe", tint: .blue,
                                  title: "Let Brimtune control \(browser.name)",
                                  detail: "To see what's playing there and send play, pause and skip. macOS asks once.") {
                        StateBadge(state: status.automation[browser] ?? .unknown,
                                   ask: { status.requestAutomation(for: browser) },
                                   fix: { status.openSystemSettings("Privacy_Automation") })
                    }
                }
                if listening.apps {
                    PermissionRow(symbol: "music.note", tint: .pink, title: "Music and Spotify apps",
                                  detail: "Nothing to do now: macOS asks the first time they play.") {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private struct Choice: View {
        let title: String
        let symbol: String
        @Binding var on: Bool
        let enabled: Bool

        var body: some View {
            Button { on.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Color.accentColor : .secondary)
                    Image(systemName: symbol)
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(on ? 0.12 : 0.05), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .help(enabled ? "" : "\(title) isn't installed.")
        }
    }
}

/// The one step people miss: each browser only lets Brimtune read the page once
/// "Allow JavaScript from Apple Events" is on. Continue waits for it.
private struct BrowserSwitchPage: View {
    @ObservedObject var status: PermissionStatus
    @ObservedObject var listening: Listening

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("One important switch").font(.system(size: 24, weight: .bold))
                Text("Turn this on in each browser you listen in. Without it Brimtune only sees the song's name:\nno covers, progress, playlists or lyrics that keep time.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(listening.browsers, id: \.self) { browser in
                Card(browser: browser, works: status.javaScript[browser] == true,
                     confirmed: Binding(get: { listening.confirmed.contains(browser) },
                                        set: { if $0 { listening.confirmed.insert(browser) } else { listening.confirmed.remove(browser) } }),
                     open: { status.open(browser) })
            }
        }
    }

    private struct Card: View {
        let browser: BrowserSource.Browser
        let works: Bool
        @Binding var confirmed: Bool
        let open: () -> Void

        private var steps: [String] {
            switch browser {
            case .safari: [
                "Safari → Settings → Advanced: turn on “Show features for web developers”.",
                "Settings → Developer: turn on “Allow JavaScript from Apple Events”.",
            ]
            case .chrome: [
                "In Chrome's menu bar: View → Developer.",
                "Click “Allow JavaScript from Apple Events” so it has a tick.",
            ]
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: browser == .safari ? "safari.fill" : "globe").foregroundStyle(.blue)
                    Text(browser.name).font(.system(size: 14, weight: .bold))
                    Spacer()
                    if works {
                        Label("On, Brimtune can read it", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                    } else {
                        Button("Open \(browser.name)", action: open).controlSize(.small)
                    }
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.orange)
                            .frame(width: 18, height: 18).background(Color.orange.opacity(0.16), in: Circle())
                        Text(step).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !works {
                    Toggle("I've turned it on", isOn: $confirmed)
                        .toggleStyle(.checkbox).font(.system(size: 12))
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(works ? Color.green.opacity(0.5) : Color.orange.opacity(0.45), lineWidth: 1))
        }
    }
}

private struct ExtrasPage: View {
    @ObservedObject var status: PermissionStatus
    @ObservedObject var preferences: Preferences
    let activities: ActivityCenter

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(symbol: "sparkles", tint: .orange, title: "A few extras",
                       subtitle: "All optional. Skip anything you don't want; you can change it later in Settings.")
            VStack(spacing: 10) {
                PermissionRow(symbol: "waveform", tint: .pink, title: "Waveform that follows the music",
                              detail: "Listens to what your Mac plays. Analysed in memory, never recorded or sent anywhere.") {
                    if status.audioRequested {
                        Label("Asked", systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    } else {
                        Button("Allow", action: status.requestAudio).controlSize(.small).buttonStyle(.borderedProminent)
                    }
                }
                PermissionRow(symbol: "calendar", tint: .red, title: "Upcoming meetings",
                              detail: "A countdown in the island five minutes before a meeting, with a Join button.") {
                    StateBadge(state: status.calendar, ask: activities.requestCalendarAccess,
                               fix: { status.openSystemSettings("Privacy_Calendars") })
                }
                PermissionRow(symbol: "airpods", tint: .blue, title: "AirPods battery",
                              detail: "Shows the battery level when your headphones connect.") {
                    StateBadge(state: status.bluetooth, ask: status.requestBluetooth,
                               fix: { status.openSystemSettings("Privacy_Bluetooth") })
                }
                PermissionRow(symbol: "power", tint: .green, title: "Open at login",
                              detail: "Start Brimtune automatically when you turn on your Mac.") {
                    Toggle("", isOn: $preferences.launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }
}

private struct DonePage: View {
    var body: some View {
        VStack(spacing: 22) {
            PageHeader(symbol: "checkmark.seal.fill", tint: .green, title: "You're all set",
                       subtitle: "Brimtune lives in your notch and in the menu bar. A few things to try:")
            VStack(alignment: .leading, spacing: 14) {
                Tip(symbol: "cursorarrow.motionlines", text: "Hover the notch to open the island, with search and your playlists.")
                Tip(symbol: "lock.fill", text: "Lock your Mac to see the player, lyrics and playlists on the lock screen.")
                Tip(symbol: "arrow.up.left.and.arrow.down.right", text: "Click the cover for the full-screen player.")
                Tip(symbol: "capsule.fill", text: "The menu bar icon has timers, history and settings.")
            }
        }
    }

    private struct Tip: View {
        let symbol: String
        let text: String

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                Text(text).font(.system(size: 13))
            }
        }
    }
}
