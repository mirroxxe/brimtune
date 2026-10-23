import Foundation

struct Lyrics: Equatable {
    struct Word: Equatable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    struct Line: Equatable, Identifiable {
        let id: Int
        let time: TimeInterval
        let text: String
        /// Per-word timing: from enhanced LRC when the source has it, otherwise
        /// spread across the line at a natural singing pace.
        var words: [Word] = []
    }

    let lines: [Line]
    let isSynced: Bool

    /// Index of the line being sung at `position`, with a small lead so the
    /// highlight lands as the line starts rather than just after.
    func index(at position: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        let t = position + 0.1
        return lines.lastIndex { $0.time <= t }
    }
}

/// Fetches lyrics from LRCLIB (lrclib.net), a free open lyrics database.
actor LyricsService {
    private var cache: [String: Lyrics?] = [:]

    func lyrics(title: String, artist: String, album: String, duration: TimeInterval) async -> Lyrics? {
        let key = "\(title)|\(artist)"
        if let cached = cache[key] { return cached }

        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: album),
        ]
        if duration > 0 { exact.queryItems?.append(.init(name: "duration", value: String(Int(duration.rounded())))) }

        var result: Lyrics?
        if let record = await fetch(exact.url!) as [String: Any]? {
            result = Self.parse(record)
        }
        if result == nil {
            var search = URLComponents(string: "https://lrclib.net/api/search")!
            search.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
            if let records = await fetch(search.url!) as [[String: Any]]? {
                // With only a title to go on, the song length is what tells same-named songs apart.
                let fitting = duration > 0
                    ? records.filter { abs(($0["duration"] as? Double ?? 0) - duration) < 4 }
                    : records
                result = fitting.lazy.compactMap(Self.parse).first { $0.isSynced } ?? fitting.lazy.compactMap(Self.parse).first
            }
        }
        if cache.count > 40 { cache.removeAll() }
        cache[key] = result
        return result
    }

    private func fetch<T>(_ url: URL) async -> T? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Brimtune/1.0 (macOS now playing)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? T
    }

    private static func parse(_ record: [String: Any]) -> Lyrics? {
        if record["instrumental"] as? Bool == true { return nil }
        if let synced = record["syncedLyrics"] as? String, let lyrics = parseLRC(synced) { return lyrics }
        guard let plain = record["plainLyrics"] as? String, !plain.isEmpty else { return nil }
        let lines = plain.components(separatedBy: .newlines).enumerated().map { Lyrics.Line(id: $0.offset, time: 0, text: $0.element, words: []) }
        return Lyrics(lines: lines, isSynced: false)
    }

    private static func parseLRC(_ text: String) -> Lyrics? {
        let stamp = #/\[(\d+):(\d+(?:\.\d+)?)\]/#
        let wordStamp = #/<(\d+):(\d+(?:\.\d+)?)>/#
        func seconds(_ m: Substring, _ s: Substring) -> TimeInterval { (Double(m) ?? 0) * 60 + (Double(s) ?? 0) }

        // (line start, plain text, word starts from enhanced "<mm:ss.xx>" tags)
        var timed: [(TimeInterval, String, [(TimeInterval, String)])] = []
        for raw in text.components(separatedBy: .newlines) {
            let stamps = raw.matches(of: stamp)
            guard let last = stamps.last else { continue }
            let body = raw[last.range.upperBound...]
            var tagged: [(TimeInterval, String)] = []
            let tags = body.matches(of: wordStamp)
            for (i, tag) in tags.enumerated() {
                let end = i + 1 < tags.count ? tags[i + 1].range.lowerBound : body.endIndex
                let word = body[tag.range.upperBound..<end].trimmingCharacters(in: .whitespaces)
                if !word.isEmpty { tagged.append((seconds(tag.output.1, tag.output.2), word)) }
            }
            let plain = body.replacing(wordStamp, with: "")
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            for m in stamps {
                timed.append((seconds(m.output.1, m.output.2), plain, tagged))
            }
        }
        guard !timed.isEmpty else { return nil }
        timed.sort { $0.0 < $1.0 }

        let lines = timed.enumerated().map { i, entry -> Lyrics.Line in
            let (start, text, tagged) = entry
            let next = i + 1 < timed.count ? timed[i + 1].0 : start + 6
            let words: [Lyrics.Word]
            if !tagged.isEmpty {
                words = tagged.enumerated().map { k, w in
                    Lyrics.Word(text: w.1, start: w.0, end: k + 1 < tagged.count ? tagged[k + 1].0 : next)
                }
            } else {
                // No per-word timing: spread the words over the whole line, as singers do.
                // Only an unusually long gap (an instrumental break) gets capped, so the
                // last word doesn't crawl through it.
                let parts = text.split(separator: " ").map(String.init)
                let gap = next - start
                let natural = Double(parts.count) * 0.8 + 1.5
                let span = gap <= natural ? gap * 0.92 : Double(parts.count) * 0.6 + 1
                let total = Double(parts.reduce(0) { $0 + $1.count + 1 })
                var t = start
                words = parts.map { part in
                    let d = span * Double(part.count + 1) / max(total, 1)
                    defer { t += d }
                    return Lyrics.Word(text: part, start: t, end: t + d)
                }
            }
            return Lyrics.Line(id: i, time: start, text: text.isEmpty ? "♪" : text, words: text.isEmpty ? [] : words)
        }
        return Lyrics(lines: lines, isSynced: true)
    }
}
