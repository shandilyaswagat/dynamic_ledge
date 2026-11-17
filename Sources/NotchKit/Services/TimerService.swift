import AppKit
import Observation

@MainActor
@Observable
public final class TimerService {
    public private(set) var timer: CountdownTimer? { didSet { saveActiveTimer() } }
    /// Duration of the last timer started, used by "Repeat".
    public private(set) var lastDuration: TimeInterval?

    /// Quick starts shown in the pill.
    public static let presets: [TimeInterval] = [300, 600, 900, 1800]
    /// Quick starts shown in the menu bar menu, which has more room.
    public static let menuPresets: [TimeInterval] = [60, 180, 300, 600, 900, 1800, 3600]

    /// Called once when a running timer reaches zero.
    @ObservationIgnored public var onFinish: (() -> Void)?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    private static let timerKey = "timer.active"
    private static let focusCountKey = "timer.completedFocusInCycle"
    private static let focusCycleLength = 4
    private var completedFocusInCycle = 0

    public init(defaults: UserDefaults? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        let count = defaults?.integer(forKey: Self.focusCountKey) ?? 0
        if (0..<Self.focusCycleLength).contains(count) { completedFocusInCycle = count }
        if let data = defaults?.data(forKey: Self.timerKey),
           let saved = try? JSONDecoder().decode(CountdownTimer.self, from: data),
           saved.canRestore(at: now()) {
            timer = saved
            if saved.mode == .plain { lastDuration = saved.duration }
            scheduleCompletion()
        } else {
            defaults?.removeObject(forKey: Self.timerKey)
        }
        // A timer that ran out while the Mac slept should ring as soon as it wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCompletion() }
        }
    }

    /// Running or paused; a finished timer is shown by its alert instead.
    public var isActive: Bool {
        guard let timer else { return false }
        return !timer.isFinished
    }

    var shouldOfferLongBreak: Bool {
        timer?.mode == .focus && timer?.isFinished == true && completedFocusInCycle == 0
    }

    /// Focus sessions and breaks are started on their own and never become "Repeat".
    public func start(duration: TimeInterval, mode: TimerMode = .plain) {
        let started = CountdownTimer(duration: duration, now: now(), mode: mode)
        timer = started
        if mode == .plain {
            lastDuration = started.duration
        }
        scheduleCompletion()
    }

    public func pause() {
        timer?.pause(now: now())
        scheduleCompletion()
    }

    public func resume() {
        timer?.resume(now: now())
        scheduleCompletion()
    }

    public func togglePause() {
        guard let timer else { return }
        if timer.isPaused { resume() } else { pause() }
    }

    public func add(_ seconds: TimeInterval) {
        timer?.add(seconds, now: now())
        scheduleCompletion()
    }

    public func cancel() {
        timer = nil
        scheduleCompletion()
    }

    public func repeatLast() {
        guard let lastDuration else { return }
        start(duration: lastDuration)
    }

    /// Checks the clock; called by the scheduled task and safe to call at any time.
    public func checkCompletion() {
        guard var current = timer, current.finishIfDue(now: now()) else { return }
        if current.mode == .focus {
            completedFocusInCycle = (completedFocusInCycle + 1) % Self.focusCycleLength
            defaults?.set(completedFocusInCycle, forKey: Self.focusCountKey)
        }
        timer = current
        scheduleCompletion()
        onFinish?()
    }

    private func saveActiveTimer() {
        guard let defaults else { return }
        if let timer, !timer.isFinished, let data = try? JSONEncoder().encode(timer) {
            defaults.set(data, forKey: Self.timerKey)
        } else {
            defaults.removeObject(forKey: Self.timerKey)
        }
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        completionTask = nil
        guard let timer, timer.isRunning else {
            endActivity()
            return
        }
        beginActivity()
        let delay = timer.remaining(at: now())
        completionTask = Task { [weak self] in
            // A tight tolerance: by default the system may fire long sleeps many seconds late.
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(20))
            guard !Task.isCancelled else { return }
            self?.checkCompletion()
        }
    }

    /// Keeps App Nap from delaying the alarm.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Timer running"
        )
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }
}

/// Plays the timer-done sound a few times, like the Clock app.
@MainActor
final class AlarmSound {
    private var task: Task<Void, Never>?
    private var sound: NSSound?

    func start() {
        stop()
        task = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled, Date().timeIntervalSince(started) < 30 {
                self?.playOnce()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        sound?.stop()
        sound = nil
    }

    private func playOnce() {
        sound?.stop()
        sound = NSSound(named: NSSound.Name("Glass"))
        sound?.play()
    }
}

enum Haptics {
    @MainActor
    static func perform(enabled: Bool) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
