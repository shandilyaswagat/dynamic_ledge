import Foundation

/// One reading of how hard the Mac is working, for Stats.
public struct SystemSnapshot: Equatable, Sendable {
    /// Share of all CPU cores in use since the previous reading, 0…1.
    public var cpu: Double
    /// Memory in use the way Activity Monitor counts it: app memory, wired and compressed.
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    /// How hard macOS is working to find memory, as Activity Monitor's graph shows it. macOS
    /// keeps RAM nearly full on purpose, so this, not the percentage, says whether it's a problem.
    public var memoryPressure: StatsMath.Level
    public var diskFree: Int64
    public var diskTotal: Int64
    /// Bytes per second since the previous reading.
    public var networkIn: Double
    public var networkOut: Double

    public init(cpu: Double = 0, memoryUsed: UInt64 = 0, memoryTotal: UInt64 = 0, memoryPressure: StatsMath.Level = .normal,
                diskFree: Int64 = 0, diskTotal: Int64 = 0, networkIn: Double = 0, networkOut: Double = 0) {
        self.cpu = cpu
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.memoryPressure = memoryPressure
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.networkIn = networkIn
        self.networkOut = networkOut
    }

    /// Share of memory in use, 0…1.
    public var memory: Double {
        memoryTotal > 0 ? min(1, Double(memoryUsed) / Double(memoryTotal)) : 0
    }

    /// Share of the startup disk in use, 0…1.
    public var disk: Double {
        diskTotal > 0 ? min(1, max(0, Double(diskTotal - diskFree) / Double(diskTotal))) : 0
    }
}

/// Pure maths and labels for Stats, kept apart from the system calls so they can be tested.
public enum StatsMath {
    /// CPU ticks (user, system, idle, nice) summed over all cores.
    public struct CPUTicks: Equatable, Sendable {
        public var user: UInt64
        public var system: UInt64
        public var idle: UInt64
        public var nice: UInt64

        public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
    }

    /// Busy share between two readings. Counters that went backwards (a reset) read as idle.
    public static func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> Double {
        func delta(_ a: UInt64, _ b: UInt64) -> Double { b >= a ? Double(b - a) : 0 }
        let busy = delta(old.user, new.user) + delta(old.system, new.system) + delta(old.nice, new.nice)
        let total = busy + delta(old.idle, new.idle)
        return total > 0 ? min(1, busy / total) : 0
    }

    /// Bytes per second from two cumulative counters. The kernel's 32-bit counters wrap, so a
    /// smaller second reading counts as no traffic rather than a huge spike.
    public static func rate(from old: UInt64, to new: UInt64, seconds: TimeInterval) -> Double {
        guard seconds > 0, new >= old else { return 0 }
        return Double(new - old) / seconds
    }

    /// "62%".
    public static func percent(_ share: Double) -> String {
        "\(Int((min(max(share, 0), 1) * 100).rounded()))%"
    }

    /// "11.2 GB", "512 MB": the way Finder writes sizes.
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .memory)
    }

    /// "1.2 MB/s", "0 KB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1_000 { return "0 KB/s" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = value < 1_000_000 ? .useKB : (value < 1_000_000_000 ? .useMB : .useGB)
        return formatter.string(fromByteCount: Int64(value)) + "/s"
    }

    /// How a reading should look: calm, busy or under strain.
    public enum Level: Equatable, Sendable {
        case normal
        case busy
        case high
    }

    /// The kernel's pressure level (1 normal, 2 warning, 4 critical).
    public static func pressure(_ kernelLevel: Int32) -> Level {
        switch kernelLevel {
        case 4...: .high
        case 2...: .busy
        default: .normal
        }
    }

    /// Whether a network interface is a real link (Wi-Fi, Ethernet). Tunnels and bridges carry
    /// the same traffic again, so counting them would double the speed.
    public static func countsTraffic(interface name: String) -> Bool {
        name.hasPrefix("en")
    }

    public static func level(_ share: Double) -> Level {
        switch share {
        case ..<0.7: .normal
        case ..<0.9: .busy
        default: .high
        }
    }
}
