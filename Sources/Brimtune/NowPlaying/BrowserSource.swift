import AppKit

/// YouTube Music and the Spotify web player running in Safari or Chrome. The page
/// is read with a little JavaScript sent over AppleScript, which each browser only
/// allows after "Allow JavaScript from Apple Events" is switched on. Until then the
/// tab title still tells us the song, but controls can't reach the page.
final class BrowserSource: NowPlayingSource {
    enum Browser {
        case safari, chrome

        var bundleID: String {
            switch self {
            case .safari: "com.apple.Safari"
            case .chrome: "com.google.Chrome"
            }
        }

        var enableHint: String {
            switch self {
            case .safari:
                "To show artwork and progress, let Brimtune read the Safari tab:\n\n1. Safari → Settings… → Advanced → turn on “Show features for web developers”.\n2. Open the new Developer tab in Settings and turn on “Allow JavaScript from Apple Events”."
            case .chrome:
                "To show artwork and progress, let Brimtune read the Chrome tab:\n\nIn Chrome’s menu bar choose View → Developer → Allow JavaScript from Apple Events."
            }
        }

        /// AppleScript that runs `js` (a variable) in tab `t`.
        var runJS: String {
            switch self {
            case .safari: "do JavaScript js in t"
            case .chrome: "execute t javascript js"
            }
        }

        var tabTitle: String {
            switch self {
            case .safari: "name of t"
            case .chrome: "title of t"
            }
        }
    }

    private enum Site {
        case youtubeMusic, spotify

        init?(url: String) {
            if url.contains("music.youtube.com") { self = .youtubeMusic }
            else if url.contains("open.spotify.com") { self = .spotify }
            else { return nil }
        }

        var displayName: String {
            switch self {
            case .youtubeMusic: "YouTube Music"
            case .spotify: "Spotify"
            }
        }
    }

    private struct Tab {
        let window: Int
        let index: Int
        let site: Site
        /// False when the browser refuses JavaScript from Apple Events; we then only know the tab title.
        let pageAccess: Bool
    }

    let browser: Browser
    let priority = 1
    var onChange: ((TrackSnapshot?) -> Void)?
    var onArtwork: ((String, NSImage) -> Void)?

    private let queue = DispatchQueue(label: "brimtune.browser", qos: .userInitiated)
    private var timer: Timer?
    private var activeTab: Tab?
    /// A YouTube Music tab, even when nothing is playing in it, so Brimtune can start music there.
    private var musicTab: Tab?
    private var artworkTrackID: String?
    private var lastPosition: (id: String, pos: Double, at: Date)?
    /// Title-only tabs can't report pause, so remember the pauses we sent.
    private var assumedPaused: Set<String> = []
    private var lastTitleOnlyID: String?
    // Title-only bookkeeping, touched only on `queue`.
    private var catalog: [String: CatalogEntry?] = [:]
    private var lookupsInFlight: Set<String> = []
    private var lookupPending = false
    private var clock: (key: String, anchor: Date, frozen: TimeInterval?)?
    private lazy var scanScript = compile(scanSource)

    init(browser: Browser) {
        self.browser = browser
    }

    func start() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.3
        refresh()
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    private var lastScan = Date.distantPast
    private var lastScanPlaying = false

    /// Scans every 1.5 s while music plays (position, lyrics), every 5 s otherwise.
    private func tick() {
        guard lastScanPlaying || Date().timeIntervalSince(lastScan) > 5 else { return }
        refresh()
    }

