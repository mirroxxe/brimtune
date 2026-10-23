import AppKit

/// Reads Apple Music or Spotify through their AppleScript dictionaries. Both apps
/// broadcast a distributed notification on every state change, so scripts only run
/// when something happened, plus a slow resync while the player is open.
final class ScriptableSource: NowPlayingSource {
    enum Player {
        case music, spotify

        var bundleID: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            }
        }

        var notification: String {
            switch self {
            case .music: "com.apple.Music.playerInfo"
            case .spotify: "com.spotify.client.PlaybackStateChanged"
            }
        }
    }

    let player: Player
    let priority = 1
    var onChange: ((TrackSnapshot?) -> Void)?
    var onArtwork: ((String, NSImage) -> Void)?

    private let queue = DispatchQueue(label: "brimtune.applescript", qos: .userInitiated)
    private var timer: Timer?
    private var artworkTrackID: String?
    private var quietUntil = Date.distantPast
    private lazy var stateScript = compile(stateSource)

    init(player: Player) {
        self.player = player
    }

    func start() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) != nil else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: .init(player.notification), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, Self.bundleID(of: note) == self.player.bundleID else { return }
            // Scripting a just-quit app would relaunch it, so stay quiet for a moment.
            self.quietUntil = Date().addingTimeInterval(3)
            self.artworkTrackID = nil
            self.onChange?(nil)
        }
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, Self.bundleID(of: note) == self.player.bundleID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
        }

        // Change notifications do the real work; this only resyncs the position.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 1
        refresh()
    }

    private var isRunning: Bool {
        Date() > quietUntil && !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    func refresh() {
        guard isRunning else { return }
        queue.async { [weak self] in
            guard let self, self.isRunning, let script = self.stateScript else { return }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            guard error == nil, let text = result.stringValue else { return }
            let snapshot = self.parse(text)
            let artworkURL = self.lastArtworkURL
            DispatchQueue.main.async {
                self.onChange?(snapshot)
                if let snapshot, snapshot.id != self.artworkTrackID {
                    self.artworkTrackID = snapshot.id
                    self.loadArtwork(for: snapshot.id, url: artworkURL)
                }
            }
        }
    }

    // MARK: Commands

    func perform(_ command: PlayerCommand) {
        let body: String
        switch (player, command) {
        case (_, .togglePlayPause): body = "playpause"
        case (_, .next): body = "next track"
        case (_, .previous): body = "previous track"
        case (.music, .toggleShuffle): body = "set shuffle enabled to not shuffle enabled"
        case (.spotify, .toggleShuffle): body = "set shuffling to not shuffling"
        case (.music, .cycleRepeat):
            body = """
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """
        case (.spotify, .cycleRepeat): body = "set repeating to not repeating"
        case (.music, .like(let on)): body = "try\nset favorited of current track to \(on)\nend try"
        case (.spotify, .like), (_, .playQueueItem): return
        }
        run(body)
    }

    func seek(to seconds: TimeInterval) {
        run("set player position to \(String(format: "%.2f", seconds))")
    }

    private func run(_ body: String) {
        guard isRunning else { return }
        let source = "tell application id \"\(player.bundleID)\"\n\(body)\nend tell"
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.refresh() }
        }
    }

    // MARK: State

    private var stateSource: String {
        let sep = "set sep to character id 31"
        switch player {
        case .music:
            return """
            tell application id "com.apple.Music"
                try
                    set s to player state as string
                    if s is "stopped" then return "stopped"
                    set t to current track
                    \(sep)
                    set fav to "missing"
                    try
                        set fav to (favorited of t) as string
                    end try
                    return s & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & ((player position) as string) & sep & (shuffle enabled as string) & sep & (song repeat as string) & sep & fav & sep & ""
                on error
                    return "stopped"
                end try
            end tell
            """
        case .spotify:
            return """
            tell application id "com.spotify.client"
                try
                    set s to player state as string
                    if s is "stopped" then return "stopped"
                    set t to current track
                    \(sep)
                    return s & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (((duration of t) / 1000) as string) & sep & ((player position) as string) & sep & (shuffling as string) & sep & (repeating as string) & sep & "missing" & sep & (artwork url of t)
                on error
                    return "stopped"
                end try
            end tell
            """
        }
    }

    private var lastArtworkURL: URL?

    private func parse(_ text: String) -> TrackSnapshot? {
        let f = text.components(separatedBy: "\u{1F}")
        guard f.count >= 10 else { return nil }
        // AppleScript formats reals with the user's decimal separator.
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let repeatMode: RepeatMode = switch f[7] {
        case "one": .one
        case "all", "true": .all
        default: .off
        }
        lastArtworkURL = URL(string: f[9])
        return TrackSnapshot(
            title: f[1], artist: f[2], album: f[3],
            duration: number(f[4]), elapsed: number(f[5]), sampledAt: Date(),
            isPlaying: f[0] == "playing",
            shuffle: f[6] == "true", repeatMode: repeatMode,
            liked: f[8] == "missing" ? nil : f[8] == "true",
            bundleID: player.bundleID,
            supportsLike: player == .music && f[8] != "missing"
        )
    }

    private func loadArtwork(for trackID: String, url: URL?) {
        switch player {
        case .spotify:
            guard let url else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.onArtwork?(trackID, image) }
            }.resume()
        case .music:
            let source = """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """
            queue.async { [weak self] in
                guard let self, self.isRunning else { return }
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                guard let data = result?.data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { self.onArtwork?(trackID, image) }
            }
        }
    }

    private func compile(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return error == nil ? script : nil
    }

    private static func bundleID(of note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }
}
