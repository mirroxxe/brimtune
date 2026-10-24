import AppKit
import SwiftUI

// MARK: - Motion

enum Motion {
    // Springs rather than timed curves: they carry velocity from one change into the
    // next, so hovering in and out mid-animation never jerks.
    static let open = Animation.spring(response: 0.46, dampingFraction: 0.8)
    static let close = Animation.spring(response: 0.4, dampingFraction: 0.95)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.9)
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// The soft blur-and-scale morph Apple uses when island content swaps.
    static var morph: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.88, anchor: .top))
                .animation(.spring(response: 0.42, dampingFraction: 0.92).delay(0.06)),
            removal: .modifier(active: BlurModifier(radius: 8), identity: BlurModifier(radius: 0))
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.94, anchor: .top))
                .animation(.easeOut(duration: 0.18))
        )
    }
}

extension AnyTransition {
    /// Covers melt into each other: the new one comes into focus as the old one
    /// softens and fades, with only a hint of scale.
    static var coverSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0))
                .combined(with: .scale(scale: 1.06))
                .combined(with: .opacity)
                .animation(.easeInOut(duration: 0.8)),
            removal: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0))
                .combined(with: .opacity)
                .animation(.easeInOut(duration: 0.8))
        )
    }
}

// MARK: - Glass

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

extension View {
    /// Liquid Glass where available. `overDesktop` is for transparent windows, where
    /// the blur has to come from the window server rather than from our own content.
    @ViewBuilder
    func glass(cornerRadius: CGFloat, overDesktop: Bool = false, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if !overDesktop, #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint?.opacity(0.18)), in: shape)
        } else {
            self
                .background {
                    ZStack {
                        VisualEffect(material: overDesktop ? .hudWindow : .popover, blending: overDesktop ? .behindWindow : .withinWindow)
                        (tint ?? .white).opacity(0.08)
                        LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
                    }
                    .clipShape(shape)
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        }
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 8
    var palette: ArtworkPalette = .fallback

    var body: some View {
        // The frame decides the size; a wide cover is cropped inside it, never spilling over its neighbours.
        Color.clear.overlay { ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.coverSwap)
                    .id(ObjectIdentifier(image))
            } else {
                // Apple Music's quiet grey placeholder rather than a loud gradient.
                LinearGradient(colors: [Color(white: 0.3), Color(white: 0.17)], startPoint: .top, endPoint: .bottom)
                GeometryReader { geo in
                    Image(systemName: "music.note")
                        .font(.system(size: geo.size.width * 0.34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }
}

// MARK: - Waveform

/// Bars that follow the music when the audio tap is live, dance on their own
/// otherwise, and settle flat when paused.
struct Waveform: View {
    var isPlaying: Bool
    var palette: ArtworkPalette
    var bars = 5
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2.5
    var height: CGFloat = 16

    @ObservedObject private var levels = AudioLevels.shared

    private let speeds: [Double] = [5.1, 7.3, 4.2, 6.6, 5.7, 8.1]
    private let phases: [Double] = [0.0, 1.3, 2.6, 0.7, 3.9, 2.0]

    var body: some View {
        if isPlaying, levels.isLive {
            live
        } else {
            simulated
        }
    }

    private var live: some View {
        gradient
            .mask {
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<bars, id: \.self) { i in
                        let band = levels.bands[min(i * levels.bands.count / bars, levels.bands.count - 1)]
                        Capsule().frame(width: barWidth, height: barWidth + (height - barWidth) * CGFloat(band))
                    }
                }
                .frame(height: height)
            }
            .frame(width: CGFloat(bars) * barWidth + CGFloat(bars - 1) * spacing, height: height)
            .animation(.linear(duration: 0.07), value: levels.bands)
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [palette.accent, palette.secondary], startPoint: .leading, endPoint: .trailing)
    }

    private var simulated: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            LinearGradient(colors: [palette.accent, palette.secondary], startPoint: .leading, endPoint: .trailing)
                .mask {
                    HStack(alignment: .center, spacing: spacing) {
                        ForEach(0..<bars, id: \.self) { i in
                            Capsule().frame(width: barWidth, height: barHeight(i, t))
                        }
                    }
                    .frame(height: height)
                }
                .frame(width: CGFloat(bars) * barWidth + CGFloat(bars - 1) * spacing, height: height)
        }
        .animation(.smooth(duration: 0.35), value: isPlaying)
    }

    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        let minH = barWidth
        guard isPlaying else { return minH }
        let s = speeds[i % speeds.count], p = phases[i % phases.count]
        let v = 0.5 + 0.3 * sin(t * s + p) + 0.2 * sin(t * s * 1.9 + p * 2.3)
        return minH + (height - minH) * CGFloat(max(0.08, min(1, v)))
    }
}