    private func refresh() {
        lastScan = Date()
        guard isRunning else {
            if activeTab != nil { activeTab = nil; onChange?(nil) }
            return
        }
        queue.async { [weak self] in
            guard let self, self.isRunning, let script = self.scanScript else { return }
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error).stringValue ?? ""
            let found = error == nil ? self.parse(output) : nil
            // A title-only song is held back until its catalog lookup lands, so it appears once, complete.
            if self.lookupPending { self.lookupPending = false; return }
            DispatchQueue.main.async { self.publish(found) }
        }
    }

    private func publish(_ found: (Tab, TrackSnapshot, URL?)?) {
        guard let (tab, snapshot, artURL) = found else {
            activeTab = nil
            onChange?(nil)
            return
        }
        activeTab = tab
        lastScanPlaying = snapshot.isPlaying
        onChange?(snapshot)
        if snapshot.id != artworkTrackID, let artURL {
            artworkTrackID = snapshot.id
            let trackID = snapshot.id
            URLSession.shared.dataTask(with: artURL) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.onArtwork?(trackID, image) }
            }.resume()
        }
    }

    // MARK: Reading

    private static let readJS = """
    (function(){
      var ms = navigator.mediaSession, md = ms && ms.metadata, o = {};
      o.state = ms ? ms.playbackState : '';
      if (md) {
        o.title = md.title; o.artist = md.artist; o.album = md.album;
        var a = md.artwork || [];
        if (a.length) o.art = a[a.length - 1].src;
      }
      var m = Array.prototype.slice.call(document.querySelectorAll('video,audio')).filter(function(e){ return e.duration > 0; })[0];
      if (m) { o.t = m.currentTime; o.d = m.duration; o.paused = m.paused; }
      var q = function(id){ var e = document.querySelector('[data-testid="' + id + '"]'); return e ? e.textContent : null; };
      o.pos = q('playback-position'); o.dur = q('playback-duration');
      var items = Array.prototype.slice.call(document.querySelectorAll('ytmusic-player-queue-item'));
      var cur = -1;
      items.forEach(function(e, i){ if (e.hasAttribute('selected')) cur = i; });
      if (cur >= 0) {
        var text = function(e, s){ var x = e.querySelector(s); return x ? x.textContent.trim() : ''; };
        o.queue = items.slice(cur + 1, cur + 4).map(function(e, k){
          var img = e.querySelector('img');
          return { i: cur + 1 + k, t: text(e, '.song-title'), a: text(e, '.byline'), img: img ? img.src : '' };
        });
      }
      return JSON.stringify(o);
    })()
    """

    private var scanSource: String {
        let js = Self.readJS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return """
        set js to "\(js)"
        set rs to character id 30
        set us to character id 31
        set out to ""
        tell application id "\(browser.bundleID)"
            -- Two Apple events for every window and tab, instead of one per tab.
            set wids to id of every window
            try
                set urlLists to URL of every tab of every window
            on error
                -- Some window without tabs (e.g. Settings) spoiled the bulk query; go window by window.
                set urlLists to {}
                repeat with w in windows
                    try
                        set end of urlLists to URL of every tab of w
                    on error
                        set end of urlLists to {}
                    end try
                end repeat
            end try
            repeat with wi from 1 to count of wids
                set wid to item wi of wids
                set urls to item wi of urlLists
                repeat with i from 1 to count of urls
                    set u to item i of urls
                    if u is missing value then set u to ""
                    if u contains "music.youtube.com" or u contains "open.spotify.com" then
                        set t to tab i of window id wid
                        try
                            set r to \(browser.runJS)
                        on error
                            set r to "!" & (\(browser.tabTitle))
                        end try
                        set out to out & wid & us & i & us & u & us & r & rs
                    end if
                end repeat
            end repeat
        end tell
        return out
        """
    }

    private func parse(_ output: String) -> (Tab, TrackSnapshot, URL?)? {
        var candidates: [(Tab, TrackSnapshot, URL?)] = []
        var musicTabs: [Tab] = []
        defer {
            // Prefer a tab we can script; among those, keep the one already in use.
            let usable = musicTabs.sorted { ($0.pageAccess ? 1 : 0) > ($1.pageAccess ? 1 : 0) }
            let next = usable.first { $0.window == musicTab?.window && $0.index == musicTab?.index && $0.pageAccess == usable.first?.pageAccess }
                ?? usable.first
            DispatchQueue.main.async { self.musicTab = next }
        }
        for record in output.components(separatedBy: "\u{1E}") where !record.isEmpty {
            let f = record.components(separatedBy: "\u{1F}")
            guard f.count >= 4, let window = Int(f[0]), let index = Int(f[1]), let site = Site(url: f[2]) else { continue }
            let payload = f[3...].joined(separator: "\u{1F}")
            let tab = Tab(window: window, index: index, site: site, pageAccess: !payload.hasPrefix("!"))
            if site == .youtubeMusic { musicTabs.append(tab) }
            if !tab.pageAccess {
                if let (s, art) = titleOnly(String(payload.dropFirst()), site: site) { candidates.append((tab, s, art)) }
            } else if let data = payload.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let (s, art) = snapshot(from: o, site: site) {
                candidates.append((tab, s, art))
            }
        }
        // The tab that's actually playing wins; otherwise the one we were already following.
        return candidates.first { $0.1.isPlaying }
            ?? candidates.first { $0.0.window == activeTab?.window && $0.0.index == activeTab?.index }
            ?? candidates.first
    }

    private func snapshot(from o: [String: Any], site: Site) -> (TrackSnapshot, URL?)? {
        guard let title = o["title"] as? String, !title.isEmpty else { return nil }
        let artist = o["artist"] as? String ?? ""
        let id = "\(title)|\(artist)"

        var position = o["t"] as? Double
        var duration = o["d"] as? Double
        if position == nil, let p = o["pos"] as? String { position = Self.seconds(p) }
        if duration == nil, let d = o["dur"] as? String { duration = Self.seconds(d) }

        var playing: Bool
        if let paused = o["paused"] as? Bool {
            playing = !paused
        } else if let state = o["state"] as? String, state == "playing" || state == "paused" {
            playing = state == "playing"
        } else if let last = lastPosition, last.id == id, let position {
            playing = position > last.pos
        } else {
            playing = false
        }
        if let position { lastPosition = (id, position, Date()) }

        let snapshot = TrackSnapshot(
            title: title, artist: artist, album: o["album"] as? String ?? "",
            duration: duration ?? 0, elapsed: position ?? 0, sampledAt: Date(),
            isPlaying: playing, shuffle: nil, repeatMode: nil, liked: nil,
            bundleID: browser.bundleID,
            queue: (o["queue"] as? [[String: Any]] ?? []).compactMap { q in
                guard let i = q["i"] as? Int, let t = q["t"] as? String, !t.isEmpty else { return nil }
                return QueueItem(id: i, title: t, artist: q["a"] as? String ?? "",
                                 artwork: (q["img"] as? String).flatMap(URL.init(string:)))
            },
            site: site.displayName
        )
        return (snapshot, (o["art"] as? String).flatMap(URL.init(string:)))
    }

    /// Without page access, fall back to the tab title so at least the song shows.
    /// Artwork, artist and length then come from Apple's public iTunes catalog, and
    /// the position is our own clock started when the title appeared.
    private func titleOnly(_ title: String, site: Site) -> (TrackSnapshot, URL?)? {
        var song = "", artist = ""
        switch site {
        case .spotify:
            // "Song • Artist" while playing, "Spotify – Web Player" otherwise.
            let parts = title.components(separatedBy: " • ")
            guard parts.count >= 2 else { return nil }
            song = parts[0]; artist = parts[1...].joined(separator: " • ")
        case .youtubeMusic:
            song = title
            for suffix in [" | YouTube Music", " - YouTube Music"] where song.hasSuffix(suffix) {
                song = String(song.dropLast(suffix.count))
            }
            guard !song.isEmpty, song != "YouTube Music" else { return nil }
        }
        let key = "\(song)|\(artist)"
        lastTitleOnlyID = key

        // Start the song clock the moment the title appears, not once the catalog answers.
        let now = Date()
        var c = clock?.key == key ? clock! : (key: key, anchor: now, frozen: nil)
        // Paused from Brimtune, or paused in the browser (the Mac has gone quiet).
        let paused = assumedPaused.contains(key) || AudioActivity.isSilent
        if paused, c.frozen == nil { c.frozen = now.timeIntervalSince(c.anchor) }
        if !paused, let frozen = c.frozen { c = (key, now.addingTimeInterval(-frozen), nil) }
        clock = c
        let elapsed = c.frozen ?? now.timeIntervalSince(c.anchor)

        guard let entry = catalog[key] else {
            lookUp(song: song, artist: artist, key: key)
            return nil
        }

        let snapshot = TrackSnapshot(
            title: song, artist: artist.isEmpty ? (entry?.artist ?? "") : artist,
            album: entry?.album ?? site.displayName, duration: entry?.duration ?? 0,
            elapsed: elapsed, sampledAt: now,
            isPlaying: !paused, shuffle: nil, repeatMode: nil, liked: nil,
            bundleID: browser.bundleID, note: browser.enableHint, site: site.displayName
        )
        return (snapshot, entry?.artwork)
    }

    private struct CatalogEntry {
        let artist: String
        let album: String
        let duration: TimeInterval
        let artwork: URL?
    }

    /// Finds the song in the iTunes Search API (no account or key needed). Only an exact
    /// title match counts (artist too, when the tab gives one): a guessed cover is worse
    /// than the placeholder. The local storefront goes first, then the US one.
    private func lookUp(song: String, artist: String, key: String) {
        lookupPending = true
        guard !lookupsInFlight.contains(key) else { return }
        lookupsInFlight.insert(key)
        let region = Locale.current.region?.identifier.lowercased() ?? "us"
        let storefronts = region == "us" ? ["us"] : [region, "us"]
        search(song: song, artist: artist, storefronts: storefronts[...]) { [weak self] entry in
            guard let self else { return }
            self.queue.async {
                self.catalog[key] = .some(entry)
                self.lookupsInFlight.remove(key)
                DispatchQueue.main.async { self.refresh() }
            }
        }
    }

    private func search(song: String, artist: String, storefronts: ArraySlice<String>,
                        completion: @escaping (CatalogEntry?) -> Void) {
        guard let country = storefronts.first else { return completion(nil) }
        var url = URLComponents(string: "https://itunes.apple.com/search")!
        url.queryItems = [
            .init(name: "term", value: artist.isEmpty ? song : "\(song) \(artist)"),
            .init(name: "entity", value: "song"),
            .init(name: "country", value: country),
            .init(name: "limit", value: "15"),
        ]
        URLSession.shared.dataTask(with: url.url!) { [weak self] data, _, _ in
            let results = data
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["results"] as? [[String: Any]] ?? []
            let wantedTitle = Self.normalized(song), wantedArtist = Self.normalized(artist)
            let match = results.first { r in
                Self.normalized(r["trackName"] as? String ?? "") == wantedTitle
                    && (wantedArtist.isEmpty || Self.normalized(r["artistName"] as? String ?? "").contains(wantedArtist)
                        || wantedArtist.contains(Self.normalized(r["artistName"] as? String ?? "")))
            }
            guard let match else {
                self?.search(song: song, artist: artist, storefronts: storefronts.dropFirst(), completion: completion)
                return
            }
            completion(CatalogEntry(
                artist: match["artistName"] as? String ?? "",
                album: match["collectionName"] as? String ?? "",
                duration: (match["trackTimeMillis"] as? Double ?? 0) / 1000,
                artwork: (match["artworkUrl100"] as? String).flatMap {
                    URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
                }
            ))
        }.resume()
    }

    /// Lowercased, without "(feat. …)"/"[Remix]" style suffixes and extra spaces.
    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// True while a YouTube Music tab is open (playing or not), so songs can be started in it.
    var followsYouTubeMusic: Bool { musicTab != nil }

    /// True when the tab lets us run JavaScript (needed to list playlists).
    var hasPageAccess: Bool { (musicTab ?? activeTab)?.pageAccess == true }

    /// Starts a song and/or playlist inside YouTube Music the way its own links do,
    /// without reloading the page. A reload would stop the music and make Safari ask
    /// "Leave this page?", which nobody can answer on the lock screen.
    func playInYouTubeMusic(videoID: String?, playlistID: String?) {
        guard let tab = musicTab else { return }
        var url = URLComponents(string: "https://music.youtube.com/watch")!
        url.queryItems = [videoID.map { .init(name: "v", value: $0) }, playlistID.map { .init(name: "list", value: $0) }].compactMap { $0 }
        // Without page access all that's left is pointing the tab somewhere new.
        guard tab.pageAccess else { return navigate(to: url.url!) }
        let fields = [videoID.map { "videoId:'\($0)'" }, playlistID.map { "playlistId:'\($0)'" }].compactMap { $0 }
            .joined(separator: ",")
        let js = """
        (function(){
          var app = document.querySelector('ytmusic-app');
          if (!app) return '';
          app.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true,
            detail: { endpoint: { watchEndpoint: { \(fields) } } } }));
          return 'ok';
        })()
        """
        guard browser == .chrome else { return run(js, in: tab) }
        // If Chrome won't let the page's own code run, loading the song's page still plays it.
        evaluate(inPage(js), in: tab) { [weak self] result in
            result == "ok" ? self?.refresh() : self?.navigate(to: url.url!)
        }
    }

    private static let youTubePlaylistsJS = """
    (function(){
      var out = [];
      document.querySelectorAll('ytmusic-guide-entry-renderer').forEach(function(e){
        var d = e.data; if (!d) return;
        var b = ((d.navigationEndpoint || {}).browseEndpoint || {}).browseId || '';
        if (b.indexOf('VL') !== 0) return;
        var text = function(f){ return f && f.runs ? f.runs.map(function(r){ return r.text }).join('') : '' };
        out.push({ id: b.slice(2), t: text(d.formattedTitle), s: text(d.formattedSubtitle) });
      });
      return JSON.stringify(out);
    })()
    """

    private static let spotifyPlaylistsJS = """
    (function(){
      var out = [], seen = {};
      document.querySelectorAll('a[href*="/playlist/"]').forEach(function(a){
        var m = a.getAttribute('href').match(/playlist\\/([A-Za-z0-9]+)/); if (!m || seen[m[1]]) return;
        var row = a.closest('[role="row"], li') || a;
        var title = (a.getAttribute('aria-label') || a.textContent || '').trim();
        if (!title) return;
        seen[m[1]] = 1;
        var img = row.querySelector('img');
        out.push({ id: m[1], t: title, s: '', img: img ? img.src : '' });
      });
      return JSON.stringify(out.slice(0, 40));
    })()
    """

    /// Reads the playlists listed in the followed tab's sidebar. Chrome may keep the
    /// sidebar's data out of reach; then the library page is read instead.
    func fetchPlaylists(completion: @escaping ([Playlist]) -> Void) {
        guard let tab = musicTab ?? activeTab, tab.pageAccess else { return completion([]) }
        let site = tab.site
        let js = site == .youtubeMusic ? inPage(Self.youTubePlaylistsJS) : Self.spotifyPlaylistsJS
        evaluate(js, in: tab) { [weak self] text in
            let lists = Self.playlists(from: text, site: site)
            guard let self, lists.isEmpty, site == .youtubeMusic, self.browser == .chrome,
                  Date().timeIntervalSince(self.libraryReadAt) > 60 else { return completion(lists) }
            self.libraryReadAt = Date()
            let start = Self.embeddedDataJS(path: "/library/playlists", attribute: "data-brimtune-lists", visit: Self.playlistVisitJS)
            self.evaluate(start, in: tab) { _ in
                self.collect("data-brimtune-lists", in: tab, attempts: 25) { completion(Self.playlists(from: $0, site: site)) }
            }
        }
    }

    /// The last time the library page was read for playlists (Chrome only); it's a big page.
    private var libraryReadAt = Date.distantPast

    private static func playlists(from json: String, site: Site) -> [Playlist] {
        let raw = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]) ?? []
        return raw.compactMap { r -> Playlist? in
            guard let id = r["id"] as? String, let title = r["t"] as? String, !title.isEmpty else { return nil }
            let img = (r["img"] as? String).flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
            return Playlist(id: id, title: title, subtitle: r["s"] as? String ?? "", artwork: img, site: site.displayName)
        }
    }

    private static func songs(from json: String) -> [PlaylistSong] {
        let raw = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]) ?? []
        return raw.compactMap { r -> PlaylistSong? in
            guard let id = r["v"] as? String, let title = r["t"] as? String else { return nil }
            return PlaylistSong(id: id, title: title, artist: r["a"] as? String ?? "", duration: r["d"] as? String ?? "",
                                artwork: (r["img"] as? String).flatMap(URL.init(string:)))
        }
    }

    /// Fetches a YouTube Music page as the tab does (signed in), digs out the data the page
    /// embeds in its HTML, and parks what `visit` collects as JSON in an attribute on <html>.
    /// Plain DOM and network calls only, so it works where the page's own objects can't be
    /// reached. `visit(o, out)` sees every object and returns true to skip its children.
    private static func embeddedDataJS(path: String, attribute: String, visit: String) -> String {
        #"""
        (function(){
          var root = document.documentElement;
          root.removeAttribute('\#(attribute)');
          fetch('\#(path)', { credentials: 'include' }).then(function(r){ return r.text() }).then(function(html){
            var out = [], re = /data:\s*'((?:[^'\\]|\\.)*)'/g, m, visit = \#(visit);
            var walk = function(o){ if (!o || typeof o !== 'object' || visit(o, out)) return; for (var k in o) walk(o[k]) };
            while ((m = re.exec(html))) {
              try { walk(JSON.parse(JSON.parse('"' + m[1].replace(/\\x([0-9a-fA-F]{2})/g, '\\u00$1').replace(/\\'/g, "'") + '"'))) } catch (e) {}
            }
            root.setAttribute('\#(attribute)', JSON.stringify(out));
          }).catch(function(){ root.setAttribute('\#(attribute)', '[]') });
          return 'started';
        })()
        """#
    }

    /// Playlists shown as cards (grid) or rows (list) on the library page.
    private static let playlistVisitJS = """
    function(o, out){
      var runs = function(t){ return t && t.runs ? t.runs.map(function(r){ return r.text }).join('') : '' };
      var add = function(b, t, sub){ if (b.indexOf('VL') === 0 && t && !out.some(function(p){ return p.id === b.slice(2) })) out.push({ id: b.slice(2), t: t, s: sub }) };
      var card = o.musicTwoRowItemRenderer;
      if (card) { add(((card.navigationEndpoint || {}).browseEndpoint || {}).browseId || '', runs(card.title), runs(card.subtitle)); return true }
      var row = o.musicResponsiveListItemRenderer;
      if (row) {
        var col = function(i){ var c = row.flexColumns && row.flexColumns[i]; return c ? runs(c.musicResponsiveListItemFlexColumnRenderer.text) : '' };
        add(((row.navigationEndpoint || {}).browseEndpoint || {}).browseId || '', col(0), col(1));
        return true;
      }
      return false;
    }
    """

    /// The songs on a playlist page.
    private static let songVisitJS = """
    function(o, out){
      var m = o.musicResponsiveListItemRenderer;
      if (!m) return false;
      var col = function(i){ var c = m.flexColumns && m.flexColumns[i]; var rr = c && c.musicResponsiveListItemFlexColumnRenderer.text.runs; return rr ? rr.map(function(x){ return x.text }).join('') : '' };
      var fc = m.fixedColumns && m.fixedColumns[0];
      var th = m.thumbnail && m.thumbnail.musicThumbnailRenderer && m.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails;
      var v = (m.playlistItemData || {}).videoId;
      if (v) out.push({ v: v, t: col(0), a: col(1), d: fc ? ((fc.musicResponsiveListItemFixedColumnRenderer.text.runs || [{}])[0].text || '') : '', img: th ? th[th.length - 1].url : '' });
      return true;
    }
    """

    /// Runs `js` in `tab` on the script queue and hands back what it returned ("" on failure).
    private func evaluate(_ js: String, in tab: Tab, after delay: TimeInterval = 0, completion: @escaping (String) -> Void) {
        let source = """
        set js to "\(Self.appleScriptString(js))"
        tell application id "\(browser.bundleID)"
            set t to tab \(tab.index) of window id \(tab.window)
            return \(browser.runJS)
        end tell
        """
        queue.asyncAfter(deadline: .now() + delay) {
            var error: NSDictionary?
            let text = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue ?? ""
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// Collects (and clears) a result a page script parks in an attribute on <html>,
    /// looking every 0.4 s while it isn't there yet.
    private func collect(_ attribute: String, in tab: Tab, attempts: Int, completion: @escaping (String) -> Void) {
        guard attempts > 0 else { return completion("") }
        let js = "(function(){ var r = document.documentElement, v = r.getAttribute('\(attribute)'); if (v !== null) r.removeAttribute('\(attribute)'); return v || '' })()"
        evaluate(js, in: tab, after: 0.4) { [weak self] text in
            guard text.isEmpty else { return completion(text) }
            self?.collect(attribute, in: tab, attempts: attempts - 1, completion: completion)
        }
    }

    /// Asks YouTube Music's own client (already signed in) for a playlist's songs.
    /// The request is asynchronous in the page, so the result is parked on `window`
    /// and collected with a few short polls.
    func fetchSongs(of playlist: Playlist, completion: @escaping ([PlaylistSong]) -> Void) {
        guard let tab = musicTab, tab.pageAccess else { return completion([]) }
        let key = playlist.id.replacingOccurrences(of: "'", with: "")
        // Chrome: the playlist's own page, which needs nothing from the page's objects.
        if browser == .chrome {
            let attribute = "data-brimtune-songs-\(key)"
            let start = Self.embeddedDataJS(path: "/playlist?list=\(key)", attribute: attribute, visit: Self.songVisitJS)
            return evaluate(start, in: tab) { [weak self] _ in
                self?.collect(attribute, in: tab, attempts: 25) { completion(Self.songs(from: $0)) }
            }
        }
        let start = """
        (function(){
          var a = document.querySelector('ytmusic-app'), nm = a && (a.networkManager || a.networkManager_);
          window.__brimtuneSongs = window.__brimtuneSongs || {};
          if (!nm || !nm.fetch) { window.__brimtuneSongs['\(key)'] = '[]'; return 'none' }
          nm.fetch('/browse', { browseId: 'VL\(key)' }).then(function(r){
            var out = [];
            (function walk(o){
              if (!o || typeof o !== 'object') return;
              var m = o.musicResponsiveListItemRenderer;
              if (m) {
                var col = function(i){ var c = m.flexColumns && m.flexColumns[i]; var rr = c && c.musicResponsiveListItemFlexColumnRenderer.text.runs; return rr ? rr.map(function(x){ return x.text }).join('') : '' };
                var fc = m.fixedColumns && m.fixedColumns[0];
                var th = m.thumbnail && m.thumbnail.musicThumbnailRenderer && m.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails;
                var v = (m.playlistItemData || {}).videoId;
                if (v) out.push({ v: v, t: col(0), a: col(1), d: fc ? ((fc.musicResponsiveListItemFixedColumnRenderer.text.runs || [{}])[0].text || '') : '', img: th ? th[th.length - 1].url : '' });
                return;
              }
              for (var k in o) walk(o[k]);
            })(r);
            window.__brimtuneSongs['\(key)'] = JSON.stringify(out);
          }).catch(function(){ window.__brimtuneSongs['\(key)'] = '[]' });
          return 'started';
        })()
        """
        run(inPage(start), in: tab)
        poll(key: key, tab: tab, attempts: 20, completion: completion)
    }

    private func poll(key: String, tab: Tab, attempts: Int, completion: @escaping ([PlaylistSong]) -> Void) {
        guard attempts > 0 else { return completion([]) }
        let source = """
        set js to "\(Self.appleScriptString(inPage("(window.__brimtuneSongs && window.__brimtuneSongs['\(key)']) || ''")))"
        tell application id "\(browser.bundleID)"
            set t to tab \(tab.index) of window id \(tab.window)
            return \(browser.runJS)
        end tell
        """
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            var error: NSDictionary?
            let text = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue ?? ""
            guard !text.isEmpty else {
                DispatchQueue.main.async { self?.poll(key: key, tab: tab, attempts: attempts - 1, completion: completion) }
                return
            }
            let songs = Self.songs(from: text)
            DispatchQueue.main.async { completion(songs) }
        }
    }

    /// Plays one song with the rest of its playlist queued after it.
    func play(_ song: PlaylistSong, in playlist: Playlist) {
        playInYouTubeMusic(videoID: song.id, playlistID: playlist.id)
    }

    /// Starts a playlist from the top in the followed tab.
    func play(_ playlist: Playlist) {
        if playlist.site == "YouTube Music" {
            return playInYouTubeMusic(videoID: nil, playlistID: playlist.id)
        }
        switch activeTab?.site {
        case .youtubeMusic:
            playInYouTubeMusic(videoID: nil, playlistID: playlist.id)
        case .spotify:
            navigate(to: URL(string: "https://open.spotify.com/playlist/\(playlist.id)")!)
            // The page needs a moment to load before its big play button exists.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let tab = self.activeTab else { return }
                self.run("var b=document.querySelector('[data-testid=\"action-bar-row\"] [data-testid=\"play-button\"]'); if(b) b.click()", in: tab)
            }
        case nil:
            break
        }
    }

    /// Points the followed tab at `url` (no page access needed).
    func navigate(to url: URL) {
        guard let tab = activeTab ?? musicTab else { return }
        let source = """
        tell application id "\(browser.bundleID)"
            set URL of tab \(tab.index) of window id \(tab.window) to "\(url.absoluteString)"
        end tell
        """
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.refresh() }
        }
    }

    // MARK: Commands

    func perform(_ command: PlayerCommand) {
        guard let tab = activeTab else { return }
        if !tab.pageAccess {
            // No page access: fall back to the system media commands, which go to the playing tab.
            if command == .togglePlayPause, let id = lastTitleOnlyID {
                if assumedPaused.remove(id) == nil { assumedPaused.insert(id) }
            }
            MediaRemoteSource.sendSystem(command)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
            return
        }
        let js: String
        switch (tab.site, command) {
        case (.youtubeMusic, .togglePlayPause):
            js = "var b=document.querySelector('ytmusic-player-bar #play-pause-button'); if(b){b.click()}else{var v=document.querySelector('video'); v.paused?v.play():v.pause()}"
        case (.youtubeMusic, .next): js = "document.querySelector('ytmusic-player-bar .next-button').click()"
        case (.youtubeMusic, .previous): js = "document.querySelector('ytmusic-player-bar .previous-button').click()"
        case (.youtubeMusic, .toggleShuffle): js = "document.querySelector('ytmusic-player-bar .shuffle').click()"
        case (.youtubeMusic, .cycleRepeat): js = "document.querySelector('ytmusic-player-bar .repeat').click()"
        case (.spotify, .togglePlayPause): js = Self.clickTestID("control-button-playpause")
        case (.spotify, .next): js = Self.clickTestID("control-button-skip-forward")
        case (.spotify, .previous): js = Self.clickTestID("control-button-skip-back")
        case (.spotify, .toggleShuffle): js = Self.clickTestID("control-button-shuffle")
        case (.spotify, .cycleRepeat): js = Self.clickTestID("control-button-repeat")
        case (.youtubeMusic, .playQueueItem(let index)):
            js = "var e=document.querySelectorAll('ytmusic-player-queue-item')[\(index)]; if(e){var b=e.querySelector('ytmusic-play-button-renderer'); (b||e).click()}"
        case (.spotify, .playQueueItem), (_, .like): return
        }
        run(js, in: tab)
    }

    func seek(to seconds: TimeInterval) {
        guard let tab = activeTab else { return }
        guard tab.pageAccess else {
            // Re-anchor our clock too, so tapping a lyric line also fixes the karaoke timing.
            queue.async { [weak self] in
                guard let self, let clock = self.clock else { return }
                self.clock = (clock.key, Date().addingTimeInterval(-seconds), clock.frozen == nil ? nil : seconds)
            }
            return MediaRemoteSource.setSystemElapsed(seconds)
        }
        let s = String(format: "%.2f", seconds)
        switch tab.site {
        case .youtubeMusic:
            run("document.querySelector('video').currentTime=\(s)", in: tab)
        case .spotify:
            // Spotify's progress bar is a range input driven by React; set it the way React notices.
            run("""
            var i=document.querySelector('[data-testid="playback-progressbar"] input[type=range]');
            if(i){var set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
            set.call(i,Math.round(\(s)*1000));i.dispatchEvent(new Event('input',{bubbles:true}));i.dispatchEvent(new Event('change',{bubbles:true}));}
            """, in: tab)
        }
    }

    private static func clickTestID(_ id: String) -> String {
        "document.querySelector('[data-testid=\"\(id)\"]').click()"
    }

    /// Chrome runs AppleScript's JavaScript in an isolated world: it sees the page's DOM but
    /// not its own objects, such as YouTube Music's app data and network client. Code that
    /// needs them is slipped into the page as a script tag carrying the page's nonce, and
    /// hands its result back through an attribute on <html>. Safari already runs in the page.
    private func inPage(_ js: String) -> String {
        js.inPage(for: browser)
    }

    /// `js` as the body of an AppleScript string literal, on one line.
    private static func appleScriptString(_ js: String) -> String {
        js.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func run(_ js: String, in tab: Tab) {
        let source = """
        set js to "\(Self.appleScriptString(js))"
        tell application id "\(browser.bundleID)"
            set t to tab \(tab.index) of window id \(tab.window)
            \(browser.runJS)
        end tell
        """
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refresh() }
        }
    }

    private func compile(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        if let error { NSLog("Brimtune: browser script failed to compile: %@", error) }
        return error == nil ? script : nil
    }
}

private extension String {
    /// This expression, evaluated in the page's own JavaScript world (see `BrowserSource.inPage`).
    func inPage(for browser: BrowserSource.Browser) -> String {
        guard browser == .chrome else { return self }
        let body = "document.documentElement.setAttribute('data-brimtune-out', String((function(){ try { return \(self) } catch (e) { return '' } })()))"
        // A JSON string is a valid JavaScript string literal.
        let data = try! JSONSerialization.data(withJSONObject: [body])
        let literal = String(decoding: data, as: UTF8.self).dropFirst().dropLast()
        // YouTube Music only accepts script text that went through a Trusted Types policy.
        // No `//` comments inside: the script is sent to the browser as a single line.
        return """
        (function(){
          var root = document.documentElement, s = document.createElement('script'), n = document.querySelector('script[nonce]');
          if (n) s.nonce = n.nonce || n.getAttribute('nonce');
          var text = \(literal);
          if (window.trustedTypes && trustedTypes.createPolicy) {
            try {
              window.__brimtunePolicy = window.__brimtunePolicy
                || trustedTypes.createPolicy('brimtune-' + Math.random().toString(36).slice(2), { createScript: function(x){ return x } });
              text = window.__brimtunePolicy.createScript(text);
            } catch (e) {}
          }
          s.textContent = text;
          root.appendChild(s); s.remove();
          var out = root.getAttribute('data-brimtune-out');
          root.removeAttribute('data-brimtune-out');
          return out || '';
        })()
        """
    }
}
