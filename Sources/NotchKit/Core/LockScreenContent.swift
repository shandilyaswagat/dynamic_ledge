import Foundation

/// What the Lock Screen shows: one thing at a time, the most time-sensitive first, like the
/// iPhone's Lock Screen live activities.
public enum LockScreenContent: Equatable, Sendable {
    case timer
    case music
    case stopwatch
    case charging(level: Int, isCharging: Bool)

    public static func choose(timer: Bool, music: Bool, stopwatch: Bool, power: PowerSnapshot?) -> LockScreenContent? {
        if timer { return .timer }
        if music { return .music }
        if stopwatch { return .stopwatch }
        if let power, power.hasBattery, power.isOnAC {
            return .charging(level: power.level, isCharging: power.isCharging)
        }
        return nil
    }

    /// Drawn exactly like the notch when unlocked: the compact activity beside the camera, or
    /// the charging alert.
    public var presentation: IslandPresentation {
        switch self {
        case .timer: .compact(primary: .timer, secondary: nil)
        case .music: .compact(primary: .nowPlaying, secondary: nil)
        case .stopwatch: .compact(primary: .stopwatch, secondary: nil)
        case .charging(let level, let isCharging): .alert(.charging(level: level, isCharging: isCharging))
        }
    }
}
