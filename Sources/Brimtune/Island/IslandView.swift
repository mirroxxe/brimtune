import AppKit
import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var center: NowPlayingCenter
    @ObservedObject var activities: ActivityCenter
    var openStage: () -> Void
    var openSettings: () -> Void
    var tapped: () -> Void
    var playSearch: (SearchResult) -> Void
    var dismissSearch: () -> Void
    var requestKeyboard: () -> Void

    @Namespace private var ns

    var body: some View {
        let size = model.size(for: model.mode)
        let radii = model.radii(for: model.mode)
        let pill = model.floating && (model.mode == .compact || model.mode == .hidden || model.mode == .idle)
        let shape = IslandOutline(topRadius: radii.top, bottomRadius: pill ? size.height / 2 : radii.bottom,
                                  floating: model.floating)
        let accent = center.palette.accent

        ZStack(alignment: .top) {
            shape.fill(.black)
            content(inset: model.floating ? radii.bottom * 0.45 : radii.top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        // A soft iridescent sheen of the album's colours drifting across on a new cover.
        .modifier(Shimmer(progress: model.shimmer, shape: shape,
                          colors: [accent, center.palette.secondary]))
        .contentShape(shape)
        .onTapGesture(perform: tapped)
        .shadow(color: .black.opacity(model.mode == .expanded ? 0.5 : model.mode == .idle ? 0 : 0.25),
                radius: model.mode == .expanded ? 22 : 10, y: 8)
        .opacity(model.mode == .hidden ? 0 : 1)
        .scaleEffect(model.mode == .hidden ? 0.85 : 1, anchor: .top)
        .padding(.top, model.floating ? IslandModel.floatingInset : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(inset: CGFloat) -> some View {
        let h = model.notch.height
        switch model.mode {
        case .hidden, .idle:
            Color.clear
        case .compact:
            // Floating, the cover sits as far from the pill's left edge as from its top and bottom.
            CompactContent(center: center, activities: activities, ns: ns, notchHeight: h)
                .padding(.leading, model.floating ? 6 : inset + 10)
                .padding(.trailing, model.floating ? 14 : inset + 10)
                .transition(.morph)
        case .peek:
            PeekContent(center: center, ns: ns, notchHeight: h)
                .padding(.horizontal, inset + 12)
                .transition(.morph)
        case .alert:
            if let alert = model.alert {
                AlertContent(alert: alert, reserve: model.topReserve)
                    .padding(.horizontal, inset + 18)
                    .transition(.morph)
            }
        case .expanded:
            ExpandedContent(center: center, activities: activities, model: model, ns: ns, reserve: model.topReserve,
                            openStage: openStage, openSettings: openSettings,
                            playSearch: playSearch, dismissSearch: dismissSearch, requestKeyboard: requestKeyboard)
                .padding(.horizontal, inset + 18)
                .transition(.morph)
                .onPreferenceChange(ExpandedHeightKey.self) { height in
                    guard height > 0, abs(height - model.expandedContentHeight) > 0.5 else { return }
                    withAnimation(Motion.open) { model.expandedContentHeight = height }
                }
        }
    }
}

/// A band of colour gliding across the island and its rim, fading in and out
/// along the way, so a track change reads as a gentle shimmer rather than a flash.
private struct Shimmer<S: Shape>: ViewModifier, Animatable {
    var progress: CGFloat
    let shape: S
    let colors: [Color]

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let strength = sin(.pi * min(max(progress, 0), 1))
        content
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(colors: [.clear] + colors.map { $0.opacity(0.22) } + [.clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.8)
                        .rotationEffect(.degrees(12))
                        .offset(x: -w * 0.8 + w * 1.8 * progress)
                        .blur(radius: 10)
                }
                .mask(shape)
                .blendMode(.plusLighter)
                .opacity(strength)
                .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .stroke(AngularGradient(colors: colors + [colors.first ?? .clear],
                                            center: .center, angle: .degrees(360 * progress)),
                            lineWidth: 1)
                    .opacity(0.45 * strength)
                    .allowsHitTesting(false)
            }
    }
}

/// Notch-hugging outline on built-in displays, a free-floating pill elsewhere.
struct IslandOutline: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var floating: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        floating
            ? RoundedRectangle(cornerRadius: min(bottomRadius, rect.height / 2), style: .continuous).path(in: rect)
            : NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
    }
}

