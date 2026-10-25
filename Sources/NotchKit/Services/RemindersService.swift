import AppKit
import EventKit
import Observation

/// A to-do from the Reminders app, copied out of EventKit.
public struct ReminderItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var due: Date?
    public var color: ColorMath.RGB

    public init(id: String, title: String, due: Date?, color: ColorMath.RGB = .white) {
        self.id = id
        self.title = title
        self.due = due
        self.color = color
    }
}

public enum ReminderRules {
    /// Overdue ones first, then by due time.
    public static func sorted(_ items: [ReminderItem]) -> [ReminderItem] {
        items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    /// "Overdue", a time for today ("3:00 PM"), or nothing when there's no due time.
    public static func label(for item: ReminderItem, at now: Date, calendar: Calendar = .current) -> String? {
        guard let due = item.due else { return nil }
        if due < now, !calendar.isDate(due, inSameDayAs: now) { return String(localized: "Overdue") }
        let components = calendar.dateComponents([.hour, .minute], from: due)
        // All-day reminders come back at midnight; they have no time to show.
        if components.hour == 0, components.minute == 0 { return String(localized: "Today") }
        return due.formatted(date: .omitted, time: .shortened)
    }
}

/// Today's to-dos from Reminders: anything not done that's due by the end of today. Asks for
/// access only when the user clicks Connect.
@MainActor
@Observable
public final class RemindersService {
    public enum Access: Equatable, Sendable {
        case notAsked
        case granted
        case denied
    }

    public private(set) var access: Access = .notAsked
    public private(set) var items: [ReminderItem] = []

    @ObservationIgnored private var store = EKEventStore()
    /// See CalendarService: macOS can report "not asked yet" for a while after the user allows it.
    @ObservationIgnored private var grantedThisSession = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var isRunning = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        access = currentAccess()
        // Any store, because the store is replaced once access is granted.
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    public func stop() {
        isRunning = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    public func requestAccess() {
        // Come forward so the permission dialog appears (see CalendarService.requestAccess).
        NSApp.activate()
        Task { [weak self] in
            guard let self else { return }
            let granted = (try? await self.store.requestFullAccessToReminders()) ?? false
            if granted {
                self.grantedThisSession = true
                self.store = EKEventStore()
            }
            if !granted, self.currentAccess() != .notAsked { self.openPrivacySettings() }
            self.reload()
        }
    }

    /// Ticks a to-do off in Reminders.
    public func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            items.removeAll { $0.id == item.id }
        } catch {
            reload()
        }
    }

    public func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reload() {
        access = currentAccess()
        guard isRunning, access == .granted else {
            items = []
            return
        }
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            let fresh = (reminders ?? []).map { reminder in
                ReminderItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title?.isEmpty == false ? reminder.title! : String(localized: "Reminder"),
                    due: reminder.dueDateComponents?.date,
                    color: Self.rgb(reminder.calendar?.color)
                )
            }
            Task { @MainActor [weak self] in
                let sorted = ReminderRules.sorted(fresh)
                if self?.items != sorted { self?.items = sorted }
            }
        }
    }

    private func currentAccess() -> Access {
        Self.access(for: EKEventStore.authorizationStatus(for: .reminder), grantedThisSession: grantedThisSession)
    }

    nonisolated static func access(for status: EKAuthorizationStatus, grantedThisSession: Bool) -> Access {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: grantedThisSession ? .granted : .notAsked
        default: .denied
        }
    }

    nonisolated private static func rgb(_ color: NSColor?) -> ColorMath.RGB {
        guard let color = color?.usingColorSpace(.sRGB) else { return .white }
        return ColorMath.RGB(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }
}
