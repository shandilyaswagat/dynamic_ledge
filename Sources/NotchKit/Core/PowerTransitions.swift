import Foundation

public struct PowerSnapshot: Equatable, Sendable {
    public var hasBattery: Bool
    /// 0–100.
    public var level: Int
    public var isOnAC: Bool
    public var isCharging: Bool
    public var isLowPowerMode: Bool
    /// Minutes to full when charging, or to empty when running on battery.
    public var estimatedMinutes: Int?

    public init(hasBattery: Bool, level: Int, isOnAC: Bool, isCharging: Bool, isLowPowerMode: Bool,
                estimatedMinutes: Int? = nil) {
        self.hasBattery = hasBattery
        self.level = min(max(level, 0), 100)
        self.isOnAC = isOnAC
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
        self.estimatedMinutes = estimatedMinutes
    }
}

/// Decides which battery alert, if any, a change in power state deserves.
public enum PowerTransitions {
    public static let lowBatteryThresholds = [20, 10]

    public static func alert(from old: PowerSnapshot?, to new: PowerSnapshot) -> IslandAlert? {
        // Never alert on launch, and never on Macs without a battery.
        guard let old, new.hasBattery else { return nil }

        if !old.isOnAC && new.isOnAC {
            return .charging(level: new.level, isCharging: new.isCharging)
        }
        if old.hasBattery, new.isOnAC, old.level < 100, new.level == 100 {
            return .batteryFull
        }

        guard !new.isOnAC, new.level < old.level else { return nil }
        let crossed = lowBatteryThresholds.filter { old.level > $0 && new.level <= $0 }
        if crossed.isEmpty { return nil }
        return .lowBattery(level: new.level)
    }
}