extension IslandModel {
    /// Empty space kept above expanded content: the notch, or a little air when floating.
    var topReserve: CGFloat { floating ? 12 : notch.height }
}

// MARK: - Activities

private enum LiveActivity {
    case meeting(ActivityCenter.Meeting)
    case timer(ActivityCenter.CountdownTimer)
    case stopwatch(ActivityCenter.Stopwatch)

    /// Most urgent first: a meeting about to start, then a timer, then a stopwatch.
    @MainActor
    static func primary(in a: ActivityCenter) -> LiveActivity? {
        if let m = a.meeting { return .meeting(m) }
        if let t = a.timer { return .timer(t) }
        if let s = a.stopwatch { return .stopwatch(s) }
        return nil
    }

    var symbol: String {
        switch self {
        case .meeting: "calendar"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        }
    }

    var tint: Color {
        switch self {
        case .meeting(let m): m.color.map(Color.init(nsColor:)) ?? .blue
        case .timer: .orange
        case .stopwatch: .orange
        }
    }

    func text(at date: Date) -> String {
        switch self {
        case .meeting(let m):
            let left = m.start.timeIntervalSince(date)
            return left <= 0 ? "Now" : TimeFormat.clock(left)
        case .timer(let t): return TimeFormat.clock(t.remaining(at: date).rounded(.up))
        case .stopwatch(let s): return TimeFormat.clock(s.elapsed(at: date))
        }
    }
}

private struct ActivityBadge: View {
    let activity: LiveActivity

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            HStack(spacing: 4) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 10.5, weight: .bold))
                Text(activity.text(at: ctx.date))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
            }
            .foregroundStyle(activity.tint)
        }
    }
}

// MARK: - Compact

private struct CompactContent: View {
    @ObservedObject var center: NowPlayingCenter
    @ObservedObject var activities: ActivityCenter
    let ns: Namespace.ID
    let notchHeight: CGFloat

    var body: some View {
        let activity = LiveActivity.primary(in: activities)
        HStack(spacing: 0) {
            if center.track != nil {
                ArtworkView(image: center.artwork, cornerRadius: 6, palette: center.palette)
                    .matchedGeometryEffect(id: "art", in: ns)
                    .frame(width: notchHeight - 12, height: notchHeight - 12)
                    // On pause the cover sinks a little before the island folds into the notch.
                    .scaleEffect(center.track?.isPlaying == true ? 1 : 0.78)
                    .opacity(center.track?.isPlaying == true ? 1 : 0.6)
                    .animation(Motion.open, value: center.track?.isPlaying)
            } else if let activity {
                Image(systemName: activity.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(activity.tint)
            }
            Spacer(minLength: 0)
            if let activity {
                ActivityBadge(activity: activity)
                    .transition(.morph)
            } else {
                Waveform(isPlaying: center.track?.isPlaying == true, palette: center.palette,
                         bars: 4, barWidth: 2.6, spacing: 2, height: notchHeight * 0.42)
                    .matchedGeometryEffect(id: "wave", in: ns)
            }
        }
        .frame(height: notchHeight)
    }
}

// MARK: - Peek (track changed)

private struct PeekContent: View {
    @ObservedObject var center: NowPlayingCenter
    let ns: Namespace.ID
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ArtworkView(image: center.artwork, cornerRadius: 6, palette: center.palette)
                    .matchedGeometryEffect(id: "art", in: ns)
                    .frame(width: notchHeight - 8, height: notchHeight - 8)
                Spacer()
                Waveform(isPlaying: center.track?.isPlaying == true, palette: center.palette,
                         bars: 4, barWidth: 2.6, spacing: 2, height: notchHeight * 0.42)
                    .matchedGeometryEffect(id: "wave", in: ns)
            }
            .frame(height: notchHeight)
            .padding(.top, 4)

