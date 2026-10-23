import AppKit
import Combine
import SwiftUI

/// Merges every source into the single "what's playing" the UI shows, and routes
/// controls back to whichever source owns it.
@MainActor
final class NowPlayingCenter: ObservableObject {
    @Published private(set) var track: TrackSnapshot?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette = ArtworkPalette.fallback
    @Published private(set) var lyrics: Lyrics?
    /// Seconds added to the position when timing lyrics; reset for every song.
    @Published private(set) var lyricsOffset: TimeInterval = 0
    /// The user's playlists from the web player being followed.
    @Published private(set) var playlists: [Playlist] = []
    /// Songs per playlist id, loaded on demand and kept for the session.
    @Published private(set) var playlistSongs: [String: [PlaylistSong]] = [:]
    @Published private(set) var loadingPlaylists: Set<String> = []
    /// When playback last stopped; the island lingers a while on a paused track.
    @Published private(set) var pausedAt: Date?

    let trackChanged = PassthroughSubject<TrackSnapshot, Never>()

    private struct Entry {
        var snapshot: TrackSnapshot
        var lastPlayed: Date
    }

    private var sources: [NowPlayingSource] = []
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var activeSource: NowPlayingSource?
    private var artworkByTrack: [String: NSImage] = [:]
    private var artworkOrder: [String] = []
    private var optimisticUntil = Date.distantPast
    private let lyricsService = LyricsService()
    private var lyricsTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(preferences: Preferences) {
        self.preferences = preferences
        add(MediaRemoteSource())
        add(ScriptableSource(player: .music))
        add(ScriptableSource(player: .spotify))
        add(BrowserSource(browser: .safari))
        add(BrowserSource(browser: .chrome))

        preferences.$lyricsEnabled.removeDuplicates().sink { [weak self] enabled in
            guard let self else { return }
            if enabled, let track = self.track { self.loadLyrics(for: track) } else if !enabled { self.lyrics = nil }
        }.store(in: &cancellables)
    }

    private let preferences: Preferences

    private func add(_ source: NowPlayingSource) {
        sources.append(source)
        let key = ObjectIdentifier(source)
        source.onChange = { [weak self, weak source] snapshot in
            guard let self, let source else { return }
            if let snapshot {
                let lastPlayed = snapshot.isPlaying ? Date() : (self.entries[key]?.lastPlayed ?? .distantPast)
                self.entries[key] = Entry(snapshot: snapshot, lastPlayed: lastPlayed)
            } else {
                self.entries[key] = nil
            }
            _ = source
            self.recompute()
        }
        source.onArtwork = { [weak self] trackID, image in
            guard let self else { return }
            self.artworkByTrack[trackID] = image
            self.artworkOrder.removeAll { $0 == trackID }
            self.artworkOrder.append(trackID)
            // Decoded covers are a few MB each; keep only the recent ones.
            while self.artworkOrder.count > 8 {
                self.artworkByTrack[self.artworkOrder.removeFirst()] = nil
            }
            if self.track?.id == trackID { self.setArtwork(image) }
        }
        source.start()
    }

    private func recompute() {
        let best = sources
            .compactMap { source in entries[ObjectIdentifier(source)].map { (source, $0) } }
            .max { a, b in
                (a.1.snapshot.isPlaying ? 1 : 0, a.1.lastPlayed, a.0.priority)
                    < (b.1.snapshot.isPlaying ? 1 : 0, b.1.lastPlayed, b.0.priority)
            }

        guard let (source, entry) = best else {
            activeSource = nil
            if track != nil { track = nil; setArtwork(nil); lyrics = nil; pausedAt = nil }
            return
        }
        // Ignore a stale reading that would undo a tap the user just made.
        if Date() < optimisticUntil, entry.snapshot.id == track?.id { return }

        let previousBrowser = activeSource as? BrowserSource
        activeSource = source
        // Playlists belong to the browser (and account) the music is in.
        if let browser = source as? BrowserSource, previousBrowser != nil, browser !== previousBrowser {
            playlists = []
            playlistSongs = [:]
            refreshPlaylists()
        }
        var next = entry.snapshot
        if let current = track, current.id == next.id, current.liked != nil, next.liked == nil {
            next.liked = current.liked
        }
        let changed = next.id != track?.id
        if next.isPlaying { pausedAt = nil } else if track?.isPlaying != false || pausedAt == nil { pausedAt = Date() }
        if let track, track.isEquivalent(to: next) { return }
        track = next

        if changed {
            setArtwork(artworkByTrack[next.id])
            trackChanged.send(next)
            if preferences.lyricsEnabled { loadLyrics(for: next) }
        }
    }

    private func setArtwork(_ image: NSImage?) {
        withAnimation(.smooth(duration: 0.5)) { artwork = image }
        guard let image else { palette = .fallback; return }
        Task.detached(priority: .utility) {
            let palette = ArtworkPalette(image: image)
            await MainActor.run {
                withAnimation(.smooth(duration: 0.6)) { self.palette = palette }
            }
        }
    }

