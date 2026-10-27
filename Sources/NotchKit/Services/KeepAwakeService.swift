import Foundation
import IOKit.pwr_mgt
import Observation

/// Stops the Mac from going to sleep, for a while or until turned off. A power assertion, the
/// same thing `caffeinate` uses; it ends on its own when the app quits.
@MainActor
@Observable
public final class KeepAwakeService {
    public private(set) var isOn = false
    /// When it turns itself off; nil means until the user turns it off.
    public private(set) var until: Date?

    /// The lengths offered: one hour, two hours, until turned off.
    public static let choices: [TimeInterval?] = [3600, 7200, nil]

    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var endTask: Task<Void, Never>?

    public init() {}

    public func turnOn(for duration: TimeInterval? = nil) {
        if assertion == 0 {
            var id: IOPMAssertionID = 0
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Dynamic Ledge: Keep Awake" as CFString,
                &id
            )
            guard status == kIOReturnSuccess else { return }
            assertion = id
        }
        isOn = true
        until = duration.map { Date().addingTimeInterval($0) }
        endTask?.cancel()
        endTask = nil
        if let duration {
            endTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.turnOff()
            }
        }
    }

    public func turnOff() {
        endTask?.cancel()
        endTask = nil
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        isOn = false
        until = nil
    }

    public func toggle() {
        if isOn { turnOff() } else { turnOn() }
    }
}
