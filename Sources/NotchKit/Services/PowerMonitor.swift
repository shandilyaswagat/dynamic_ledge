import Foundation
import IOKit.ps
import Observation

/// Watches the battery and reports charging and low-battery alerts.
@MainActor
@Observable
public final class PowerMonitor {
    @ObservationIgnored public var onAlert: ((IslandAlert) -> Void)?
    public private(set) var snapshot: PowerSnapshot?

    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var powerStateObserver: NSObjectProtocol?

    public init() {}

    public func start() {
        guard source == nil else { return }
        snapshot = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            // Added to the main run loop below, so this runs on the main thread.
            MainActor.assumeIsolated { monitor.update() }
        }
        if let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
            source = created
        }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    public func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        source = nil
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
        powerStateObserver = nil
    }

    private func update() {
        let new = Self.read()
        if let alert = PowerTransitions.alert(from: snapshot, to: new) {
            onAlert?(alert)
        }
        if snapshot != new {
            snapshot = new
        }
    }

    static func read() -> PowerSnapshot {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return PowerSnapshot(hasBattery: false, level: 100, isOnAC: true, isCharging: false, isLowPowerMode: lowPower)
        }

        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        let isOnAC = providing == kIOPSACPowerValue

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let level = Int((Double(current) / Double(maximum) * 100).rounded())
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let estimate: Int? = if charging {
                description[kIOPSTimeToFullChargeKey] as? Int
            } else if !isOnAC {
                description[kIOPSTimeToEmptyKey] as? Int
            } else {
                nil
            }
            return PowerSnapshot(
                hasBattery: true, level: level, isOnAC: isOnAC, isCharging: charging, isLowPowerMode: lowPower,
                estimatedMinutes: estimate.flatMap { $0 > 0 ? $0 : nil }
            )
        }
        return PowerSnapshot(hasBattery: false, level: 100, isOnAC: true, isCharging: false, isLowPowerMode: lowPower)
    }
}