    private func loadLyrics(for track: TrackSnapshot) {
        lyricsTask?.cancel()
        lyrics = nil
        lyricsOffset = 0
        lyricsTask = Task { [lyricsService] in
            let result = await lyricsService.lyrics(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
            guard !Task.isCancelled, self.track?.id == track.id else { return }
            withAnimation(.smooth) { self.lyrics = result }
        }
    }

    // MARK: Controls

    func perform(_ command: PlayerCommand) {
        guard let source = activeSource, var t = track else { return }
        // Reflect the tap immediately; the player confirms a moment later.
        switch command {
        case .togglePlayPause:
            t.elapsed = t.position(at: Date())
            t.sampledAt = Date()
            t.isPlaying.toggle()
            pausedAt = t.isPlaying ? nil : Date()
            optimisticUntil = Date().addingTimeInterval(0.8)
        case .like(let on):
            t.liked = on
        case .toggleShuffle:
            t.shuffle = !(t.shuffle ?? false)
        case .cycleRepeat:
            t.repeatMode = switch t.repeatMode ?? .off { case .off: .all; case .all: .one; case .one: .off }
        case .next, .previous, .playQueueItem:
            break
        }
        withAnimation(.smooth(duration: 0.3)) { track = t }
        source.perform(command)
    }

    func seek(to seconds: TimeInterval) {
        guard let source = activeSource, var t = track else { return }
        t.elapsed = seconds
        t.sampledAt = Date()
        track = t
        optimisticUntil = Date().addingTimeInterval(1)
        source.seek(to: seconds)
    }

    private var playlistCovers: [String: URL] = [:]
    private var playlistTimer: Timer?
    private var playlistsFetchedAt = Date.distantPast

    /// Re-reads the sidebar's playlists: often until the tab shows up, then every
    /// couple of minutes since they rarely change.
    func startPlaylistRefresh() {
        refreshPlaylists()
        playlistTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.playlists.isEmpty || Date().timeIntervalSince(self.playlistsFetchedAt) > 120 { self.refreshPlaylists() }
            }
        }
        playlistTimer?.tolerance = 2
    }

    func refreshPlaylists() {
        playlistsFetchedAt = Date()
        guard let browser = followedBrowser else { return }
        browser.fetchPlaylists { [weak self] lists in
            guard let self, !lists.isEmpty else { return }
            let withCovers = lists.map { list -> Playlist in
                var list = list
                if list.artwork == nil { list.artwork = self.playlistCovers[list.id] }
                return list
            }
            if withCovers != self.playlists { withAnimation(.smooth) { self.playlists = withCovers } }
            self.loadCovers(for: withCovers)
        }
    }

    /// YouTube serves a cover for public and unlisted playlists through oEmbed;
    /// private ones keep the drawn cover.
    private func loadCovers(for lists: [Playlist]) {
        // Private playlists have no public cover; their first song's art stands in.
        for list in lists where list.artwork == nil && list.site == "YouTube Music" && playlistSongs[list.id] == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.playlists.first(where: { $0.id == list.id })?.artwork == nil else { return }
                self.loadSongs(for: list)
            }
        }
        for list in lists where list.artwork == nil && list.site == "YouTube Music" && !list.isLiked && playlistCovers[list.id] == nil {
            var url = URLComponents(string: "https://www.youtube.com/oembed")!
            url.queryItems = [.init(name: "url", value: "https://www.youtube.com/playlist?list=\(list.id)"), .init(name: "format", value: "json")]
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url.url!),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let cover = (json["thumbnail_url"] as? String).flatMap(URL.init(string:)) else { return }
                playlistCovers[list.id] = cover
                if let i = playlists.firstIndex(where: { $0.id == list.id }) {
                    withAnimation(.smooth) { playlists[i].artwork = cover }
                }
            }
        }
    }

    /// True once a YouTube Music / Spotify tab answers our JavaScript (Safari's
    /// "Allow JavaScript from Apple Events" is on).
    var browserHasPageAccess: Bool { followedBrowser != nil }

    private var followedBrowser: BrowserSource? {
        browsers.first(where: \.hasPageAccess)
    }

    /// Safari and Chrome, the one playing (or played last) first. Both can have a YouTube
    /// Music tab open, and search, playlists and songs belong in the one you listen in.
    private var browsers: [BrowserSource] {
        sources.compactMap { $0 as? BrowserSource }.sorted { a, b in
            if a === activeSource { return true }
            if b === activeSource { return false }
            let played = { (s: BrowserSource) in self.entries[ObjectIdentifier(s)]?.lastPlayed ?? .distantPast }
            return played(a) > played(b)
        }
    }

    func loadSongs(for playlist: Playlist, force: Bool = false) {
        guard force || playlistSongs[playlist.id] == nil, !loadingPlaylists.contains(playlist.id),
              let browser = followedBrowser else { return }
        loadingPlaylists.insert(playlist.id)
        browser.fetchSongs(of: playlist) { [weak self] songs in
            guard let self else { return }
            self.loadingPlaylists.remove(playlist.id)
            withAnimation(.smooth) { self.playlistSongs[playlist.id] = songs }
            // A private playlist without a cover borrows its first song's.
            if let i = self.playlists.firstIndex(where: { $0.id == playlist.id }), self.playlists[i].artwork == nil,
               let art = songs.first?.artwork {
                self.playlistCovers[playlist.id] = art
                withAnimation(.smooth) { self.playlists[i].artwork = art }
            }
        }
    }

    /// The browser holding a YouTube Music tab, playing or not.
    private var musicBrowser: BrowserSource? {
        browsers.first(where: \.followsYouTubeMusic)
    }

    func play(_ song: PlaylistSong, in playlist: Playlist) {
        if let browser = musicBrowser {
            browser.play(song, in: playlist)
        } else {
            NSWorkspace.shared.open(URL(string: "https://music.youtube.com/watch?v=\(song.id)&list=\(playlist.id)")!)
        }
    }

    func play(_ playlist: Playlist) {
        if playlist.site == "YouTube Music", musicBrowser == nil {
            NSWorkspace.shared.open(URL(string: "https://music.youtube.com/watch?list=\(playlist.id)")!)
            return
        }
        (musicBrowser ?? followedBrowser)?.play(playlist)
    }

    /// Plays a searched song in the YouTube Music tab being followed, or opens it.
    func play(_ result: SearchResult) {
        if let browser = musicBrowser {
            browser.playInYouTubeMusic(videoID: result.id, playlistID: nil)
        } else {
            NSWorkspace.shared.open(result.youTubeMusicURL)
        }
    }

    func nudgeLyrics(by delta: TimeInterval) {
        withAnimation(.smooth(duration: 0.25)) { lyricsOffset += delta }
    }

    /// The user clicked the line being sung: that line's time is "now".
    func syncLyrics(to time: TimeInterval) {
        lyricsOffset = 0
        seek(to: time)
    }

    func openPlayerApp() {
        let id = track?.bundleID ?? "com.apple.Music"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

// MARK: - Palette

struct ArtworkPalette: Equatable {
    var accent: Color
    var secondary: Color
    var background: Color

    static let fallback = ArtworkPalette(
        accent: Color(red: 0.55, green: 0.8, blue: 0.95),
        secondary: Color(red: 0.75, green: 0.6, blue: 0.95),
        background: Color(red: 0.08, green: 0.12, blue: 0.2)
    )

    /// Picks the most vivid colours of a downsampled cover rather than a muddy average.
    init(image: NSImage) {
        let side = 24
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { self = .fallback; return }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { self = .fallback; return }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var colors: [(h: CGFloat, s: CGFloat, b: CGFloat, score: CGFloat)] = []
        var avg = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
        for i in 0..<(side * side) {
            let r = CGFloat(px[i * 4]) / 255, g = CGFloat(px[i * 4 + 1]) / 255, b = CGFloat(px[i * 4 + 2]) / 255
            avg.r += r; avg.g += g; avg.b += b
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            colors.append((h, s, v, s * (0.35 + v)))
        }
        let n = CGFloat(side * side)
        avg = (avg.r / n, avg.g / n, avg.b / n)

        let ranked = colors.sorted { $0.score > $1.score }
        let top = ranked.prefix(max(8, ranked.count / 8))
        func mean(_ items: some Collection<(h: CGFloat, s: CGFloat, b: CGFloat, score: CGFloat)>) -> NSColor {
            // Average hue on the circle so reds near 0/1 don't cancel out.
            var x: CGFloat = 0, y: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            for c in items { x += cos(c.h * 2 * .pi); y += sin(c.h * 2 * .pi); s += c.s; b += c.b }
            let k = CGFloat(items.count)
            var h = atan2(y, x) / (2 * .pi); if h < 0 { h += 1 }
            return NSColor(hue: h, saturation: s / k, brightness: b / k, alpha: 1)
        }
        let accentNS = mean(top)
        var ah: CGFloat = 0, asat: CGFloat = 0, ab: CGFloat = 0
        accentNS.getHue(&ah, saturation: &asat, brightness: &ab, alpha: nil)
        let distinct = ranked.filter { abs($0.h - ah) > 0.12 && $0.s > 0.2 }.prefix(24)

        // Keep the accent readable on black: lift dark covers, tame neon ones.
        accent = Color(hue: ah, saturation: min(asat, 0.75), brightness: max(ab, 0.8))
        if distinct.isEmpty {
            secondary = Color(hue: ah, saturation: min(asat, 0.75) * 0.4, brightness: 0.95)
        } else {
            let sec = mean(distinct)
            var sh: CGFloat = 0, ss: CGFloat = 0, sb: CGFloat = 0
            sec.getHue(&sh, saturation: &ss, brightness: &sb, alpha: nil)
            secondary = Color(hue: sh, saturation: min(ss, 0.7), brightness: max(sb, 0.8))
        }
        background = Color(red: avg.r * 0.55, green: avg.g * 0.55, blue: avg.b * 0.55)
    }

    init(accent: Color, secondary: Color, background: Color) {
        self.accent = accent
        self.secondary = secondary
        self.background = background
    }
}
