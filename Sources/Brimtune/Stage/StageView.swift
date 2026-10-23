import AppKit
import SwiftUI

/// Shared by the full-screen player and the "Full stage" lock screen.
@MainActor
final class StagePresentation: ObservableObject {
    @Published var isVisible = false
    /// False while the window is hidden, so nothing inside keeps animating unseen.
    @Published var mounted = false
    private var unmountWork: DispatchWorkItem?

    func show() {
        unmountWork?.cancel()
        mounted = true
        // One runloop later, so the content exists before it animates in.
        DispatchQueue.main.async { self.isVisible = true }
    }

    func hide() {
        isVisible = false
        unmountWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isVisible else { return }
            self.mounted = false
        }
        unmountWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}

/// Renders its content only while the presentation is mounted.
struct MountGate<Content: View>: View {
    @ObservedObject var presentation: StagePresentation
    @ViewBuilder var content: () -> Content

    var body: some View {
        if presentation.mounted { content() } else { Color.clear }
    }
}

struct StageView: View {
    enum Context { case player, lockScreen }

    let context: Context
    @ObservedObject var center: NowPlayingCenter
    @ObservedObject var audio: AudioMonitor
    @ObservedObject var preferences: Preferences
    @ObservedObject var presentation: StagePresentation
    @ObservedObject var history: HistoryStore
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}
    var onHistory: () -> Void = {}

    /// What the column beside the cover shows.
    enum Panel { case lyrics, queue, playlists }

    @State private var showLyrics = true
    @State private var panel: Panel = .lyrics
    @State private var notice: String?
    @State private var openPlaylist: Playlist?
    @Namespace private var stageSpace

    private var lyricsAvailable: Bool { preferences.lyricsEnabled && center.lyrics != nil }

    /// Recently played, minus the song that's on now.
    private var recent: [HistoryStore.Entry] {
        Array(history.entries.filter { $0.title != center.track?.title || $0.artist != center.track?.artist }.prefix(6))
    }

    private var queueAvailable: Bool { !(center.track?.upNext.isEmpty ?? true) || !recent.isEmpty }

    private var availablePanels: [Panel] {
        [lyricsAvailable ? .lyrics : nil, queueAvailable ? .queue : nil, center.playlists.isEmpty ? nil : .playlists]
            .compactMap { $0 }
    }

    /// The column actually on screen: the chosen panel when it has content, else the first that does.
    private var shownPanel: Panel? {
        guard showLyrics, let first = availablePanels.first else { return nil }
        return availablePanels.contains(panel) ? panel : first
    }

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height, W = geo.size.width
            // Scale type to the screen, not to the lock-screen band the panel occupies.
            let k = max(0.6, min((context == .lockScreen ? H / 0.52 : H) / 1000, 1.4))
            let lyricsOn = shownPanel != nil

            ZStack(alignment: .topLeading) {
                // On the lock screen the real wallpaper and system clock stay visible behind us.
                if context == .player {
                    Backdrop(center: center, animate: presentation.isVisible)
                        .frame(width: W, height: H)
                }

                VStack(spacing: 0) {
                    if context == .player {
                        ClockHeader(scale: k)
                            .padding(.top, H * 0.06)
                    }
                    Spacer(minLength: 16)
                    if let track = center.track {
                        main(track: track, W: W, H: H, k: k, lyricsOn: lyricsOn)
                    } else {
                        Text("Nothing Playing")
                            .font(.system(size: 22 * k, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: context == .lockScreen ? 16 : H * 0.07)
                }
                .frame(width: W, height: H)
                .scaleEffect(presentation.isVisible ? 1 : 0.94)
                .blur(radius: presentation.isVisible ? 0 : 16)
                .opacity(presentation.isVisible ? 1 : 0)

                if context == .player {
                    Sidebar(context: context, lyricsOn: $showLyrics, hasLyrics: center.lyrics != nil,
                            onClose: onClose, onSettings: onSettings, onHistory: onHistory)
                        .padding(.leading, 28)
                        .padding(.top, 36)
                        .opacity(presentation.isVisible ? 1 : 0)
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.92), value: presentation.isVisible)
            .animation(.spring(response: 0.5, dampingFraction: 0.88), value: lyricsOn)
            .animation(.spring(response: 0.5, dampingFraction: 0.9), value: shownPanel)

        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func main(track: TrackSnapshot, W: CGFloat, H: CGFloat, k: CGFloat, lyricsOn: Bool) -> some View {
        let onLock = context == .lockScreen
        // The lock-screen panel is only the band between the system clock and the unlock prompt.
        let art = onLock
            ? (lyricsOn ? min(H * 0.48, W * 0.2) : min(H * 0.56, W * 0.26))
            : (lyricsOn ? min(H * 0.36, W * 0.27) : min(H * 0.42, W * 0.34))
        let cardWidth = max(min(art * 0.62, 330), 290)
        let gap = (onLock ? 16 : 24) * k
        if let shown = shownPanel {
            HStack(alignment: .center, spacing: W * 0.06) {
                VStack(spacing: gap) {
                    artwork(size: art)
                    PlayerCard(center: center, audio: audio, width: cardWidth, overDesktop: onLock)
                        .matchedGeometryEffect(id: "card", in: stageSpace)
                }
                VStack(alignment: .leading, spacing: 14 * k) {
                    if availablePanels.count > 1 {
                        PanelTabs(selection: shown, available: availablePanels, overDesktop: onLock) { choice in
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { panel = choice }
                        }
                    }
                    Group {
                        switch shown {
                        case .lyrics:
                            if let lyrics = center.lyrics {
                                LyricsView(lyrics: lyrics, track: track, fontSize: (onLock ? 26 : 30) * k, offset: center.lyricsOffset,
                                           onSeek: { center.syncLyrics(to: $0) }, onNudge: { center.nudgeLyrics(by: $0) })
                            }
                        case .queue:
                            QueuePanel(queue: track.upNext, recent: recent, history: history, scale: k,
                                       canOpen: !onLock) { center.perform(.playQueueItem($0)) }
                        case .playlists:
                            if let open = openPlaylist {
                                PlaylistSongList(center: center, playlist: open, scale: k * 1.15, back: {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { openPlaylist = nil }
                                })
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            } else {
                                PlaylistGrid(playlists: center.playlists, nowPlayingSite: track.site, scale: k,
                                             play: { center.play($0) },
                                             open: { list in withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { openPlaylist = list } })
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 12)))
                    .shadow(color: .black.opacity(onLock ? 0.45 : 0), radius: 10, y: 2)
                }
                .frame(width: W * (onLock ? 0.32 : 0.36), height: art + 160 * k)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        } else {
            VStack(spacing: gap) {
                artwork(size: art)
                PlayerCard(center: center, audio: audio, width: cardWidth, overDesktop: onLock)
                    .matchedGeometryEffect(id: "card", in: stageSpace)
            }
        }
    }

    private func artwork(size: CGFloat) -> some View {
        StageArtwork(center: center, size: size, onTap: toggleLyrics)
            .matchedGeometryEffect(id: "art", in: stageSpace)
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glass(cornerRadius: 16, overDesktop: true)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
    }

    /// Tapping the cover swaps between "cover + lyrics" and "just the cover".
    private func toggleLyrics() {
        guard !availablePanels.isEmpty else {
            // Nothing to bring back; say so instead of silently flipping hidden state.
            return flash("No lyrics or queue for this song")
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) { showLyrics.toggle() }
    }

    private func flash(_ text: String) {
        withAnimation(.smooth(duration: 0.25)) { notice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.smooth(duration: 0.3)) { if notice == text { notice = nil } }
        }
    }
}

// MARK: - Up Next & history

/// "Lyrics | Up Next" switch above the column.
private struct PanelTabs: View {
    let selection: StageView.Panel
    let available: [StageView.Panel]
    let overDesktop: Bool
    var select: (StageView.Panel) -> Void
    @Namespace private var tabs

    var body: some View {
        HStack(spacing: 2) {
            ForEach(available, id: \.self) { panel in
                switch panel {
                case .lyrics: tab("Lyrics", .lyrics)
                case .queue: tab("Up Next", .queue)
                case .playlists: tab("Playlists", .playlists)
                }
            }
        }
        .padding(3)
        .glass(cornerRadius: 18, overDesktop: overDesktop)
    }

    private func tab(_ title: String, _ panel: StageView.Panel) -> some View {
        Button { select(panel) } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(selection == panel ? 1 : 0.6))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background {
                    if selection == panel {
                        Capsule().fill(.white.opacity(0.18)).matchedGeometryEffect(id: "tab", in: tabs)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The user's playlists as a grid of covers; one click starts playing it.
private struct PlaylistGrid: View {
    let playlists: [Playlist]
    let nowPlayingSite: String?
    let scale: CGFloat
    var play: (Playlist) -> Void
    var open: (Playlist) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118 * scale, maximum: 170 * scale), spacing: 18 * scale)],
                      alignment: .leading, spacing: 20 * scale) {
                ForEach(playlists) { list in
                    GridCard(playlist: list, scale: scale, play: { play(list) }, open: { open(list) })
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Click the cover to see the songs; the ▶ that appears on hover plays straight away.
private struct GridCard: View {
    let playlist: Playlist
    let scale: CGFloat
    var play: () -> Void
    var open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                PlaylistCover(playlist: playlist, cornerRadius: 14 * scale)
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: play) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15 * scale, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 38 * scale, height: 38 * scale)
                                .background(.white, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        }
                        .buttonStyle(PressableButtonStyle(hoverBackground: false))
                        .padding(8 * scale)
                        .opacity(hovering ? 1 : 0)
                        .offset(y: hovering ? 0 : 6)
                    }
                    .shadow(color: .black.opacity(hovering ? 0.45 : 0.3), radius: hovering ? 16 : 8, y: hovering ? 8 : 4)
                    .scaleEffect(hovering ? 1.03 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.title)
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                    if !playlist.subtitle.isEmpty {
                        Text(playlist.subtitle)
                            .font(.system(size: 11.5 * scale))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { hovering = over } }
        .help("Show songs in \(playlist.title)")
    }
}

