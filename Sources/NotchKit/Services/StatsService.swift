import Darwin
import Foundation
import Observation

/// Reads CPU, memory, disk and network every couple of seconds, only while Stats is switched on.
/// Every reading is a handful of cheap kernel calls; nothing is stored or sent anywhere.
@MainActor
@Observable
public final class StatsService {
    public private(set) var snapshot = SystemSnapshot()
    /// False until two readings exist, since CPU and network need a difference to measure.
    public private(set) var hasReading = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: StatsMath.CPUTicks?
    @ObservationIgnored private var lastNetwork: (received: UInt64, sent: UInt64, at: Date)?
    @ObservationIgnored private var lastDiskCheck = Date.distantPast

    static let interval: TimeInterval = 2
    /// Asked for once: every `mach_host_self()` call hands out a port right that must be released.
    private static let host = mach_host_self()

    public init() {}

    public var isRunning: Bool { timer != nil }

    public func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops reading for a while (something else is in the notch) but keeps the last counters,
    /// so the first reading after resuming is already a real one.
    public func pause() {
        timer?.invalidate()
        timer = nil
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
        lastNetwork = nil
        hasReading = false
    }

    private func sample() {
        var next = snapshot
        let now = Date()
        var measuredChange = false
        if let ticks = Self.cpuTicks() {
            if let lastTicks {
                next.cpu = StatsMath.cpuUsage(from: lastTicks, to: ticks)
                measuredChange = true
            }
            lastTicks = ticks
        }
        if let memory = Self.memoryUsed() {
            next.memoryUsed = memory
        }
        next.memoryPressure = Self.memoryPressure()
        next.memoryTotal = ProcessInfo.processInfo.physicalMemory
        if let network = Self.networkBytes() {
            if let last = lastNetwork {
                let seconds = now.timeIntervalSince(last.at)
                next.networkIn = StatsMath.rate(from: last.received, to: network.received, seconds: seconds)
                next.networkOut = StatsMath.rate(from: last.sent, to: network.sent, seconds: seconds)
            }
            lastNetwork = (network.received, network.sent, now)
        }
        // Free space barely moves; once a minute is plenty.
        if now.timeIntervalSince(lastDiskCheck) > 60, let disk = Self.disk() {
            next.diskFree = disk.free
            next.diskTotal = disk.total
            lastDiskCheck = now
        }
        if next != snapshot { snapshot = next }
        if measuredChange, !hasReading { hasReading = true }
    }

    // MARK: System calls

    private static func cpuTicks() -> StatsMath.CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return StatsMath.CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// App memory (anonymous pages that can't be purged), wired and compressed, like the
    /// "Memory Used" figure in Activity Monitor.
    private static func memoryUsed() -> UInt64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let app = UInt64(info.internal_page_count) - min(UInt64(info.internal_page_count), UInt64(info.purgeable_count))
        return (app + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * page
    }

    /// Total bytes in and out across the network interfaces that are up, loopback excluded.
    private static func networkBytes() -> (received: UInt64, sent: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard StatsMath.countsTraffic(interface: String(cString: entry.ifa_name)),
                  entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }

    private static func memoryPressure() -> StatsMath.Level {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return StatsMath.pressure(level)
    }

    private static func disk() -> (free: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }
}
