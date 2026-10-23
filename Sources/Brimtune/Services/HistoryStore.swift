import AppKit
import Combine

/// The last songs played, with small cover thumbnails, kept on disk.
@MainActor
final class HistoryStore: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let title: String
        let artist: String
        let album: String
        let source: String
        let playedAt: Date
        var thumbnail: String?
    }

    @Published private(set) var entries: [Entry] = []
    private let limit = 100
    private var cancellables: Set<AnyCancellable> = []

    private lazy var folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brimtune/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private var indexURL: URL { folder.appendingPathComponent("history.json") }

    init(center: NowPlayingCenter) {
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
        center.trackChanged
            .sink { [weak self] track in self?.record(track) }
            .store(in: &cancellables)
        center.$artwork
            .compactMap { $0 }
            .sink { [weak self, weak center] image in
                guard let track = center?.track else { return }
                self?.attach(image, to: track)
            }
            .store(in: &cancellables)
    }

    private let thumbnails = NSCache<NSString, NSImage>()

    /// Views ask for thumbnails on every redraw, so keep them out of the disk path.
    func thumbnail(for entry: Entry) -> NSImage? {
        guard let name = entry.thumbnail else { return nil }
        if let cached = thumbnails.object(forKey: name as NSString) { return cached }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        thumbnails.setObject(image, forKey: name as NSString)
        return image
    }

    /// Opens the song again where it was played: a search in the same service.
    func open(_ entry: Entry) {
        let query = "\(entry.title) \(entry.artist)".trimmingCharacters(in: .whitespaces)
        var components: URLComponents
        switch entry.source {
        case "Spotify":
            components = URLComponents(string: "https://open.spotify.com/search/")!
            components.path += query
        case "Music":
            components = URLComponents(string: "music://music.apple.com/search")!
            components.queryItems = [.init(name: "term", value: query)]
        default:
            components = URLComponents(string: "https://music.youtube.com/search")!
            components.queryItems = [.init(name: "q", value: query)]
        }
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: folder)
        save()
    }

    // MARK: Private

    private func record(_ track: TrackSnapshot) {
        if let last = entries.first, last.title == track.title, last.artist == track.artist { return }
        let source = track.site ?? (track.bundleID == "com.spotify.client" ? "Spotify" : "Music")
        entries.insert(Entry(id: UUID(), title: track.title, artist: track.artist, album: track.album,
                             source: source, playedAt: Date(), thumbnail: nil), at: 0)
        for dropped in entries.dropFirst(limit) {
            if let file = dropped.thumbnail { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) }
        }
        entries = Array(entries.prefix(limit))
        save()
    }

    private func attach(_ image: NSImage, to track: TrackSnapshot) {
        guard let index = entries.firstIndex(where: { $0.title == track.title && $0.artist == track.artist }),
              index < 3, entries[index].thumbnail == nil else { return }
        let side = 120
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let name = entries[index].id.uuidString + ".jpg"
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]),
              (try? data.write(to: folder.appendingPathComponent(name))) != nil else { return }
        entries[index].thumbnail = name
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: indexURL) }
    }
}
