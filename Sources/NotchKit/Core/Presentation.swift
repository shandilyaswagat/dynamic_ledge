import Foundation

/// A live activity that can sit in the pill. Order of cases is not meaningful; use `priority`.
public enum ActivityKind: String, CaseIterable, Sendable, Codable, Hashable {
    case call
    case timer
    case stopwatch
    case nowPlaying
    /// Memory and CPU, when Stats is on and nothing else is happening. Never shares the notch:
    /// any other activity replaces it.
    case stats

    /// Lower comes first.
    public var priority: Int {
        switch self {
        case .call: 0
        case .timer: 1
        case .stopwatch: 2
        case .nowPlaying: 3
        case .stats: 4
        }
    }
}

/// A short system event, shown briefly like the iPhone's charging or AirPods alerts.
public enum IslandAlert: Equatable, Sendable {
    case charging(level: Int, isCharging: Bool)
    case lowBattery(level: Int)
    case headphones(name: String, symbol: String)
    case timerFinished
    /// Shown once on first launch, so a new user sees where the app lives.
    case welcome
    /// Volume or brightness changed. `value` is 0…1.
    case level(LevelKind, value: Double, muted: Bool)
    /// A calendar event is about to start.
    case upcomingEvent(title: String, minutes: Int)
    /// A shortcut run from the notch finished.
    case shortcut(name: String, succeeded: Bool)
    /// A file finished downloading into Downloads.
    case download(URL)
    /// A new version of the app is out.
    case updateAvailable(version: String)

    public enum LevelKind: String, Sendable, Hashable {
        case volume
        case brightness
    }

    /// Alerts of the same kind replace each other instead of queueing.
    public enum Kind: Hashable, Sendable {
        case power
        case headphones
        case timer
        case app
        case level
        case calendar
        case shortcut
        case download
        case update
    }

    public var kind: Kind {
        switch self {
        case .charging, .lowBattery: .power
        case .headphones: .headphones
        case .timerFinished: .timer
        case .welcome: .app
        case .level: .level
        case .upcomingEvent: .calendar
        case .shortcut: .shortcut
        case .download: .download
        case .updateAvailable: .update
        }
    }

    /// How long the alert stays. "Timer done" waits for the user, but clears itself after
    /// ten minutes so an unattended Mac isn't left with the notch expanded.
    public var displayDuration: TimeInterval {
        switch self {
        case .charging: 3
        case .lowBattery: 4
        case .headphones: 3
        case .timerFinished: 600
        case .welcome: 4
        case .level: 1.6
        case .upcomingEvent: 8
        case .shortcut: 2.5
        case .download: 5
        case .updateAvailable: 6
        }
    }

    /// Urgent alerts interrupt an expanded view; the rest wait for it to close.
    public var isUrgent: Bool {
        self == .timerFinished
    }

    /// Feedback for something the user just did (volume keys): shown at once, never queued
    /// behind other alerts, and dropped rather than replayed if something urgent takes over.
    public var isInstant: Bool {
        if case .level = self { return true }
        return false
    }
}

/// The views that share the Home nook: the tabs (Home, Tray, Clipboard), the launcher grid, and
/// the views opened from it or from Home's widgets, which show a back button instead of the tabs.
public enum HomeTab: String, CaseIterable, Sendable, Codable, Hashable {
    case home
    case tray
    case clipboard
    case notes
    case mirror
    case timers
    case calendar
    case reminders
    /// Memory, CPU, disk and network.
    case stats
    /// The grid of everything the notch can do. Its Edit button picks the shortcuts beside Home.
    case launcher

    /// Shown in the tab bar beside the camera.
    public var isTab: Bool {
        self == .home || self == .tray || self == .clipboard
    }

    /// Shows a back button and its name in place of the tab bar.
    public var isPanel: Bool {
        !isTab && self != .launcher
    }
}

public enum ExpandTarget: Equatable, Sendable {
    case activity(ActivityKind)
    case nook(HomeTab)

    public init(_ tab: HomeTab) {
        self = .nook(tab)
    }

    public static let home = ExpandTarget.nook(.home)
    public static let tray = ExpandTarget.nook(.tray)
    public static let clipboard = ExpandTarget.nook(.clipboard)
    public static let notes = ExpandTarget.nook(.notes)
    public static let mirror = ExpandTarget.nook(.mirror)
}

/// Everything the pill can look like at a given moment.
public enum IslandPresentation: Equatable, Sendable {
    /// Retracted into the notch (or gone). `peek` shows a small droplet while the notch is hovered.
    case hidden(peek: Bool)
    /// An empty pill, shown when "show when idle" is on or the appearance settings are open.
    case idle
    case compact(primary: ActivityKind, secondary: ActivityKind?)
    case expanded(ActivityKind)
    /// Home, its tabs (Tray, Clipboard, Notes, Mirror) and its panels, in one fixed-size nook.
    case nook(HomeTab)
    case alert(IslandAlert)
    case drop(targeted: Bool)

