import Foundation

struct SearchResult: Identifiable, Equatable {
    /// YouTube video id; YouTube Music plays the same ids.
    let id: String
    let title: String
    let artist: String
    let duration: String?
    let thumbnail: URL?

    var youTubeMusicURL: URL { URL(string: "https://music.youtube.com/watch?v=\(id)")! }
}

/// Song search for the island. Reads YouTube's public results page (no account or
/// API key): the query goes to YouTube, nothing else does.
enum MusicSearch {
    static func search(_ query: String) async -> [SearchResult] {
        var url = URLComponents(string: "https://www.youtube.com/results")!
        // sp=EgIQAQ== limits results to videos (no channels or playlists).
        url.queryItems = [.init(name: "search_query", value: query), .init(name: "sp", value: "EgIQAQ==")]
        var request = URLRequest(url: url.url!, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        // Skips the cookie-consent interstitial some regions get.
        request.setValue("CONSENT=YES+1", forHTTPHeaderField: "Cookie")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "var ytInitialData = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8))
        else { return [] }

        var renderers: [[String: Any]] = []
        collect(json, into: &renderers)
        return renderers.prefix(5).compactMap(result)
    }

    private static func collect(_ node: Any, into out: inout [[String: Any]]) {
        if let dict = node as? [String: Any] {
            if let video = dict["videoRenderer"] as? [String: Any] { out.append(video) }
            for value in dict.values { collect(value, into: &out) }
        } else if let list = node as? [Any] {
            for value in list { collect(value, into: &out) }
        }
    }

    private static func result(from video: [String: Any]) -> SearchResult? {
        func runs(_ key: String) -> String? {
            ((video[key] as? [String: Any])?["runs"] as? [[String: Any]])?.first?["text"] as? String
        }
        guard let id = video["videoId"] as? String, let title = runs("title") else { return nil }
        let thumbs = (video["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        return SearchResult(
            id: id,
            title: title,
            artist: runs("ownerText") ?? "",
            duration: (video["lengthText"] as? [String: Any])?["simpleText"] as? String,
            thumbnail: (thumbs?.last?["url"] as? String).flatMap(URL.init(string:))
        )
    }
}
