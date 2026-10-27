import Foundation

/// The user-editable shortcuts beside the notch controls. Home is deliberately not represented
/// here: it is always present, while these are the optional feature shortcuts that follow it.
public struct FeatureShortcutSelection: Equatable, Sendable {
    public static let maximumItems = 3
    /// The default shortcuts shown beside Home when the user has not customized their shortcuts.
    /// Matches the tabs that previously existed in the top-left nook header.
    public static let defaultItems: [LauncherItem] = [.files, .clipboard]

    public private(set) var items: [LauncherItem]

    /// Drops unknown values, repeats and overflow so an old or malformed preference is harmless.
    public init(rawValues: [String]) {
        self.init(items: rawValues.compactMap(LauncherItem.init(rawValue:)))
    }

    public init(items: [LauncherItem]) {
        var seen = Set<LauncherItem>()
        self.items = items.filter { seen.insert($0).inserted }.prefix(Self.maximumItems).map { $0 }
    }

    public var rawValues: [String] {
        items.map(\.rawValue)
    }

    public func contains(_ item: LauncherItem) -> Bool {
        items.contains(item)
    }

    /// Adds a feature once, up to the fixed number of slots.
    @discardableResult
    public mutating func add(_ item: LauncherItem) -> Bool {
        guard !contains(item), items.count < Self.maximumItems else { return false }
        items.append(item)
        return true
    }

    @discardableResult
    public mutating func remove(_ item: LauncherItem) -> Bool {
        guard let index = items.firstIndex(of: item) else { return false }
        items.remove(at: index)
        return true
    }
}