    public static let home = IslandPresentation.nook(.home)
    public static let tray = IslandPresentation.nook(.tray)
    public static let clipboard = IslandPresentation.nook(.clipboard)
    public static let notes = IslandPresentation.nook(.notes)
    public static let mirror = IslandPresentation.nook(.mirror)

    public var isExpandedFamily: Bool {
        switch self {
        case .expanded, .nook, .alert, .drop: true
        case .hidden, .idle, .compact: false
        }
    }

    /// Which Home tab this is, if it is one.
    public var homeTab: HomeTab? {
        if case .nook(let tab) = self { return tab }
        return nil
    }

    public var isHidden: Bool {
        if case .hidden = self { return true }
        return false
    }

    public var isVisible: Bool {
        if case .hidden = self { return false }
        return true
    }

    /// The idle or compact pill: small, clickable, and lifts slightly on hover.
    public var isRestingPill: Bool {
        switch self {
        case .idle, .compact: true
        default: false
        }
    }

    /// Changes in this value are shape changes worth a liquid pulse (appear, disappear, split).
    public var topology: Topology {
        switch self {
        case .hidden(let peek): Topology(visible: false, peek: peek, split: false)
        case .compact(_, let secondary): Topology(visible: true, peek: false, split: secondary != nil)
        default: Topology(visible: true, peek: false, split: false)
        }
    }

    public struct Topology: Hashable, Sendable {
        public var visible: Bool
        public var peek: Bool
        public var split: Bool
    }
}

public struct PresentationInput: Equatable, Sendable {
    public var activeActivities: Set<ActivityKind>
    public var preferredPrimary: ActivityKind?
    public var alert: IslandAlert?
    public var expandTarget: ExpandTarget?
    public var isFileDragNear: Bool
    public var isDropTargeted: Bool
    public var showWhenIdle: Bool
    public var isHoveringNotch: Bool
    public var isPreviewing: Bool

    public init(
        activeActivities: Set<ActivityKind> = [],
        preferredPrimary: ActivityKind? = nil,
        alert: IslandAlert? = nil,
        expandTarget: ExpandTarget? = nil,
        isFileDragNear: Bool = false,
        isDropTargeted: Bool = false,
        showWhenIdle: Bool = false,
        isHoveringNotch: Bool = false,
        isPreviewing: Bool = false
    ) {
        self.activeActivities = activeActivities
        self.preferredPrimary = preferredPrimary
        self.alert = alert
        self.expandTarget = expandTarget
        self.isFileDragNear = isFileDragNear
        self.isDropTargeted = isDropTargeted
        self.showWhenIdle = showWhenIdle
        self.isHoveringNotch = isHoveringNotch
        self.isPreviewing = isPreviewing
    }
}

public enum PresentationResolver {
    /// Activities in display order: the user's swipe choice first, then by priority.
    public static func ordered(_ active: Set<ActivityKind>, preferred: ActivityKind?) -> [ActivityKind] {
        let byPriority = active.sorted { $0.priority < $1.priority }
        guard let preferred, active.contains(preferred) else { return byPriority }
        return [preferred] + byPriority.filter { $0 != preferred }
    }

    /// The activity a swipe brings to the front. Steps through the priority order and wraps,
    /// so repeated swipes visit every activity.
    public static func nextPrimary(_ active: Set<ActivityKind>, current: ActivityKind?, forward: Bool) -> ActivityKind? {
        let byPriority = active.sorted { $0.priority < $1.priority }
        guard byPriority.count > 1 else { return nil }
        let index = current.flatMap { byPriority.firstIndex(of: $0) } ?? 0
        let step = forward ? 1 : byPriority.count - 1
        return byPriority[(index + step) % byPriority.count]
    }

    /// Drag beats alerts, alerts beat the expanded view, then activities by priority, then idle.
    public static func resolve(_ input: PresentationInput) -> IslandPresentation {
        if input.isFileDragNear || input.isDropTargeted {
            return .drop(targeted: input.isDropTargeted)
        }
        if let alert = input.alert {
            return .alert(alert)
        }
        switch input.expandTarget {
        case .nook(let tab):
            return .nook(tab)
        case .activity(let kind) where input.activeActivities.contains(kind):
            return .expanded(kind)
        default:
            break
        }
        let ordered = ordered(input.activeActivities, preferred: input.preferredPrimary)
        if let primary = ordered.first {
            return .compact(primary: primary, secondary: ordered.dropFirst().first)
        }
        if input.showWhenIdle || input.isPreviewing {
            return .idle
        }
        return .hidden(peek: input.isHoveringNotch)
    }
}
