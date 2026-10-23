import AppKit

enum PlayerCommand: Equatable {
    case togglePlayPause
    case next
    case previous
    case toggleShuffle
    case cycleRepeat
    case like(Bool)
    /// Jump to an entry of the player's queue (`QueueItem.id`).
    case playQueueItem(Int)
}

/// One of the next few songs in the player's queue.
struct QueueItem: Equatable, Identifiable {
    let id: Int
    let title: String
    let artist: String
    let artwork: URL?
}

/// One of the user's playlists in the web player.
struct Playlist: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    var artwork: URL?
    /// "YouTube Music" or "Spotify".
    let site: String

    /// YouTube Music's automatic "Liked music" list.
    var isLiked: Bool { id == "LM" }
}

/// A song inside one of the user's playlists.
struct PlaylistSong: Identifiable, Equatable {
    /// YouTube video id.
    let id: String
    let title: String
    let artist: String
    let duration: String
    let artwork: URL?
}

enum RepeatMode: Equatable {
    case off, all, one
}

/// A point-in-time reading of a player. Position advances on its own while playing,
/// so views derive the live position with `position(at:)` instead of polling.
struct TrackSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var sampledAt: Date
    var isPlaying: Bool
    var shuffle: Bool?
    var repeatMode: RepeatMode?
    var liked: Bool?
    var bundleID: String?
    var supportsLike = false
    /// Shown under the artist when something limits control, e.g. a browser setting to enable.
    var note: String?
    /// Up next, when the player exposes it.
    var queue: [QueueItem] = []
    /// The web service playing in a browser ("YouTube Music", "Spotify"); nil for apps.
    var site: String?

    var id: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }

    /// The next distinct songs: no repeats of the current one or of each other.
    var upNext: [QueueItem] {
        var seen: Set<String> = ["\(title)|\(artist)"]
        return Array(queue.filter { seen.insert("\($0.title)|\($0.artist)").inserted }.prefix(3))
    }

    func position(at date: Date) -> TimeInterval {
        var p = elapsed
        if isPlaying { p += date.timeIntervalSince(sampledAt) }
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }

    /// Same track and state, ignoring clock drift between two readings.
    func isEquivalent(to other: TrackSnapshot) -> Bool {
        id == other.id && isPlaying == other.isPlaying && shuffle == other.shuffle
            && repeatMode == other.repeatMode && liked == other.liked && note == other.note && queue == other.queue
            && abs(position(at: Date()) - other.position(at: Date())) < 1.5
    }
}

/// The one queue every AppleScript in Brimtune runs on. NSAppleScript can't run two
/// scripts at once: with Safari and Chrome read in parallel, one browser's answers
/// landed in the other's reading and scripts failed (-1751), so tracks lagged or vanished.
enum AppleScriptQueue {
    static let shared = DispatchQueue(label: "brimtune.applescript", qos: .userInitiated)
}

protocol NowPlayingSource: AnyObject {
    /// Higher wins when two sources report the same thing.
    var priority: Int { get }
    var onChange: ((TrackSnapshot?) -> Void)? { get set }
    var onArtwork: ((String, NSImage) -> Void)? { get set }
    func start()
    func perform(_ command: PlayerCommand)
    func seek(to seconds: TimeInterval)
}

enum TimeFormat {
    static func clock(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
