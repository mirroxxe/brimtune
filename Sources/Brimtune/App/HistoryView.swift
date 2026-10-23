import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Songs you play will show up here")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.entries) { entry in
                                HistoryRow(entry: entry, image: history.thumbnail(for: entry)) { history.open(entry) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 380, minHeight: 460)
        .toolbar {
            ToolbarItem {
                Button("Clear", systemImage: "trash") { history.clear() }
                    .disabled(history.entries.isEmpty)
            }
        }
    }

    private var sections: [(title: String, entries: [HistoryStore.Entry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.entries) { calendar.startOfDay(for: $0.playedAt) }
        return grouped.keys.sorted(by: >).map { day in
            let title = calendar.isDateInToday(day) ? "Today"
                : calendar.isDateInYesterday(day) ? "Yesterday"
                : day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            return (title, grouped[day] ?? [])
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryStore.Entry
    let image: NSImage?
    var open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(image: image, cornerRadius: 6)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 13, weight: .semibold))
                Text(entry.artist.isEmpty ? entry.source : "\(entry.artist) · \(entry.source)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            if hovering {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                Text(entry.playedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { over in withAnimation(.smooth(duration: 0.15)) { hovering = over } }
        .onTapGesture(perform: open)
        .help("Open in \(entry.source)")
    }
}