/// The songs coming up, then the ones just played.
private struct QueuePanel: View {
    let queue: [QueueItem]
    let recent: [HistoryStore.Entry]
    let history: HistoryStore
    let scale: CGFloat
    /// Opening a song elsewhere makes no sense while the Mac is locked.
    let canOpen: Bool
    var play: (Int) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26 * scale) {
                if !queue.isEmpty {
                    section("Up Next") {
                        ForEach(queue) { item in
                            QueueRow(title: item.title, subtitle: item.artist, scale: scale, enabled: true) {
                                QueueArtwork(url: item.artwork, cornerRadius: 0)
                            } action: { play(item.id) }
                        }
                    }
                }
                if !recent.isEmpty {
                    section("Recently Played") {
                        ForEach(recent) { entry in
                            QueueRow(title: entry.title,
                                     subtitle: [entry.artist.isEmpty ? entry.source : entry.artist,
                                                entry.playedAt.formatted(.relative(presentation: .named))].joined(separator: " · "),
                                     scale: scale, enabled: canOpen) {
                                ArtworkView(image: history.thumbnail(for: entry), cornerRadius: 0)
                            } action: { history.open(entry) }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Text(title.uppercased())
                .font(.system(size: 11.5 * scale, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.45))
            rows()
        }
    }
}

private struct QueueRow<Art: View>: View {
    let title: String
    let subtitle: String
    let scale: CGFloat
    let enabled: Bool
    @ViewBuilder var art: () -> Art
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14 * scale) {
                art()
                    .frame(width: 50 * scale, height: 50 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13.5 * scale))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "play.fill")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .opacity(hovering && enabled ? 1 : 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(hovering && enabled ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { over in withAnimation(.smooth(duration: 0.15)) { hovering = over } }
    }
}

