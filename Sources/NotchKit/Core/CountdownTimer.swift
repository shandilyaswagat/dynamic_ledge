import Foundation

/// What a timer is for. Focus sessions and their breaks are timers that offer the next step
/// when they end.
public enum TimerMode: String, Codable, Equatable, Sendable {
    case plain
    case focus
    case rest

    /// The step offered when this one ends.
    public var next: TimerMode? {
        switch self {
        case .plain: nil
        case .focus: .rest
        case .rest: .focus
        }
    }
}

/// The pill's own timer. A value type with an injected clock so it can be
/// tested without waiting.
public struct CountdownTimer: Codable, Equatable, Sendable {
    public enum Phase: Codable, Equatable, Sendable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    public private(set) var duration: TimeInterval
    public private(set) var phase: Phase
    public let mode: TimerMode

    public static let minimumDuration: TimeInterval = 1
    public static let maximumDuration: TimeInterval = 24 * 3600

    public init(duration: TimeInterval, now: Date, mode: TimerMode = .plain) {
        let clamped = min(max(duration, Self.minimumDuration), Self.maximumDuration)
        self.duration = clamped
        self.mode = mode
        self.phase = .running(endDate: now.addingTimeInterval(clamped))
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): remaining
        case .finished: 0
        }
    }

    /// 0 at the start, 1 when done.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(1 - remaining(at: now) / duration, 0), 1)
    }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    public var isFinished: Bool { phase == .finished }

    func canRestore(at now: Date) -> Bool {
        if isFinished || !(Self.minimumDuration...Self.maximumDuration).contains(duration) { return false }
        return (0...Self.maximumDuration).contains(remaining(at: now))
    }

    public var endDate: Date? {
        if case .running(let endDate) = phase { return endDate }
        return nil
    }

    public mutating func pause(now: Date) {
        guard case .running = phase else { return }
        phase = .paused(remaining: remaining(at: now))
    }

    public mutating func resume(now: Date) {
        guard case .paused(let remaining) = phase else { return }
        phase = .running(endDate: now.addingTimeInterval(remaining))
    }

    /// Adds time to a running or paused timer, e.g. "+1 min".
    public mutating func add(_ seconds: TimeInterval, now: Date) {
        switch phase {
        case .running(let endDate):
            let newRemaining = min(endDate.timeIntervalSince(now) + seconds, Self.maximumDuration)
            phase = .running(endDate: now.addingTimeInterval(max(newRemaining, 0)))
            duration = min(duration + seconds, Self.maximumDuration)
        case .paused(let remaining):
            phase = .paused(remaining: min(max(remaining + seconds, 0), Self.maximumDuration))
            duration = min(duration + seconds, Self.maximumDuration)
        case .finished:
            break
        }
    }

    /// Moves a running timer to `.finished` once its end date has passed.
    @discardableResult
    public mutating func finishIfDue(now: Date) -> Bool {
        guard case .running(let endDate) = phase, now >= endDate else { return false }
        phase = .finished
        return true
    }
}
