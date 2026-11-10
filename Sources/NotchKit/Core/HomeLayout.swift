import Foundation

/// Something that can sit on Home. Which ones show, and in what order, is the user's choice.
public enum HomeItem: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Music, calls and running clocks.
    case live
    case calendar
    case timer
    /// The favourite Shortcuts picked in Settings.
    case shortcuts
    /// Codex and Antigravity limits (Settings › General › Coding Assistants).
    case aiUsage
    /// The user's own tiles (`HomeTile`).
    case tiles
    case mirror
    case notes
    case todos
    case stats

    public var id: String { rawValue }

    /// Whether the standard layout has room for it. The elongated row shows every item.
    public var inStandardLayout: Bool {
        switch self {
        case .live, .calendar, .timer, .shortcuts, .aiUsage, .tiles: true
        case .mirror, .notes, .todos, .stats: false
        }
    }
}

/// Which Home items are shown and in what order. The two layouts share it.
public struct HomeLayoutSelection: Equatable, Sendable, Codable {
    public struct Entry: Equatable, Sendable, Codable {
        public var item: HomeItem
        public var isVisible: Bool

        public init(item: HomeItem, isVisible: Bool = true) {
            self.item = item
            self.isVisible = isVisible
        }
    }

    public private(set) var entries: [Entry]

    /// The order the standard layout has always had, then the items only the elongated row shows.
    public static let defaultOrder: [HomeItem] = [.live, .calendar, .timer, .shortcuts, .aiUsage, .tiles, .mirror, .notes, .todos, .stats]

    public static let standard = HomeLayoutSelection(entries: defaultOrder.map { Entry(item: $0) })

    /// What Home shows before the user changes anything, so the first edit starts from what they
    /// see. The elongated row has always had its own order, and no Shortcuts widget.
    public static func builtIn(elongated: Bool) -> HomeLayoutSelection {
        guard elongated else { return standard }
        let order: [HomeItem] = [.live, .mirror, .calendar, .notes, .timer, .todos, .stats, .aiUsage, .shortcuts, .tiles]
        return HomeLayoutSelection(entries: order.map { Entry(item: $0, isVisible: $0 != .shortcuts) })
    }

    /// Drops repeats, then adds any item that is missing at the end, shown. An old preference
    /// from a version with fewer items stays valid, and a new item turns up instead of vanishing.
    public init(entries: [Entry]) {
        var seen = Set<HomeItem>()
        var kept = entries.filter { seen.insert($0.item).inserted }
        for item in Self.defaultOrder where !seen.contains(item) {
            kept.append(Entry(item: item))
        }
        self.entries = kept
    }

    /// Reads a saved preference, ignoring items this version doesn't know. Nil when it can't be read.
    public init?(data: Data) {
        struct Saved: Decodable {
            struct SavedEntry: Decodable {
                var item: String
                var isVisible: Bool
            }
            var entries: [SavedEntry]
        }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        self.init(entries: saved.entries.compactMap { entry in
            HomeItem(rawValue: entry.item).map { Entry(item: $0, isVisible: entry.isVisible) }
        })
    }

    public var data: Data? {
        struct Out: Encodable {
            struct OutEntry: Encodable {
                var item: String
                var isVisible: Bool
            }
            var entries: [OutEntry]
        }
        return try? JSONEncoder().encode(Out(entries: entries.map { .init(item: $0.item.rawValue, isVisible: $0.isVisible) }))
    }

    /// The items to show, in order.
    public var visibleItems: [HomeItem] {
        entries.filter(\.isVisible).map(\.item)
    }

    public func isVisible(_ item: HomeItem) -> Bool {
        entries.first { $0.item == item }?.isVisible ?? false
    }

    public mutating func setVisible(_ item: HomeItem, _ visible: Bool) {
        guard let index = entries.firstIndex(where: { $0.item == item }) else { return }
        entries[index].isVisible = visible
    }

    /// Moves an item one place up (-1) or down (+1). Returns false at either end.
    @discardableResult
    public mutating func move(_ item: HomeItem, by step: Int) -> Bool {
        guard let index = entries.firstIndex(where: { $0.item == item }) else { return false }
        let target = index + step
        guard entries.indices.contains(target) else { return false }
        entries.swapAt(index, target)
        return true
    }

    /// For drag and drop in Settings' list.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var moved = entries
        let items = source.sorted().map { moved[$0] }
        for index in source.sorted(by: >) { moved.remove(at: index) }
        let shift = source.filter { $0 < destination }.count
        moved.insert(contentsOf: items, at: min(max(destination - shift, 0), moved.count))
        entries = moved
    }
}

/// A button the user makes for Home: opens an app, a website or a folder, or runs a Shortcut.
public struct HomeTile: Equatable, Sendable, Codable, Identifiable {
    public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
        /// One of the app's own features: Clipboard, Files, Notes and so on (`LauncherItem`).
        case feature, app, website, folder, shortcut

        public var id: String { rawValue }
    }

    public var id: UUID
    public var title: String
    /// An SF Symbol name.
    public var symbol: String
    public var kind: Kind
    /// A feature's name (`LauncherItem.rawValue`), an app or folder path, a web address, or a
    /// Shortcut's name.
    public var target: String

    public init(id: UUID = UUID(), title: String, symbol: String, kind: Kind, target: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.kind = kind
        self.target = target
    }

    /// Few enough to fit Home's two columns of three.
    public static let maximum = 6

    /// Symbols to choose from, so a tile can be told apart at a glance.
    public static let symbols = [
        "star.fill", "heart.fill", "bolt.fill", "globe", "folder.fill", "doc.text.fill",
        "envelope.fill", "message.fill", "music.note", "play.rectangle.fill", "gamecontroller.fill",
        "hammer.fill", "terminal.fill", "paintbrush.fill", "camera.fill", "cart.fill",
    ]

    /// The feature a feature tile opens. Nil for the other kinds, or a feature this version lacks.
    public var featureItem: LauncherItem? {
        kind == .feature ? LauncherItem(rawValue: target) : nil
    }

    /// A tile can be saved once it has a name and something to open.
    public var isComplete: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return kind != .feature || featureItem != nil
    }

    /// What the tile opens, for a list in Settings.
    public var summary: String {
        kind == .feature ? (featureItem?.title ?? target) : target
    }

    /// The address a website tile opens. A bare "example.com" gets https. Nil when it isn't a
    /// web address that can be opened.
    public var webURL: URL? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let full = text.contains("://") || text.hasPrefix("mailto:") ? text : "https://\(text)"
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), scheme != "file" else { return nil }
        if scheme == "http" || scheme == "https" { return url.host?.isEmpty == false ? url : nil }
        return url
    }

    /// Reads saved tiles, dropping any that can't be read, and keeping at most `maximum`.
    public static func decode(_ data: Data) -> [HomeTile]? {
        guard let tiles = try? JSONDecoder().decode([HomeTile].self, from: data) else { return nil }
        var seen = Set<UUID>()
        return tiles.filter { $0.isComplete && seen.insert($0.id).inserted }.prefix(maximum).map { $0 }
    }

    public static func encode(_ tiles: [HomeTile]) -> Data? {
        try? JSONEncoder().encode(tiles)
    }
}
