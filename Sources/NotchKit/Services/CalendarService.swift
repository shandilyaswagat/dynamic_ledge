import AppKit
import EventKit
import Observation

/// A calendar event, copied out of EventKit so views and tests don't touch EKEvent.
public struct CalendarEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var color: ColorMath.RGB
    public var isAllDay: Bool
    /// A Meet, Zoom, Teams or Webex link found in the event, for the Join button.
    public var joinURL: URL?
    public var joinProvider: MeetingLinks.Provider?

    public init(id: String, title: String, start: Date, end: Date, color: ColorMath.RGB = .white, isAllDay: Bool = false,
                joinURL: URL? = nil, joinProvider: MeetingLinks.Provider? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.color = color
        self.isAllDay = isAllDay
        self.joinURL = joinURL
        self.joinProvider = joinProvider
    }

    public func isHappening(at date: Date) -> Bool {
        start <= date && date < end
    }
}

/// Pure rules for which event to show and when to warn about it.
public enum CalendarRules {
    /// How long before an event starts the notch gives a heads-up.
    public static let reminderLead: TimeInterval = 5 * 60

    /// The event happening now, or else the next one to start.
    public static func nextEvent(in events: [CalendarEvent], at date: Date) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && $0.end > date }
            .sorted { $0.start < $1.start }
            .first
    }

    /// The next moment a heads-up is due, and for which event. Skips events already reminded.
    public static func nextReminder(in events: [CalendarEvent], after date: Date, reminded: Set<String>)
        -> (event: CalendarEvent, at: Date)? {
        events
            .filter { !$0.isAllDay && !reminded.contains($0.id) && $0.start > date }
            .map { (event: $0, at: max(date, $0.start.addingTimeInterval(-reminderLead))) }
            .min { $0.at < $1.at }
    }

    /// "now", "in 12 min", "in 1 hr", a clock time for later today, or the day and time after that.
    public static func relativeLabel(for event: CalendarEvent, at date: Date, calendar: Calendar = .current) -> String {
        if event.isHappening(at: date) { return String(localized: "now") }
        let minutes = Int((event.start.timeIntervalSince(date) / 60).rounded(.up))
        if minutes < 60 { return String(localized: "in \(max(minutes, 1)) min") }
        if minutes < 120 { return String(localized: "in 1 hr") }
        let time = event.start.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(event.start, inSameDayAs: date) { return time }
        return dayLabel(for: event, at: date, calendar: calendar) + " " + time
    }
}

/// Reads the user's calendars (only after they allow it) for the Home tab and event heads-ups.
@MainActor
@Observable
public final class CalendarService {
    public enum Access: Equatable, Sendable {
        case notAsked
        case granted
        case denied
        /// "Add Events Only": the app could create events but can't read them.
        case limited
    }

    public private(set) var access: Access = .notAsked
    public private(set) var events: [CalendarEvent] = []

    /// Called when an event is about to start.
    @ObservationIgnored public var onReminder: ((CalendarEvent) -> Void)?

    @ObservationIgnored private var store = EKEventStore()
    /// The user said yes in this session. Right after that, macOS can keep reporting "not asked
    /// yet" for a while; without this the panel fell back to Connect after the user allowed it.
    @ObservationIgnored private var grantedThisSession = false
    @ObservationIgnored private var reminded = Set<String>()
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isRunning = false

    public init() {
        access = currentAccess()
    }

    public var nextEvent: CalendarEvent? {
        CalendarRules.nextEvent(in: events, at: Date())
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        access = currentAccess()
        // Any store, because the store is replaced once access is granted.
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        reload()
    }

    public func stop() {
        isRunning = false
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        reminderTask?.cancel()
        refreshTask?.cancel()
    }

    /// Asks for calendar access. Only ever called from a button the user pressed.
    /// Called once access is granted, so the notch can show the result right away.
    @ObservationIgnored public var onGranted: (() -> Void)?

    public func requestAccess() {
        // The notch never brings the app forward, and macOS may not show a permission dialog for
        // an app in the background. Come forward first so the dialog appears on top.
        NSApp.activate()
        Task { [weak self] in
            guard let self else { return }
            let granted = (try? await self.store.requestFullAccessToEvents()) ?? false
            // No dialog was shown (macOS remembered an earlier answer): send the user to the switch.
            if !granted, self.currentAccess() != .notAsked { self.openPrivacySettings() }
            if granted {
                self.grantedThisSession = true
                // A store made before access was granted keeps returning nothing, so start fresh.
                self.store = EKEventStore()
            }
            self.reload()
            if granted { self.onGranted?() }
        }
    }