// MARK: - Pieces

private struct Backdrop: View {
    @ObservedObject var center: NowPlayingCenter
    let animate: Bool

    var body: some View {
        ZStack {
            center.palette.background
            if #available(macOS 15.0, *) {
                BreathingMesh(palette: center.palette, animate: animate)
                    .transition(.opacity)
            } else if let art = center.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 80)
                    .scaleEffect(1.35)
                    .opacity(0.85)
                    .id(ObjectIdentifier(art))
                    .transition(.opacity.animation(.smooth(duration: 1.2)))
            }
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.25), .black.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .animation(.easeInOut(duration: 1.4), value: center.palette)
    }
}

/// Apple Music-style living background: a mesh of the cover's colours whose
/// control points drift slowly, like the colours are breathing.
/// sin-based drift for mesh points, `amount` either side of rest.
private struct Wobble {
    let t: Double
    func callAsFunction(_ speed: Double, _ phase: Double, _ amount: Double) -> Float {
        Float(sin(t * speed + phase) * amount)
    }
}

@available(macOS 15.0, *)
private struct BreathingMesh: View {
    let palette: ArtworkPalette
    let animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animate)) { ctx in
            let wobble = Wobble(t: ctx.date.timeIntervalSinceReferenceDate).callAsFunction
            let deep = palette.background
            let accent = palette.accent
            let second = palette.secondary
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + wobble(0.21, 0, 0.18), 0], [1, 0],
                    [0, 0.5 + wobble(0.17, 1.3, 0.2)], [0.5 + wobble(0.13, 2.1, 0.22), 0.5 + wobble(0.19, 0.4, 0.22)],
                    [1, 0.5 + wobble(0.15, 3.1, 0.2)],
                    [0, 1], [0.5 + wobble(0.23, 4.2, 0.18), 1], [1, 1],
                ],
                colors: [
                    accent.mix(with: deep, by: 0.35), second.mix(with: deep, by: 0.45), deep,
                    deep, accent.mix(with: second, by: 0.5 + Double(wobble(0.11, 0.9, 0.4))), second.mix(with: deep, by: 0.3),
                    second.mix(with: deep, by: 0.55), deep, accent.mix(with: deep, by: 0.5),
                ],
                smoothsColors: true
            )
            .saturation(1.15)
        }
    }
}

