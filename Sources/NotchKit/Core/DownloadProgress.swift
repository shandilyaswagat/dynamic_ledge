import Foundation

/// One download in progress, as a browser reports it.
public struct DownloadProgressItem: Equatable, Sendable, Identifiable {
    /// The file being written.
    public var id: String
    public var name: String
    public var completed: Int64
    /// Zero or less when the browser doesn't know the size yet.
    public var total: Int64
    /// Estimated from recent speed; nil until there's enough to go on.
    public var secondsLeft: TimeInterval?
    public var startedAt: Date

    public init(id: String, name: String, completed: Int64, total: Int64, secondsLeft: TimeInterval? = nil, startedAt: Date) {
        self.id = id
        self.name = name
        self.completed = completed
        self.total = total
        self.secondsLeft = secondsLeft
        self.startedAt = startedAt
    }

    /// 0…1, or nil when the size isn't known.
    public var fraction: Double? {
        guard total > 0 else { return nil }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    /// The name the file will have when it's done: "report.pdf", not "report.pdf.crdownload".
    public static func displayName(for url: URL) -> String {
        var name = url.lastPathComponent
        while DownloadRules.partialExtensions.contains((name as NSString).pathExtension.lowercased()) {
            name = (name as NSString).deletingPathExtension
        }
        return name.isEmpty ? url.lastPathComponent : name
    }
}

/// Everything downloading at once, as one activity.
public struct DownloadSummary: Equatable, Sendable {
    public var items: [DownloadProgressItem]

    public init(_ items: [DownloadProgressItem]) {
        self.items = items
    }

    /// Bytes done over bytes expected, for the downloads whose size is known.
    public var fraction: Double? {
        let sized = items.filter { $0.total > 0 }
        let total = sized.reduce(Int64(0)) { $0 + $1.total }
        guard total > 0 else { return nil }
        let done = sized.reduce(Int64(0)) { $0 + min($1.completed, $1.total) }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    /// The longest wait among the downloads, since the activity lasts until the last one ends.
    public var secondsLeft: TimeInterval? {
        items.compactMap(\.secondsLeft).max()
    }
}

/// Smoothed download speed, so the time left doesn't jump with every burst.
public struct DownloadRate: Sendable {
    public private(set) var bytesPerSecond: Double?
    private var last: (bytes: Int64, time: Date)?

    /// How much each new sample counts; the rest is the running average.
    static let weight = 0.3

    public init() {}

    public mutating func add(bytes: Int64, at time: Date) {
        defer { last = (bytes, time) }
        guard let last else { return }
        let elapsed = time.timeIntervalSince(last.time)
        guard elapsed > 0.05, bytes >= last.bytes else { return }
        let speed = Double(bytes - last.bytes) / elapsed
        bytesPerSecond = bytesPerSecond.map { $0 + Self.weight * (speed - $0) } ?? speed
    }

    public func secondsLeft(completed: Int64, total: Int64) -> TimeInterval? {
        guard total > 0, let speed = bytesPerSecond, speed > 1 else { return nil }
        return max(0, Double(total - completed) / speed)
    }
}

public enum DownloadFormat {
    /// "12 MB of 340 MB", or "12 MB" when the size isn't known.
    public static func bytes(_ completed: Int64, of total: Int64) -> String {
        let done = ByteCountFormatter.string(fromByteCount: max(0, completed), countStyle: .file)
        guard total > 0 else { return done }
        return done + " of " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    /// "8 sec left", "3 min left", "1 hr 5 min left".
    public static func timeLeft(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded())
        if value < 60 { return "\(max(1, value)) sec left" }
        let minutes = (value + 30) / 60
        if minutes < 60 { return "\(minutes) min left" }
        return "\(minutes / 60) hr \(minutes % 60) min left"
    }
}