// MARK: - Progress

struct ProgressScrubber: View {
    let duration: TimeInterval
    let position: TimeInterval
    var tint: Color = .white
    var onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let fraction = dragFraction ?? (duration > 0 ? position / duration : 0)
            let active = hovering || dragFraction != nil
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(0, geo.size.width * min(1, fraction)))
            }
            .frame(height: active ? 7 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        dragFraction = min(1, max(0, value.location.x / geo.size.width))
                    }
                    .onEnded { _ in
                        guard let f = dragFraction else { return }
                        onSeek(f * duration)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { dragFraction = nil }
                    }
            )
            .animation(Motion.snappy, value: active)
        }
        .frame(height: 12)
    }
}

struct TimeLabels: View {
    let position: TimeInterval
    let duration: TimeInterval

    var body: some View {
        HStack {
            Text(TimeFormat.clock(position))
            Spacer()
            Text("-" + TimeFormat.clock(max(0, duration - position)))
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Buttons

struct PressableButtonStyle: ButtonStyle {
    var hoverBackground = true

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, hoverBackground: hoverBackground)
    }

    private struct PressableBody: View {
        let configuration: Configuration
        let hoverBackground: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(6)
                .background {
                    Circle()
                        .fill(.white.opacity(hoverBackground && hovering ? 0.12 : 0))
                        .scaleEffect(configuration.isPressed ? 0.85 : 1)
                }
                .scaleEffect(configuration.isPressed ? 0.86 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.snappy(duration: 0.2), value: configuration.isPressed)
                .animation(.smooth(duration: 0.2), value: hovering)
        }
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 15
    var active = true
    var bounceTrigger: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 1 : 0.45))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounceTrigger)
                .frame(width: size * 1.6, height: size * 1.6)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Previous / play-pause / next, plus optional shuffle & repeat.
struct TransportControls: View {
    @ObservedObject var center: NowPlayingCenter
    var size: CGFloat = 18
    var showModes = true

    @State private var prevTaps = 0
    @State private var nextTaps = 0

    var body: some View {
        let t = center.track
        HStack(spacing: 0) {
            if showModes {
                IconButton(symbol: "shuffle", size: size * 0.72, active: t?.shuffle == true) { center.perform(.toggleShuffle) }
                Spacer(minLength: 0)
            }
            IconButton(symbol: "backward.fill", size: size, bounceTrigger: prevTaps) {
                prevTaps += 1; center.perform(.previous)
            }
            Spacer(minLength: 0)
            IconButton(symbol: t?.isPlaying == true ? "pause.fill" : "play.fill", size: size * 1.3) {
                center.perform(.togglePlayPause)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "forward.fill", size: size, bounceTrigger: nextTaps) {
                nextTaps += 1; center.perform(.next)
            }
            if showModes {
                Spacer(minLength: 0)
                IconButton(symbol: t?.repeatMode == .one ? "repeat.1" : "repeat", size: size * 0.72,
                           active: (t?.repeatMode ?? .off) != .off) { center.perform(.cycleRepeat) }
            }
        }
    }
}

/// The headphones button: shows the current output and switches between outputs.
struct OutputPicker: View {
    @ObservedObject var audio: AudioMonitor
    var size: CGFloat = 15

