import AppKit
import Combine
import EventKit

/// Live Activities for the island: a countdown timer, a stopwatch and the next
/// calendar meeting.
@MainActor
final class ActivityCenter: ObservableObject {
    struct CountdownTimer: Equatable {
        var duration: TimeInterval
        /// Set while running.
        var endsAt: Date?
        /// Set while paused.
        var remainingWhenPaused: TimeInterval?

        func remaining(at date: Date) -> TimeInterval {
            if let endsAt { return max(0, endsAt.timeIntervalSince(date)) }
            return remainingWhenPaused ?? duration
        }

        var isRunning: Bool { endsAt != nil }
    }

    struct Stopwatch: Equatable {
        var startedAt: Date?
        var accumulated: TimeInterval = 0

        func elapsed(at date: Date) -> TimeInterval {
            accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
        }

        var isRunning: Bool { startedAt != nil }
    }

    struct Meeting: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: NSColor?
        let joinURL: URL?
    }

    enum Alert: Equatable {
        case timerDone
        case meeting(Meeting, startingNow: Bool)
    }

    @Published private(set) var timer: CountdownTimer?
    @Published private(set) var stopwatch: Stopwatch?
    /// The next meeting, once it is within the heads-up window.
    @Published private(set) var meeting: Meeting?

    let alerts = PassthroughSubject<Alert, Never>()

    static let meetingLead: TimeInterval = 5 * 60

    private let preferences: Preferences
    private let store = EKEventStore()
    private var timerWork: DispatchWorkItem?
    private var calendarTimer: Timer?
    private var startWork: DispatchWorkItem?
    private var announced: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []

    init(preferences: Preferences) {
        self.preferences = preferences
        preferences.$calendarEnabled.removeDuplicates().sink { [weak self] enabled in
            self?.setCalendar(enabled)
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCalendar() }
        }
    }

    /// Anything worth showing in the compact island.
    var hasLiveActivity: Bool { timer != nil || stopwatch != nil || meeting != nil }

    // MARK: Timer

    func startTimer(minutes: Double) {
        let duration = minutes * 60
        timer = CountdownTimer(duration: duration, endsAt: Date().addingTimeInterval(duration))
        scheduleTimerEnd()
    }

    func toggleTimer() {
        guard var t = timer else { return }
        if let endsAt = t.endsAt {
            t.remainingWhenPaused = max(0, endsAt.timeIntervalSinceNow)
            t.endsAt = nil
        } else {
            t.endsAt = Date().addingTimeInterval(t.remainingWhenPaused ?? t.duration)
            t.remainingWhenPaused = nil
        }
        timer = t
        scheduleTimerEnd()
    }

    func cancelTimer() {
        timerWork?.cancel()
        timer = nil
    }

    private func scheduleTimerEnd() {
        timerWork?.cancel()
        guard let endsAt = timer?.endsAt else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timer = nil
            NSSound(named: "Glass")?.play()
            self.alerts.send(.timerDone)
        }
        timerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, endsAt.timeIntervalSinceNow), execute: work)
    }

    // MARK: Stopwatch

    func startStopwatch() {
        stopwatch = Stopwatch(startedAt: Date())
    }

    func toggleStopwatch() {
        guard var s = stopwatch else { return startStopwatch() }
        if let started = s.startedAt {
            s.accumulated += Date().timeIntervalSince(started)
            s.startedAt = nil
        } else {
            s.startedAt = Date()
        }
        stopwatch = s
    }

    func resetStopwatch() {
        stopwatch = nil
    }

    // MARK: Calendar

    private func setCalendar(_ enabled: Bool) {
        calendarTimer?.invalidate()
        meeting = nil
        guard enabled else { return }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshCalendar()
                self.calendarTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshCalendar() }
                }
                self.calendarTimer?.tolerance = 5
            }
        }
    }

    private func refreshCalendar() {
        guard preferences.calendarEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: now.addingTimeInterval(3600), calendars: nil)
        let next = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.startDate > now.addingTimeInterval(-90) }
            .sorted { $0.startDate < $1.startDate }
            .first

        guard let event = next, event.startDate.timeIntervalSince(now) <= Self.meetingLead else {
            if meeting != nil { meeting = nil }
            return
        }
        let info = Meeting(
            id: event.eventIdentifier ?? event.title,
            title: event.title ?? "Meeting",
            start: event.startDate, end: event.endDate,
            color: event.calendar?.color,
            joinURL: Self.joinLink(in: event)
        )
        if meeting != info { meeting = info }

        let startingNow = event.startDate <= now
        let key = info.id + (startingNow ? "now" : "soon")
        if !announced.contains(key) {
            announced.insert(key)
            alerts.send(.meeting(info, startingNow: startingNow))
        }
        // Wake up right at the start so the "now" alert isn't late (one pending wake-up, not one per refresh).
        startWork?.cancel()
        if !startingNow {
            let work = DispatchWorkItem { [weak self] in self?.refreshCalendar() }
            startWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + event.startDate.timeIntervalSinceNow + 0.5, execute: work)
        }
    }

    /// A Zoom / Meet / Teams / Webex link from the event's URL, location or notes.
    private static func joinLink(in event: EKEvent) -> URL? {
        if let url = event.url, isMeetingURL(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let links = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url) ?? []
        return links.first(where: isMeetingURL)
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]
            .contains { host.hasSuffix($0) }
    }
}
