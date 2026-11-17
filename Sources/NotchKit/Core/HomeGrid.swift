import Foundation

/// How much of Home's grid a tile takes: one cell, two side by side, or two by two.
public enum HomeTileSize: String, CaseIterable, Sendable, Codable {
    case small
    case wide
    case large

    /// Columns and rows it covers.
    public var columns: Int { self == .small ? 1 : 2 }
    public var rows: Int { self == .large ? 2 : 1 }

    /// The next size when its resize handle is pressed: small, wide, large, then small again.
    public var next: HomeTileSize {
        switch self {
        case .small: .wide
        case .wide: .large
        case .large: .small
        }
    }

    /// The size closest to a span dragged out with the resize handle.
    public static func fitting(columns: Int, rows: Int) -> HomeTileSize {
        if columns >= 2, rows >= 2 { return .large }
        return columns >= 2 ? .wide : .small
    }

    /// Elongated keeps one row. The wide size preserves each widget's original width.
    var elongatedWidthMultiplier: CGFloat {
        switch self {
        case .small: 0.8
        case .wide: 1
        case .large: 1.25
        }
    }

    static func fitting(elongatedWidth: CGFloat, originalWidth: CGFloat) -> HomeTileSize {
        allCases.min { abs($0.elongatedWidthMultiplier * originalWidth - elongatedWidth)
                      < abs($1.elongatedWidthMultiplier * originalWidth - elongatedWidth) } ?? .wide
    }
}

/// What a Home tile shows: a launcher feature or the favourite Shortcuts.
public enum HomeTileItem: String, CaseIterable, Sendable, Identifiable {
    case nowPlaying
    case timer
    case stopwatch
    case calendar
    case reminders
    case clipboard
    case files
    case scratchpad
    case mirror
    case keepAwake
    case stats
    case aiUsage
    case shortcuts

    public var id: String { rawValue }
    static var standardItems: [Self] { allCases.filter { $0 != .nowPlaying } }

    /// The launcher feature it opens; nil for Shortcuts, which runs the favourites instead.
    public var launcherItem: LauncherItem? { LauncherItem(rawValue: rawValue) }

    public var title: String { launcherItem?.title ?? "Shortcuts" }
    public var symbolName: String { launcherItem?.symbolName ?? "bolt.fill" }
}

/// One tile on Home: what it shows and its size.
public struct HomeTile: Equatable, Hashable, Sendable, Identifiable {
    public var item: HomeTileItem
    public var size: HomeTileSize

    public var id: HomeTileItem { item }

    public init(_ item: HomeTileItem, _ size: HomeTileSize = .small) {
        self.item = item
        self.size = size
    }

    /// Saved as "calendar:wide".
    public var rawValue: String { "\(item.rawValue):\(size.rawValue)" }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard let item = parts.first.flatMap(HomeTileItem.init(rawValue:)) else { return nil }
        self.item = item
        self.size = parts.count > 1 ? HomeTileSize(rawValue: parts[1]) ?? .small : .small
    }
}

/// The tiles on Home, in order, as the user arranged them (hold a tile to edit).
public struct HomeGrid: Equatable, Sendable {
    /// Stats, Calendar and Reminders up top, then the quick switches and clocks.
    public static let defaultTiles: [HomeTile] = [
        HomeTile(.stats, .large),
        HomeTile(.calendar, .wide),
        HomeTile(.reminders, .wide),
        HomeTile(.keepAwake),
        HomeTile(.aiUsage),
        HomeTile(.timer),
        HomeTile(.stopwatch),
    ]

    /// The original inline widgets, in their original order and widths.
    public static let defaultElongatedTiles: [HomeTile] = [
        .nowPlaying, .mirror, .calendar, .scratchpad, .timer, .reminders, .stats, .aiUsage,
    ].map { HomeTile($0, .wide) }

    public private(set) var tiles: [HomeTile]
    private let layout: NookLayout