    var body: some View {
        Menu {
            ForEach(audio.outputs) { output in
                Button {
                    audio.select(output)
                } label: {
                    Label(output.name, systemImage: output.id == audio.current?.id ? "checkmark" : output.symbol)
                }
            }
        } label: {
            Image(systemName: audio.current?.isBluetooth == true ? "headphones" : "airplay.audio")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 1.6, height: size * 1.6)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(6)
    }
}

/// Remote cover art for queue and search rows, with a quiet placeholder while it
/// loads or when the page didn't expose one.
struct QueueArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 6

    var body: some View {
        // The slot's size comes from the frame the caller gives it; a wide thumbnail
        // is cropped inside it instead of stretching the row into the text beside it.
        Color.clear
            .overlay {
                AsyncImage(url: url.flatMap { $0.scheme == "data" ? nil : $0 }, transaction: Transaction(animation: .smooth(duration: 0.3))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                    } else {
                        ZStack {
                            LinearGradient(colors: [Color(white: 0.26), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                            Image(systemName: "music.note")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// A playlist's cover: YouTube's image when there is one, otherwise a soft
/// gradient drawn from the name, so every playlist still looks distinct.
struct PlaylistCover: View {
    let playlist: Playlist
    var cornerRadius: CGFloat = 12

    var body: some View {
        // A square slot first, so a wide cover can't stretch the layout.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { drawn }
            .overlay {
                if let url = playlist.artwork {
                    AsyncImage(url: url, transaction: Transaction(animation: .smooth(duration: 0.35))) { phase in
                        if case .success(let image) = phase {
                            // YouTube covers are 16:9 video frames; crop to the square middle.
                            image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                        }
                    }
                }
            }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }

    private var drawn: some View {
        let seed = playlist.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(seed % 360) / 360
        let top = playlist.isLiked ? Color(hue: 0.95, saturation: 0.65, brightness: 0.95) : Color(hue: hue, saturation: 0.55, brightness: 0.85)
        let bottom = playlist.isLiked ? Color(hue: 0.75, saturation: 0.7, brightness: 0.55) : Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.45)
        return GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.25), .clear], center: .topLeading, startRadius: 0, endRadius: geo.size.width)
                Image(systemName: playlist.isLiked ? "heart.fill" : "music.note.list")
                    .font(.system(size: geo.size.width * 0.32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }
}

/// The songs of a playlist with a header; used in the island and on the stage.
/// `scale` grows everything for the big screens.
struct PlaylistSongList: View {
    @ObservedObject var center: NowPlayingCenter
    let playlist: Playlist
    var scale: CGFloat = 1
    /// Fixed height of the scrolling list; nil lets it fill the space it's given.
    var listHeight: CGFloat?
    var back: () -> Void
    var played: () -> Void = {}

    var body: some View {
        let songs = center.playlistSongs[playlist.id] ?? []
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(spacing: 12 * scale) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28 * scale, height: 28 * scale)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(PressableButtonStyle(hoverBackground: false))
                .help("Back")
                PlaylistCover(playlist: playlist, cornerRadius: 9 * scale)
                    .frame(width: 46 * scale, height: 46 * scale)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.title)
                        .font(.system(size: 15 * scale, weight: .bold))
                        .foregroundStyle(.white)
                    Text([songs.isEmpty ? nil : "\(songs.count) songs", playlist.subtitle.isEmpty ? nil : playlist.subtitle]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11.5 * scale))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                Button {
                    center.play(playlist)
                    played()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 10 * scale, weight: .bold))
                        Text("Play").font(.system(size: 12.5 * scale, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 13 * scale).padding(.vertical, 6 * scale)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle(hoverBackground: false))
            }

            Group {
                if songs.isEmpty {
                    HStack(spacing: 8) {
                        if center.loadingPlaylists.contains(playlist.id) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Loading songs…")
                        } else {
                            Text("No songs found")
                        }
                    }
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 60 * scale)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                SongRow(song: song, index: index + 1, scale: scale,
                                        isCurrent: song.title == center.track?.title) {
                                    center.play(song, in: playlist)
                                    played()
                                }
                            }
                        }
                    }
                    .frame(height: listHeight.map { min($0, CGFloat(songs.count) * 42 * scale) })
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                               .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    }
                }
            }
            .transition(.opacity)
        }
        .onAppear { center.loadSongs(for: playlist) }
    }
}