            VStack(spacing: 1) {
                Text(center.track?.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(center.track.map { $0.artist.isEmpty ? $0.album : $0.artist } ?? "")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(center.palette.accent.opacity(0.9))
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Alerts

private struct AlertContent: View {
    let alert: IslandAlert
    let reserve: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: reserve)
            Group {
                switch alert {
                case let .device(output, battery):
                    DeviceRow(output: output, battery: battery)
                case .timerDone:
                    AlertRow(symbol: "timer", tint: .orange, caption: "Timer", title: "Done")
                case let .meeting(meeting, now):
                    AlertRow(symbol: "calendar", tint: meeting.color.map(Color.init(nsColor:)) ?? .blue,
                             caption: now ? "Starting now" : "In \(Int((meeting.start.timeIntervalSinceNow / 60).rounded())) min",
                             title: meeting.title, join: meeting.joinURL)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct AlertRow: View {
    let symbol: String
    let tint: Color
    let caption: String
    let title: String
    var join: URL?
    @State private var ring = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: ring)
                .frame(width: 30)
                .onAppear { ring += 1 }
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let join { JoinButton(url: join) }
        }
    }
}

private struct JoinButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Text("Join")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.green, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Headphones connecting: the device turns in space, catches the light, settles.
private struct DeviceRow: View {
    let output: AudioOutput
    let battery: Int?
    @State private var appeared = false
    @State private var spin: Double = -200
    @State private var shine: CGFloat = -1
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            device
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Connected")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(output.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let battery {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(battery <= 20 ? Color.red : Color.green)
                                .frame(width: geo.size.width * CGFloat(battery) / 100 * ringProgress)
                        }
                    }
                    .frame(width: 44, height: 7)
                    Text("\(battery)")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            } else {
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24, height: 24)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { appeared = true }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.8)) { spin = 0 }
            withAnimation(.easeInOut(duration: 0.9).delay(0.45)) { shine = 1.4 }
            withAnimation(.smooth(duration: 0.9).delay(0.3)) { ringProgress = 1 }
        }
    }

    private var device: some View {
        let symbol = Image(systemName: output.symbol)
        return symbol
            .font(.system(size: 26, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .overlay {
                // A highlight sweeping across the device's surface.
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: geo.size.width * shine)
                }
                .mask(symbol.font(.system(size: 26, weight: .regular)))
                .blendMode(.plusLighter)
            }
            .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0.08), perspective: 0.55)
            .scaleEffect(appeared ? 1 : 0.35)
            .shadow(color: .white.opacity(0.25), radius: 6)
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    @ObservedObject var center: NowPlayingCenter
    @ObservedObject var activities: ActivityCenter
    @ObservedObject var model: IslandModel
    let ns: Namespace.ID
    let reserve: CGFloat
    var openStage: () -> Void
    var openSettings: () -> Void
    var playSearch: (SearchResult) -> Void
    var dismissSearch: () -> Void
    var requestKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: reserve)
            if let open = model.openPlaylist {
                PlaylistSongList(center: center, playlist: open, listHeight: 300, back: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { model.openPlaylist = nil }
                }, played: dismissSearch)
                .padding(.top, 6)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                mainContent
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .padding(.bottom, 16)
        // The island takes exactly the height its content needs.
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ExpandedHeightKey.self, value: geo.size.height)
            }
        }
        .contextMenu {
            Button("Full-Screen Player", action: openStage)
            Button("Settings…", action: openSettings)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let track = center.track {
                playing(track)
            }
            SearchArea(model: model, play: playSearch, dismiss: dismissSearch, requestKeyboard: requestKeyboard)
                .padding(.top, center.track == nil ? 6 : 14)
            // While results are on screen they have the island to themselves.
            if model.searchResults.isEmpty {
                if let track = center.track {
                    let upNext = track.upNext
                    if !upNext.isEmpty {
                        UpNextRow(items: upNext) { center.perform(.playQueueItem($0)) }
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                }
                if !center.playlists.isEmpty {
                    PlaylistShelf(playlists: center.playlists, play: { list in
                        center.play(list)
                        dismissSearch()
                    }, open: { list in
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { model.openPlaylist = list }
                    })
                    .padding(.top, 12)
                }
                activityRows
                    .padding(.top, 10)
                if center.track == nil && !activities.hasLiveActivity && !model.isSearching {
                    nothingPlaying
                }
            }
        }
    }

    @ViewBuilder
    private var activityRows: some View {
        VStack(spacing: 8) {
            if let meeting = activities.meeting {
                MeetingRow(meeting: meeting)
            }
            if let timer = activities.timer {
                TimerRow(timer: timer, toggle: activities.toggleTimer, cancel: activities.cancelTimer)
            }
            if let stopwatch = activities.stopwatch {
                StopwatchRow(stopwatch: stopwatch, toggle: activities.toggleStopwatch, reset: activities.resetStopwatch)
            }
        }
    }

    private func playing(_ track: TrackSnapshot) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ArtworkView(image: center.artwork, cornerRadius: 12, palette: center.palette)
                    .matchedGeometryEffect(id: "art", in: ns)
                    .frame(width: 54, height: 54)
                    .scaleEffect(track.isPlaying ? 1 : 0.92)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .onTapGesture(perform: openStage)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(track.artist.isEmpty ? track.album : track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                .contentTransition(.opacity)
                Spacer(minLength: 8)
                Waveform(isPlaying: track.isPlaying, palette: center.palette, bars: 4, barWidth: 2.6, spacing: 2, height: 14)
                    .matchedGeometryEffect(id: "wave", in: ns)
            }
            .animation(Motion.open, value: track.isPlaying)

            if track.duration > 0 {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let position = track.position(at: ctx.date)
                    HStack(spacing: 10) {
                        Text(TimeFormat.clock(position))
                            .frame(width: 32, alignment: .leading)
                        ProgressScrubber(duration: track.duration, position: position, tint: .white.opacity(0.9)) { center.seek(to: $0) }
                        Text("-" + TimeFormat.clock(max(0, track.duration - position)))
                            .frame(width: 36, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                }
            }

            HStack(spacing: 0) {
                leadingAccessory(track).frame(width: 30)
                Spacer(minLength: 0)
                TransportControls(center: center, size: 19, showModes: false)
                    .frame(width: 190)
                Spacer(minLength: 0)
                IconButton(symbol: "arrow.up.left.and.arrow.down.right", size: 11, active: false, action: openStage)
                    .frame(width: 30)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func leadingAccessory(_ track: TrackSnapshot) -> some View {
        if let note = track.note {
            InfoBadge(message: note)
        } else if track.shuffle != nil {
            IconButton(symbol: "shuffle", size: 11, active: track.shuffle == true) { center.perform(.toggleShuffle) }
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private var nothingPlaying: some View {
        VStack(spacing: 6) {
            Text("Nothing Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text("Play something in Music, Spotify or YouTube Music")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct ExpandedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Search

private struct SearchArea: View {
    @ObservedObject var model: IslandModel
    var play: (SearchResult) -> Void
    var dismiss: () -> Void
    var requestKeyboard: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(focused ? 0.75 : 0.4))
                TextField("", text: $model.searchQuery, prompt: Text("Search for a song").foregroundStyle(.white.opacity(0.32)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { if let first = model.searchResults.first { play(first) } }
                    .onExitCommand(perform: dismiss)
                if model.searchLoading {
                    ProgressView().controlSize(.mini).tint(.white)
                } else if !model.searchQuery.isEmpty {
                    Button { model.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(.white.opacity(focused ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.16 : 0.04), lineWidth: 1))
            .animation(.smooth(duration: 0.2), value: focused)
            // The island only takes the keyboard once you click into the field.
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                // The panel has to become key before the field can take focus; a field that
                // still thinks it is focused from an earlier click needs a fresh start.
                requestKeyboard()
                focused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
            })

            if !model.searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(model.searchResults.enumerated()), id: \.element.id) { index, result in
                        SearchResultRow(result: result, isFirst: index == 0) { play(result) }
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }
            }
        }
        .onChange(of: focused) { _, now in model.searchFocused = now }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let isFirst: Bool
    var play: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                QueueArtwork(url: result.thumbnail, cornerRadius: 7)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    Text([result.artist, result.duration].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: isFirst && !hovering ? "return" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering || isFirst ? 0.6 : 0))
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(.white.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.smooth(duration: 0.12)) { hovering = over } }
    }
}

private struct UpNextRow: View {
    let items: [QueueItem]
    var play: (Int) -> Void
    /// Remembered between sessions; the island resizes itself around the change.
    @AppStorage("upNextCollapsed") private var collapsed = false
    @State private var hoveringHeader = false
    @State private var page = 0

    private static let pageSize = 3

    var body: some View {
        let pages = max(1, (items.count + Self.pageSize - 1) / Self.pageSize)
        let current = min(page, pages - 1)
        let shown = Array(items.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { collapsed.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Up Next")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(hoveringHeader ? 0.7 : 0.45))
                        if collapsed {
                            Text("\(items.count)")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.white.opacity(0.1), in: Capsule())
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        Spacer()
                    }
                    .padding(.leading, 6)
                    .frame(height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapsed ? "Show up next" : "Hide up next")

                if !collapsed && pages > 1 {
                    pager("chevron.left", enabled: current > 0) { page = current - 1 }
                    pager("chevron.right", enabled: current < pages - 1) { page = current + 1 }
                }
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { collapsed.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(hoveringHeader ? 0.75 : 0.4))
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }
            .onHover { over in withAnimation(.smooth(duration: 0.15)) { hoveringHeader = over } }

            if !collapsed {
                ForEach(shown) { item in
                    UpNextItem(item: item) { play(item.id) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    private func pager(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.18))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct UpNextItem: View {
    let item: QueueItem
    var play: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                QueueArtwork(url: item.artwork, cornerRadius: 6)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(item.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .background(.white.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.smooth(duration: 0.12)) { hovering = over } }
        .help("Play \(item.title)")
    }
}

/// "Playlists": a row of covers you can scroll sideways; click one to play it.
private struct PlaylistShelf: View {
    let playlists: [Playlist]
    var play: (Playlist) -> Void
    var open: (Playlist) -> Void
    @AppStorage("playlistsCollapsed") private var collapsed = false
    @State private var hoveringHeader = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Playlists")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(hoveringHeader ? 0.7 : 0.45))
                    if collapsed {
                        Text("\(playlists.count)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.white.opacity(0.1), in: Capsule())
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(hoveringHeader ? 0.75 : 0.4))
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { over in withAnimation(.smooth(duration: 0.15)) { hoveringHeader = over } }

            if !collapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(playlists) { list in
                            ShelfCard(playlist: list, play: { play(list) }, open: { open(list) })
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                           .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

/// Click the cover to see the songs; the ▶ that appears on hover plays straight away.
private struct ShelfCard: View {
    let playlist: Playlist
    var play: () -> Void
    var open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 5) {
                PlaylistCover(playlist: playlist, cornerRadius: 10)
                    .frame(width: 66, height: 66)
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: play) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 24, height: 24)
                                .background(.white, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        }
                        .buttonStyle(PressableButtonStyle(hoverBackground: false))
                        .padding(2)
                        .opacity(hovering ? 1 : 0)
                        .scaleEffect(hovering ? 1 : 0.7)
                    }
                    .scaleEffect(hovering ? 1.04 : 1)
                    .shadow(color: .black.opacity(0.35), radius: hovering ? 8 : 4, y: 3)
                Text(playlist.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(width: 66, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = over } }
        .help("Show songs in \(playlist.title)")
    }
}

// MARK: - Activity rows

private struct RowIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.18), in: Circle())
    }
}