    /// Drops unknown values and repeats, so an old or malformed preference is harmless.
    public init(rawValues: [String], layout: NookLayout = .standard) {
        self.init(tiles: rawValues.compactMap(HomeTile.init(rawValue:)), layout: layout)
    }

    public init(tiles: [HomeTile] = Self.defaultTiles, layout: NookLayout = .standard) {
        self.layout = layout
        var seen = Set<HomeTileItem>()
        self.tiles = tiles.filter { (layout == .elongated || $0.item != .nowPlaying) && seen.insert($0.item).inserted }
    }

    public var rawValues: [String] { tiles.map(\.rawValue) }

    public func contains(_ item: HomeTileItem) -> Bool {
        tiles.contains { $0.item == item }
    }

    public func size(of item: HomeTileItem) -> HomeTileSize? {
        tiles.first { $0.item == item }?.size
    }

    /// Adds a feature at the end as a small tile, once.
    @discardableResult
    public mutating func add(_ item: HomeTileItem) -> Bool {
        guard (layout == .elongated || item != .nowPlaying), !contains(item) else { return false }
        tiles.append(HomeTile(item))
        return true
    }

    @discardableResult
    public mutating func remove(_ item: HomeTileItem) -> Bool {
        guard let index = tiles.firstIndex(where: { $0.item == item }) else { return false }
        tiles.remove(at: index)
        return true
    }

    public mutating func resize(_ item: HomeTileItem, to size: HomeTileSize) {
        guard let index = tiles.firstIndex(where: { $0.item == item }) else { return }
        tiles[index].size = size
    }

    /// Moves a tile to where another one is, the others shifting along, like rearranging apps.
    public mutating func move(_ item: HomeTileItem, to target: HomeTileItem) {
        guard item != target,
              let from = tiles.firstIndex(where: { $0.item == item }),
              let to = tiles.firstIndex(where: { $0.item == target }) else { return }
        let tile = tiles.remove(at: from)
        tiles.insert(tile, at: to)
    }
}

/// Where each tile goes in a grid of fixed columns, pages of `rowsPerPage` rows. Each tile, in
/// order, takes the first free spot it fits, so a small tile can fill a gap left beside a big one,
/// like the iPhone's Control Center. A tile never runs across two pages.
public enum HomeGridLayout {
    public struct Placement: Equatable, Sendable {
        public var tile: HomeTile
        public var page: Int
        public var column: Int
        /// Row on its page.
        public var row: Int
    }

    public static func place(_ tiles: [HomeTile], columns: Int, rowsPerPage: Int) -> [Placement] {
        guard columns > 0, rowsPerPage > 0 else { return [] }
        var taken: [[Bool]] = []
        var placements: [Placement] = []
        func fits(_ page: Int, _ row: Int, _ column: Int, _ size: HomeTileSize) -> Bool {
            guard column + size.columns <= columns, row + size.rows <= rowsPerPage else { return false }
            for r in row..<(row + size.rows) {
                for c in column..<(column + size.columns) where taken[page * rowsPerPage + r][c] {
                    return false
                }
            }
            return true
        }
        for tile in tiles {
            // Too wide for the grid: shrink it so it still shows.
            var tile = tile
            if tile.size.columns > columns || tile.size.rows > rowsPerPage { tile.size = .small }
            var page = 0
            placing: while true {
                while taken.count < (page + 1) * rowsPerPage {
                    taken.append(Array(repeating: false, count: columns))
                }
                for row in 0..<rowsPerPage {
                    for column in 0..<columns where fits(page, row, column, tile.size) {
                        for r in row..<(row + tile.size.rows) {
                            for c in column..<(column + tile.size.columns) {
                                taken[page * rowsPerPage + r][c] = true
                            }
                        }
                        placements.append(Placement(tile: tile, page: page, column: column, row: row))
                        break placing
                    }
                }
                page += 1
            }
        }
        return placements
    }

    /// Pages the tiles need: at least one, so an empty Home still has its space.
    public static func pageCount(_ placements: [Placement]) -> Int {
        (placements.map(\.page).max() ?? 0) + 1
    }
}
