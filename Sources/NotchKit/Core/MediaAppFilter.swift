import Foundation

/// Which apps Now Playing listens to: every app, or only the ones the user picked.
public struct MediaAppFilter: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable, Identifiable {
        case all
        case chosen

        public var id: String { rawValue }
    }

    public var mode: Mode
    /// Bundle identifiers allowed in `.chosen` mode.
    public var allowed: Set<String>

    public static let all = MediaAppFilter(mode: .all, allowed: [])

    public init(mode: Mode, allowed: Set<String>) {
        self.mode = mode
        self.allowed = allowed
    }

    /// An app that can't be identified is only shown when every app is.
    public func allows(_ bundleIdentifier: String?) -> Bool {
        switch mode {
        case .all: true
        case .chosen: bundleIdentifier.map(allowed.contains) ?? false
        }
    }
}

/// Apps that played something recently, most recent first, so Settings can offer them.
public struct RecentMediaApps: Equatable, Sendable {
    public static let limit = 12

    public private(set) var identifiers: [String]

    public init(_ identifiers: [String] = []) {
        var seen = Set<String>()
        self.identifiers = Array(identifiers.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(Self.limit))
    }

    /// Returns false when nothing changed, so callers can skip saving. An app already in the
    /// list stays where it is: playback reports arrive often, and reordering on each would mean
    /// a write every time.
    @discardableResult
    public mutating func note(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, !identifiers.contains(identifier) else { return false }
        identifiers.insert(identifier, at: 0)
        if identifiers.count > Self.limit { identifiers.removeLast(identifiers.count - Self.limit) }
        return true
    }

    public mutating func remove(_ identifier: String) {
        identifiers.removeAll { $0 == identifier }
    }
}
