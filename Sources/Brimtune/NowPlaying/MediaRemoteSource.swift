import AppKit

/// System-wide now playing via the private MediaRemote framework. It covers every
/// app (browsers, Podcasts, TV…), but macOS 15.4 and later only answer Apple-signed
/// processes, so there this source simply stays silent and the scripting sources
/// take over.
final class MediaRemoteSource: NowPlayingSource {
    let priority = 2
    var onChange: ((TrackSnapshot?) -> Void)?
    var onArtwork: ((String, NSImage) -> Void)?

    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private var getInfo: GetInfoFn?
    private var getPlaying: GetPlayingFn?
    private var sendCommand: SendCommandFn?
    private var setElapsed: SetElapsedFn?
    private var artworkTrackID: String?

    func start() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else { return }
        func load<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        getInfo = load("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getPlaying = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetPlayingFn.self)
        sendCommand = load("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        setElapsed = load("MRMediaRemoteSetElapsedTime", as: SetElapsedFn.self)
        guard let register = load("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self),
              getInfo != nil, getPlaying != nil else { return }

        register(.main)
        for name in [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ] {
            NotificationCenter.default.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    private func refresh() {
        guard let getInfo, let getPlaying else { return }
        getInfo(.main) { [weak self] cfInfo in
            getPlaying(.main) { playing in
                guard let self else { return }
                let info = (cfInfo as? [String: Any]) ?? [:]
                guard let snapshot = Self.snapshot(from: info, playing: playing) else {
                    self.onChange?(nil)
                    return
                }
                self.onChange?(snapshot)
                if snapshot.id != self.artworkTrackID,
                   let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
                   let image = NSImage(data: data) {
                    self.artworkTrackID = snapshot.id
                    self.onArtwork?(snapshot.id, image)
                }
            }
        }
    }

    static func snapshot(from info: [String: Any], playing: Bool) -> TrackSnapshot? {
        func value<T>(_ key: String) -> T? { info["kMRMediaRemoteNowPlayingInfo" + key] as? T }
        guard let title: String = value("Title"), !title.isEmpty else { return nil }
        let rate: Double = value("PlaybackRate") ?? (playing ? 1 : 0)
        let repeatMode: RepeatMode? = (value("RepeatMode") as Int?).map { $0 == 2 ? .one : $0 == 3 ? .all : .off }
        return TrackSnapshot(
            title: title,
            artist: value("Artist") ?? "",
            album: value("Album") ?? "",
            duration: value("Duration") ?? 0,
            elapsed: value("ElapsedTime") ?? 0,
            sampledAt: value("Timestamp") ?? Date(),
            isPlaying: playing && rate > 0,
            shuffle: (value("ShuffleMode") as Int?).map { $0 != 1 },
            repeatMode: repeatMode,
            liked: nil,
            bundleID: nil
        )
    }

    private static func code(for command: PlayerCommand) -> Int32? {
        switch command {
        case .togglePlayPause: 2
        case .next: 4
        case .previous: 5
        case .toggleShuffle: 6
        case .cycleRepeat: 7
        case .like: 106
        case .playQueueItem: nil
        }
    }

    private static let system: (send: SendCommandFn?, seek: SetElapsedFn?) = {
        guard let mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else { return (nil, nil) }
        return (dlsym(mr, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: SendCommandFn.self) },
                dlsym(mr, "MRMediaRemoteSetElapsedTime").map { unsafeBitCast($0, to: SetElapsedFn.self) })
    }()

    /// Sends a command to whatever the system considers the now-playing app. Unlike
    /// reading, sending still works for ordinary apps.
    static func sendSystem(_ command: PlayerCommand) {
        guard let code = code(for: command) else { return }
        _ = system.send?(code, nil)
    }

    static func setSystemElapsed(_ seconds: TimeInterval) {
        system.seek?(seconds)
    }

    func perform(_ command: PlayerCommand) {
        guard let code = Self.code(for: command) else { return }
        _ = sendCommand?(code, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
    }

    func seek(to seconds: TimeInterval) {
        setElapsed?(seconds)
    }
}
