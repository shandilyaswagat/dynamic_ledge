import AppKit
import Darwin
import Observation

/// Reads CPU, memory, disk and network every couple of seconds when a Stats view needs them.
/// A rolling minute of readings stays in memory for the charts.
@MainActor
@Observable
public final class StatsService {
    struct NetworkSample {
        let time: Date
        let download: Double
        let upload: Double
    }

    struct CPUSample {
        let time: Date
        let load: Double
    }

    public private(set) var snapshot = SystemSnapshot()
    /// False until two readings exist, since CPU and network need a difference to measure.
    public private(set) var hasReading = false
    private(set) var hasNetworkReading = false
    private(set) var cpuHistory: [CPUSample] = []
    private(set) var networkHistory: [NetworkSample] = []
    private(set) var sampledAt = Date()
    private(set) var panelMemoryPressure: StatsMath.Level?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: StatsMath.CPUTicks?
    @ObservationIgnored private var lastNetwork: (counters: [UInt16: StatsMath.InterfaceBytes], at: TimeInterval)?
    @ObservationIgnored private var lastDiskCheck = Date.distantPast
    /// Something is showing Stats; the timer runs only while this is true and the screen is on.
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var screenAsleep = false

    /// Also read disk and network, for the panel. The notch itself shows only memory and CPU.
    @ObservationIgnored public var detailed = false {
        didSet {
            guard detailed != oldValue else { return }
            // Start network over, so the first rate isn't an average over the time it was off.
            lastNetwork = nil
            hasNetworkReading = false
            if detailed, timer != nil { sample() }
        }
    }

    nonisolated static let interval: TimeInterval = 2
    nonisolated static let historyDuration: TimeInterval = 60
    nonisolated static let cpuHistoryLimit = Int(historyDuration / interval)
    /// Asked for once: every `mach_host_self()` call hands out a port right that must be released.
    private static let host = mach_host_self()
    private static let pageSize = UInt64(getpagesize())
    private static let memoryTotal = ProcessInfo.processInfo.physicalMemory

    public init() {
        // No one sees the numbers while the display sleeps, so don't read them.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreenAsleep(true) }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreenAsleep(false) }
        }
    }

    public var isRunning: Bool { timer != nil }

    public func start() {
        wanted = true
        schedule()
    }

    /// Stops reading while Stats is hidden and retains the chart samples.
    public func pause() {
        if wanted {
            lastTicks = nil
            lastNetwork = nil
            hasNetworkReading = false
        }
        wanted = false
        schedule()
    }

    public func stop() {
        pause()
        lastTicks = nil
        lastNetwork = nil
        hasReading = false
        hasNetworkReading = false
        cpuHistory.removeAll()
        networkHistory.removeAll()
    }

    private func setScreenAsleep(_ asleep: Bool) {
        screenAsleep = asleep
        if asleep {
            lastTicks = nil
            hasReading = false
            lastNetwork = nil
            hasNetworkReading = false
        }
        schedule()
    }

    private func schedule() {
        let run = wanted && !screenAsleep
        if !run {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        var next = snapshot
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.historyDuration)
        cpuHistory.removeAll { $0.time < cutoff || $0.time > now }
        networkHistory.removeAll { $0.time < cutoff || $0.time > now }
        sampledAt = now
        var measuredChange = false
        if let ticks = Self.cpuTicks() {
            if let lastTicks {
                next.cpu = StatsMath.cpuUsage(from: lastTicks, to: ticks)
                measuredChange = true
                if cpuHistory.count == Self.cpuHistoryLimit { cpuHistory.removeFirst() }
                cpuHistory.append(CPUSample(time: now, load: next.cpu))
            }
            lastTicks = ticks
        }
        if let memory = Self.memoryUsed() {
            next.memoryUsed = memory
        }
        let pressure = Self.memoryPressure()
        next.memoryPressure = pressure ?? .normal
        panelMemoryPressure = pressure
        next.memoryTotal = Self.memoryTotal
        if detailed { sampleNetwork(into: &next, time: now) }
        // Free space barely moves; once a minute is plenty.
        if detailed, now.timeIntervalSince(lastDiskCheck) > 60, let disk = Self.disk() {
            next.diskFree = disk.free
            next.diskTotal = disk.total
            lastDiskCheck = now
        }
        if next != snapshot { snapshot = next }
        if measuredChange, !hasReading { hasReading = true }
    }

    private func sampleNetwork(into next: inout SystemSnapshot, time: Date) {
        let uptime = ProcessInfo.processInfo.systemUptime
        // Opening Stats can request a reading just before the existing timer fires.
        if let lastNetwork, uptime - lastNetwork.at < 0.5 { return }
        guard let counters = Self.networkBytes() else {
            lastNetwork = nil
            hasNetworkReading = false
            return
        }
        defer { lastNetwork = (counters, uptime) }
        guard let lastNetwork else { return }
        let rates = StatsMath.networkRates(from: lastNetwork.counters, to: counters, seconds: uptime - lastNetwork.at)
        next.networkIn = rates.download
        next.networkOut = rates.upload
        hasNetworkReading = true
        if networkHistory.count == Self.cpuHistoryLimit { networkHistory.removeFirst() }
        networkHistory.append(NetworkSample(time: time, download: rates.download, upload: rates.upload))
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
        let page = pageSize
        let app = UInt64(info.internal_page_count) - min(UInt64(info.internal_page_count), UInt64(info.purgeable_count))
        return (app + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * page
    }

    /// Route interface messages expose 64-bit counters. The getifaddrs counters wrap at 4 GiB.
    private static func networkBytes() -> [UInt16: StatsMath.InterfaceBytes]? {
        var query: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        let queryCount = UInt32(query.count)
        var length = 0
        guard sysctl(&query, queryCount, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var messages = Data(count: length)
        let status = messages.withUnsafeMutableBytes { buffer in
            sysctl(&query, queryCount, buffer.baseAddress, &length, nil, 0)
        }
        guard status == 0 else { return nil }
        return messages.withUnsafeBytes { buffer in
            var counters: [UInt16: StatsMath.InterfaceBytes] = [:]
            var offset = 0
            var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
            while offset + 4 <= length {
                let size = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard size >= 4, size <= length - offset else { break }
                let start = offset
                offset += size
                guard buffer[start + 2] == UInt8(RTM_VERSION), buffer[start + 3] == UInt8(RTM_IFINFO2),
                      size >= MemoryLayout<if_msghdr2>.size else { continue }
                let entry = buffer.loadUnaligned(fromByteOffset: start, as: if_msghdr2.self)
                guard entry.ifm_flags & IFF_UP != 0, entry.ifm_flags & IFF_LOOPBACK == 0,
                      let interface = if_indextoname(UInt32(entry.ifm_index), &name),
                      StatsMath.countsTraffic(interface: String(cString: interface)) else { continue }
                counters[entry.ifm_index] = StatsMath.InterfaceBytes(received: entry.ifm_data.ifi_ibytes,
                                                                    sent: entry.ifm_data.ifi_obytes)
            }
            return counters
        }
    }

    private static func memoryPressure() -> StatsMath.Level? {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
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