private struct ClockHeader: View {
    let scale: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(spacing: -6 * scale) {
                Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 26 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                GlassText(text: Self.time(ctx.date), size: 150 * scale)
            }
        }
    }

    private static func time(_ date: Date) -> String {
        let f = DateFormatter()
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "H"
        f.dateFormat = template.contains("a") ? "h:mm" : "H:mm"
        return f.string(from: date)
    }
}

/// Lock-screen style numerals: translucent fill, bright rim, soft depth.
struct GlassText: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let font = Font.system(size: size, weight: .semibold, design: .rounded)
        Text(text)
            .font(font)
            .foregroundStyle(
                LinearGradient(colors: [.white.opacity(0.75), Color(red: 0.75, green: 0.88, blue: 1).opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                Text(text)
                    .font(font)
                    .foregroundStyle(
                        LinearGradient(colors: [.white.opacity(0.9), .clear, .white.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .blendMode(.overlay)
            }
            .shadow(color: .white.opacity(0.35), radius: 0.5, x: -0.5, y: -0.5)
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

private struct StageArtwork: View {
    @ObservedObject var center: NowPlayingCenter
    let size: CGFloat
    var onTap: () -> Void = {}

    var body: some View {
        ArtworkView(image: center.artwork, cornerRadius: size * 0.045, palette: center.palette)
            .frame(width: size, height: size)
            .scaleEffect(center.track?.isPlaying == false ? 0.9 : 1)
            .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
            .animation(.bouncy(duration: 0.55, extraBounce: 0.08), value: center.track?.isPlaying)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }
}

/// The glass control card under the artwork.
struct PlayerCard: View {
    @ObservedObject var center: NowPlayingCenter
    @ObservedObject var audio: AudioMonitor
    var width: CGFloat = 340
    var overDesktop = false

    var body: some View {
        let track = center.track
        VStack(spacing: 6) {
            ZStack {
                VStack(spacing: 1) {
                    Text(track?.title ?? "Not Playing")
                        .font(.system(size: 13.5, weight: .bold))
                    Text(track.map { $0.artist.isEmpty ? $0.album : $0.artist } ?? "")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                .padding(.horizontal, 36)
                HStack {
                    Spacer()
                    Waveform(isPlaying: track?.isPlaying == true, palette: center.palette, bars: 5, barWidth: 2, spacing: 1.5, height: 11)
                }
            }
            .foregroundStyle(.white)

            if let track, track.duration > 0 {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let position = track.position(at: ctx.date)
                    HStack(spacing: 8) {
                        Text(TimeFormat.clock(position)).frame(width: 34, alignment: .leading)
                        ProgressScrubber(duration: track.duration, position: position) { center.seek(to: $0) }
                        Text("-" + TimeFormat.clock(max(0, track.duration - position))).frame(width: 38, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                }
            }

            HStack(spacing: 0) {
                Group {
                    if let note = track?.note {
                        InfoBadge(message: note)
                    } else if track?.supportsLike == true {
                        IconButton(symbol: track?.liked == true ? "heart.fill" : "heart", size: 15) {
                            center.perform(.like(!(track?.liked ?? false)))
                        }
                    } else if track?.shuffle != nil {
                        IconButton(symbol: "shuffle", size: 13, active: track?.shuffle == true) { center.perform(.toggleShuffle) }
                    } else {
                        // Sized so the empty slot can't stretch the card vertically.
                        Color.clear.frame(height: 24)
                    }
                }
                .frame(width: 30)
                Spacer(minLength: 0)
                TransportControls(center: center, size: 16, showModes: false)
                    .frame(width: width * 0.52)
                Spacer(minLength: 0)
                OutputPicker(audio: audio, size: 13)
                    .frame(width: 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .glass(cornerRadius: 22, overDesktop: overDesktop, tint: center.palette.accent)
    }
}

private struct Sidebar: View {
    let context: StageView.Context
    @Binding var lyricsOn: Bool
    let hasLyrics: Bool
    var onClose: () -> Void
    var onSettings: () -> Void
    var onHistory: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if context == .player {
                IconButton(symbol: "xmark", size: 12, action: onClose)
            }
            IconButton(symbol: lyricsOn ? "quote.bubble.fill" : "quote.bubble", size: 12, active: hasLyrics) {
                withAnimation(.smooth) { lyricsOn.toggle() }
            }
            if context == .player {
                IconButton(symbol: "clock.arrow.circlepath", size: 12, action: onHistory)
                IconButton(symbol: "gearshape", size: 12, action: onSettings)
            }
        }
        .padding(5)
        .glass(cornerRadius: 22)
    }
}

// MARK: - Lyrics

struct LyricsView: View {
    let lyrics: Lyrics
    let track: TrackSnapshot
    let fontSize: CGFloat
    /// Manual correction added to the playback position, set with the ± buttons.
    var offset: TimeInterval = 0
    var onSeek: (TimeInterval) -> Void
    var onNudge: (TimeInterval) -> Void = { _ in }

    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            LyricsScroll(lyrics: lyrics, track: track, offset: offset,
                         current: lyrics.index(at: track.position(at: ctx.date) + offset),
                         fontSize: fontSize, onSeek: onSeek)
        }
        .overlay(alignment: .bottomTrailing) {
            if lyrics.isSynced && (hovering || offset != 0) {
                SyncNudge(offset: offset, onNudge: onNudge)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
            }
        }
        .onHover { over in withAnimation(.smooth(duration: 0.25)) { hovering = over } }
    }
}

/// "Lyrics are early / late" fine-tuning, for when the position is only estimated.
private struct SyncNudge: View {
    let offset: TimeInterval
    var onNudge: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "minus", size: 10) { onNudge(-0.5) }
            Text(String(format: "%+.1fs", offset))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44)
                .contentTransition(.numericText())
            IconButton(symbol: "plus", size: 10) { onNudge(0.5) }
        }
        .padding(.horizontal, 4)
        .glass(cornerRadius: 16, overDesktop: true)
        .help("Lyrics ahead or behind? Nudge them, or click the line being sung.")
    }
}

private struct LyricsScroll: View {
    let lyrics: Lyrics
    let track: TrackSnapshot
    let offset: TimeInterval
    let current: Int?
    let fontSize: CGFloat
    var onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: fontSize * 0.75) {
                        ForEach(lyrics.lines) { line in
                            let distance = current.map { abs(line.id - $0) } ?? (lyrics.isSynced ? 3 : 0)
                            Group {
                                if distance == 0, lyrics.isSynced, !line.words.isEmpty {
                                    KaraokeLine(line: line, track: track, offset: offset, fontSize: fontSize)
                                } else {
                                    Text(line.text)
                                        .font(.system(size: fontSize, weight: .bold))
                                        .foregroundStyle(.white.opacity(lyrics.isSynced ? (distance == 0 ? 1 : 0.32) : 0.85))
                                }
                            }
                            .blur(radius: lyrics.isSynced ? min(CGFloat(distance), 4) * 0.8 : 0)
                            .scaleEffect(distance == 0 ? 1 : 0.96, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { if lyrics.isSynced { onSeek(line.time) } }
                            .id(line.id)
                            .animation(.spring(response: 0.6, dampingFraction: 0.9), value: current)
                        }
                    }
                    .padding(.vertical, geo.size.height * 0.4)
                }
                .onChange(of: current) { _, index in
                    guard let index else { return }
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.92)) {
                        proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.35))
                    }
                }
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.35)) }
                }
            }
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                                       .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// The line being sung, lit word by word like Apple Music.
private struct KaraokeLine: View {
    let line: Lyrics.Line
    let track: TrackSnapshot
    let offset: TimeInterval
    let fontSize: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !track.isPlaying)) { ctx in
            let t = track.position(at: ctx.date) + offset
            FlowLayout(spacing: fontSize * 0.26, lineSpacing: fontSize * 0.1) {
                ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                    let span = max(word.end - word.start, 0.05)
                    KaraokeWord(text: word.text, progress: CGFloat(min(max((t - word.start) / span, 0), 1)),
                                fontSize: fontSize)
                }
            }
        }
    }
}