    /// Opens the Calendar app on the day of the event.
    public func open(_ event: CalendarEvent) {
        if let url = URL(string: "calshow:\(event.start.timeIntervalSinceReferenceDate)") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Picks up a change made in System Settings while the app was running.
    public func refreshAccess() {
        let now = currentAccess()
        guard now != access else { return }
        if now == .granted { store = EKEventStore() }
        reload()
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func currentAccess() -> Access {
        Self.access(for: EKEventStore.authorizationStatus(for: .event), grantedThisSession: grantedThisSession)
    }

    nonisolated static func access(for status: EKAuthorizationStatus, grantedThisSession: Bool) -> Access {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: grantedThisSession ? .granted : .notAsked
        case .writeOnly: .limited
        default: .denied
        }
    }

    private func reload() {
        access = currentAccess()
        guard isRunning, access == .granted else {
            events = []
            scheduleReminder()
            return
        }
        let now = Date()
        // The coming week, so the Calendar panel has something to show on a quiet day.
        let start = Calendar.current.startOfDay(for: now)
        let predicate = store.predicateForEvents(withStart: start, end: start.addingTimeInterval(8 * 24 * 3600), calendars: nil)
        let fresh = store.events(matching: predicate)
            .filter { $0.status != .canceled && !Self.isDeclined($0) }
            .map { event in
                let join = MeetingLinks.joinLink(in: [event.url?.absoluteString, event.location, event.notes])
                return CalendarEvent(
                    id: (event.calendarItemIdentifier) + "@" + String(event.startDate.timeIntervalSince1970),
                    title: event.title?.isEmpty == false ? event.title! : String(localized: "Event"),
                    start: event.startDate,
                    end: event.endDate,
                    color: Self.rgb(event.calendar?.color),
                    isAllDay: event.isAllDay,
                    joinURL: join?.url,
                    joinProvider: join?.provider
                )
            }
            .sorted { $0.start < $1.start }
        if fresh != events {
            events = fresh
        }
        scheduleReminder()
        scheduleRefresh()
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func rgb(_ color: NSColor?) -> ColorMath.RGB {
        guard let color = color?.usingColorSpace(.sRGB) else { return .white }
        return ColorMath.RGB(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    private func scheduleReminder() {
        reminderTask?.cancel()
        reminderTask = nil
        guard let next = CalendarRules.nextReminder(in: events, after: Date(), reminded: reminded) else { return }
        let delay = max(0, next.at.timeIntervalSinceNow)
        reminderTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.reminded.insert(next.event.id)
            self.onReminder?(next.event)
            self.scheduleReminder()
        }
    }

    /// The "in 12 min" label and the next event roll over as time passes.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

extension CalendarRules {
    /// What's on now and coming up, soonest first; all-day events lead their day.
    public static func upcoming(in events: [CalendarEvent], at date: Date, limit: Int) -> [CalendarEvent] {
        let calendar = Calendar.current
        return Array(
            events
                .filter { $0.end > date }
                .sorted {
                    let dayA = calendar.startOfDay(for: max($0.start, date))
                    let dayB = calendar.startOfDay(for: max($1.start, date))
                    if dayA != dayB { return dayA < dayB }
                    if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                    return $0.start < $1.start
                }
                .prefix(limit)
        )
    }

    /// "10:30 – 11:00 AM", "Now · until 11:00 AM" or "All day".
    public static func timeRange(for event: CalendarEvent, at date: Date) -> String {
        if event.isAllDay { return String(localized: "All day") }
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if event.isHappening(at: date) { return String(localized: "Now · until \(end)") }
        return event.start.formatted(date: .omitted, time: .shortened) + " – " + end
    }

    /// "Today", "Tomorrow", or the weekday and date for later in the week.
    public static func dayLabel(for event: CalendarEvent, at date: Date, calendar: Calendar = .current) -> String {
        let day = max(event.start, date)
        if calendar.isDate(day, inSameDayAs: date) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date), calendar.isDate(day, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// The days of one month laid out in weeks, starting on the user's first weekday.
public struct MonthLayout: Equatable {
    /// Day numbers in grid order; nil pads the first week.
    public var cells: [Int?]
    public var today: Int
    public var weekdaySymbols: [String]

    public init(containing date: Date, calendar: Calendar = .current) {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let weekday = calendar.component(.weekday, from: start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        cells = Array(repeating: nil, count: lead) + (1...days).map { Optional($0) }
        today = calendar.component(.day, from: date)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        weekdaySymbols = Array(symbols[first...] + symbols[..<first])
    }
}