private struct SongRow: View {
    let song: PlaylistSong
    let index: Int
    let scale: CGFloat
    let isCurrent: Bool
    var play: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10 * scale) {
                ZStack {
                    if hovering {
                        Image(systemName: "play.fill").font(.system(size: 10 * scale, weight: .bold))
                    } else if isCurrent {
                        Image(systemName: "waveform").font(.system(size: 11 * scale, weight: .bold)).foregroundStyle(.pink)
                    } else {
                        Text("\(index)").font(.system(size: 11 * scale, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 20 * scale)
                QueueArtwork(url: song.artwork, cornerRadius: 5 * scale)
                    .frame(width: 32 * scale, height: 32 * scale)
                VStack(alignment: .leading, spacing: 0) {
                    Text(song.title)
                        .font(.system(size: 12.5 * scale, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.pink : .white)
                    Text(song.artist)
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                Text(song.duration)
                    .font(.system(size: 11 * scale).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6 * scale)
            .frame(height: 42 * scale)
            .background(.white.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 9 * scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.smooth(duration: 0.12)) { hovering = over } }
    }
}

/// A small ⓘ that explains how to unlock fuller browser support.
struct InfoBadge: View {
    let message: String

    var body: some View {
        IconButton(symbol: "info.circle", size: 12, active: false) {
            let alert = NSAlert()
            alert.messageText = "Show more from your browser"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        .help(message)
    }
}

// MARK: - Notch shape

/// The island outline: concave flares where it meets the screen edge, rounded below.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = min(topRadius, rect.width / 4)
        let br = min(bottomRadius, (rect.height - tr), (rect.width - 2 * tr) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr), control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY), control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br), control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Hosting

/// Lets the first click on a non-key panel reach SwiftUI controls.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Volume

/// A speaker and a slider for the music's own volume (the Mac's volume is left alone).
/// The bar thickens and shows a thumb when the pointer is on it, the speaker steps through
/// its waves as the level changes, and the percentage rises above the thumb while dragging.
struct VolumeSlider: View {
    @ObservedObject var center: NowPlayingCenter
    @State private var dragLevel: Double?
    @State private var hovering = false
    @State private var beforeMute: Double = 0.5

    private var shown: Double { dragLevel ?? center.musicVolume ?? 0 }

    private var symbol: String {
        switch shown {
        case ..<0.005: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    var body: some View {
        let active = hovering || dragLevel != nil
        HStack(spacing: 10) {
            Button {
                if shown > 0.005 { beforeMute = shown; center.setVolume(0) } else { center.setVolume(beforeMute) }
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(active ? 0.85 : 0.5))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mute")

            GeometryReader { geo in
                let width = geo.size.width
                let thumb: CGFloat = 12
                let x = CGFloat(shown) * (width - thumb) + thumb / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.9)).frame(width: max(0, x))
                    Circle().fill(.white)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .scaleEffect(dragLevel != nil ? 1.2 : active ? 1 : 0.01)
                        .offset(x: x - thumb / 2)
                        .overlay(alignment: .top) {
                            Text("\(Int((shown * 100).rounded()))")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                                .fixedSize()
                                .offset(y: -17)
                                .opacity(dragLevel != nil ? 1 : 0)
                        }
                }
                .frame(height: active ? 7 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = Double(min(1, max(0, (value.location.x - thumb / 2) / max(1, width - thumb))))
                            dragLevel = f
                            center.setVolume(f)
                        }
                        .onEnded { _ in dragLevel = nil }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: dragLevel != nil)
                .animation(dragLevel == nil ? .smooth(duration: 0.25) : nil, value: shown)
            }
            .frame(height: 22)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 20)
        }
        .frame(height: 22)
    }
}