private struct KaraokeWord: View {
    let text: String
    let progress: CGFloat
    let fontSize: CGFloat

    var body: some View {
        let font = Font.system(size: fontSize, weight: .bold)
        Text(text)
            .font(font)
            .foregroundStyle(.white.opacity(0.35))
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.45 * Double(progress)), radius: fontSize * 0.25)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            // A soft leading edge reads as light sweeping across, not a hard cut.
                            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.85),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width * progress * 1.15)
                        }
                    }
            }
            .offset(y: -fontSize * 0.06 * min(progress * 2, 1))
    }
}

/// Lays words out left to right, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Lock card

/// The compact glass player floating on the real lock screen.
struct LockCardView: View {
    @ObservedObject var center: NowPlayingCenter
    @ObservedObject var audio: AudioMonitor
    @ObservedObject var presentation: StagePresentation

    var body: some View {
        let track = center.track
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ArtworkView(image: center.artwork, cornerRadius: 9, palette: center.palette)
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "").font(.system(size: 14, weight: .semibold))
                    Text(track.map { $0.artist.isEmpty ? $0.album : $0.artist } ?? "").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                .foregroundStyle(.white)
                Spacer(minLength: 4)
                Waveform(isPlaying: track?.isPlaying == true, palette: center.palette, bars: 4, barWidth: 2.4, spacing: 2, height: 14)
            }
            if let track, track.duration > 0 {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let position = track.position(at: ctx.date)
                    VStack(spacing: 3) {
                        ProgressScrubber(duration: track.duration, position: position) { center.seek(to: $0) }
                        TimeLabels(position: position, duration: track.duration)
                    }
                }
            }
            HStack {
                Group {
                    if track?.shuffle != nil {
                        IconButton(symbol: "shuffle", size: 12, active: track?.shuffle == true) { center.perform(.toggleShuffle) }
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
                .frame(width: 34)
                Spacer()
                TransportControls(center: center, size: 18, showModes: false).frame(width: 170)
                Spacer()
                OutputPicker(audio: audio, size: 13)
            }
        }
        .padding(16)
        .frame(width: 340)
        .glass(cornerRadius: 28, overDesktop: true)
        .scaleEffect(presentation.isVisible ? 1 : 0.9)
        .blur(radius: presentation.isVisible ? 0 : 12)
        .opacity(presentation.isVisible ? 1 : 0)
        .animation(Motion.open, value: presentation.isVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}
