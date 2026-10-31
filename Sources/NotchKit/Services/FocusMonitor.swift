import Foundation

public struct FocusMode: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let symbol: String

    public init(id: String, name: String, symbol: String = "moon.fill") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }

    public static let dnd = FocusMode(id: "dnd", name: "Do Not Disturb", symbol: "moon.fill")
    public static let work = FocusMode(id: "work", name: "Work", symbol: "briefcase.fill")
    public static let personal = FocusMode(id: "personal", name: "Personal", symbol: "person.fill")
    public static let sleep = FocusMode(id: "sleep", name: "Sleep", symbol: "bed.double.fill")
}

@MainActor
public protocol FocusMonitoring: AnyObject {
    var onAlert: ((IslandAlert) -> Void)? { get set }
    func start()
    func stop()
}

/// Replaceable Focus and Do Not Disturb monitor. Watches system notifications
/// and alerts the notch when a Focus mode is engaged.
@MainActor
public final class FocusMonitor: FocusMonitoring {
    public var onAlert: ((IslandAlert) -> Void)?

    private var observer: NSObjectProtocol?
    private let center: DistributedNotificationCenter
    private var lastMode: String?

    public init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    public func start() {
        guard observer == nil else { return }
        observer = center.addObserver(
            forName: .init("com.apple.donotdisturb.mode.changed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notify(mode: .dnd)
            }
        }
    }

    public func stop() {
        if let observer {
            center.removeObserver(observer)
        }
        observer = nil
    }

    public func notify(mode: FocusMode) {
        guard lastMode != mode.name else { return }
        lastMode = mode.name
        onAlert?(.focus(name: mode.name, symbol: mode.symbol))
    }
}