private struct RoundButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.2), in: Circle())
        }
        .buttonStyle(PressableButtonStyle(hoverBackground: false))
    }
}

private struct TimerRow: View {
    let timer: ActivityCenter.CountdownTimer
    var toggle: () -> Void
    var cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(symbol: "timer", tint: .orange)
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                Text(TimeFormat.clock(timer.remaining(at: ctx.date).rounded(.up)))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText(countsDown: true))
            }
            Spacer()
            RoundButton(symbol: "xmark", tint: .white.opacity(0.7), action: cancel)
            RoundButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", tint: .orange, action: toggle)
        }
        .frame(height: 36)
    }
}

private struct StopwatchRow: View {
    let stopwatch: ActivityCenter.Stopwatch
    var toggle: () -> Void
    var reset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(symbol: "stopwatch", tint: .orange)
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let t = stopwatch.elapsed(at: ctx.date)
                Text(TimeFormat.clock(t) + String(format: ".%d", Int(t * 10) % 10))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer()
            RoundButton(symbol: "arrow.counterclockwise", tint: .white.opacity(0.7), action: reset)
            RoundButton(symbol: stopwatch.isRunning ? "pause.fill" : "play.fill", tint: .orange, action: toggle)
        }
        .frame(height: 36)
    }
}

private struct MeetingRow: View {
    let meeting: ActivityCenter.Meeting

    var body: some View {
        let tint = meeting.color.map(Color.init(nsColor:)) ?? .blue
        HStack(spacing: 10) {
            RowIcon(symbol: "calendar", tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = meeting.start.timeIntervalSince(ctx.date)
                    Text(left <= 0 ? "Now · until \(meeting.end.formatted(date: .omitted, time: .shortened))"
                                   : "In \(TimeFormat.clock(left)) · \(meeting.start.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            if let url = meeting.joinURL { JoinButton(url: url) }
        }
        .frame(height: 36)
    }
}
