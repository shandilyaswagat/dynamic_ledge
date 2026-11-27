import CoreGraphics
import Foundation

enum HomeDashboardWidget: String, CaseIterable, Identifiable {
    case music, calendar, timer, shortcuts, stats, bluetooth, aiUsage

    var id: String { rawValue }
}

enum HomeDashboardEditorMode: Equatable {
    case arranging
    case dragging
    case choosing
}

/// Where a card sits on the Home grid, and how many cells it covers each way.
struct HomeDashboardCard: Equatable {
    let widget: HomeDashboardWidget
    var column: Int
    var row: Int
    var width: Int
    var height: Int

    var columns: Range<Int> { column..<(column + width) }
    var rows: Range<Int> { row..<(row + height) }

    func overlaps(_ other: HomeDashboardCard) -> Bool {
        columns.overlaps(other.columns) && rows.overlaps(other.rows)
    }
}

/// Cards placed freely on a fine grid.
struct HomeDashboardLayout: Equatable {
    enum Presentation {
        case editor, home
    }

    static let columns = 6
    static let rows = 2
    /// Narrower than a third of Home, a card's content no longer fits.
    static let minimumWidth = 2

    private(set) var cards: [HomeDashboardCard] = []

    init(cards: [HomeDashboardCard] = []) {
        for card in cards where !widgets.contains(card.widget) && fits(card) {
            self.cards.append(card)
        }
    }

    init(widgets: [HomeDashboardWidget]) {
        widgets.forEach { add($0) }
    }

    /// A card is saved as "name:column:row:width:height".
    init(rawValues: [String]) {
        self.init(cards: rawValues.enumerated().compactMap { index, entry in
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard let name = parts.first, let widget = HomeDashboardWidget(rawValue: String(name)) else { return nil }
            // Earlier builds saved six fixed slots, three to a row, as bare names.
            if parts.count == 1 {
                return HomeDashboardCard(widget: widget, column: index % 3 * Self.minimumWidth,
                                         row: index / 3, width: Self.minimumWidth, height: 1)
            }
            guard parts.count == 5, let column = Int(parts[1]), let row = Int(parts[2]),
                  let width = Int(parts[3]), let height = Int(parts[4]) else { return nil }
            return HomeDashboardCard(widget: widget, column: column, row: row, width: width, height: height)
        })
    }

    var rawValues: [String] {
        cards.map { "\($0.widget.rawValue):\($0.column):\($0.row):\($0.width):\($0.height)" }
    }

    var widgets: [HomeDashboardWidget] { cards.map(\.widget) }
    /// Rows holding at least one card: how many Home shows.
    var occupiedRows: Int { Self.used(Self.rows, by: cards.map(\.rows)).count }
    /// Rows down to the lowest card, empty ones above it included: how many the editor shows.
    var extentRows: Int { cards.map(\.rows.upperBound).max() ?? 0 }
    var hasRoom: Bool { freeSpot != nil }

    func card(for widget: HomeDashboardWidget) -> HomeDashboardCard? {
        cards.first { $0.widget == widget }
    }

    mutating func add(_ widget: HomeDashboardWidget) {
        guard !widgets.contains(widget), let spot = freeSpot else { return }
        cards.append(HomeDashboardCard(widget: widget, column: spot.column, row: spot.row, width: Self.minimumWidth, height: 1))
    }

    mutating func remove(_ widget: HomeDashboardWidget) {
        cards.removeAll { $0.widget == widget }
    }

    /// Moves the card's top-left corner to the cell, as near as its size allows.
    @discardableResult
    mutating func move(_ widget: HomeDashboardWidget, toColumn column: Int, row: Int) -> Bool {
        guard let card = card(for: widget) else { return false }
        return place(HomeDashboardCard(widget: widget, column: column, row: row, width: card.width, height: card.height))
    }

    /// Resizes the card from its top-left corner.
    @discardableResult
    mutating func resize(_ widget: HomeDashboardWidget, width: Int, height: Int) -> Bool {
        guard let card = card(for: widget) else { return false }
        return place(HomeDashboardCard(widget: widget, column: card.column, row: card.row,
                                       width: min(width, Self.columns - card.column), height: min(height, Self.rows - card.row)))
    }

    /// Puts the card there, kept within the grid. Cards in the way make room: each goes where
    /// the card came from if it fits, else to the nearest gap, narrower or shorter when it
    /// must. False, with nothing changed, when they can't all fit.
    @discardableResult
    mutating func place(_ target: HomeDashboardCard) -> Bool {
        guard let original = card(for: target.widget) else { return false }
        var placed = target
        placed.width = min(max(placed.width, Self.minimumWidth), Self.columns)
        placed.height = min(max(placed.height, 1), Self.rows)
        placed.column = min(max(placed.column, 0), Self.columns - placed.width)
        placed.row = min(max(placed.row, 0), Self.rows - placed.height)
        guard placed != original else { return true }

        var next = self
        next.cards = [placed] + cards.filter { $0.widget != placed.widget && !$0.overlaps(placed) }
        let displaced = cards.filter { $0.widget != placed.widget && $0.overlaps(placed) }
        guard next.relocate(displaced[...], preferring: original) else { return false }
        cards = cards.compactMap { next.card(for: $0.widget) }
        return true
    }

    private mutating func relocate(_ displaced: ArraySlice<HomeDashboardCard>, preferring vacated: HomeDashboardCard) -> Bool {
        guard let card = displaced.first else { return true }
        for candidate in placements(for: card, preferring: vacated) {
            cards.append(candidate)
            if relocate(displaced.dropFirst(), preferring: vacated) { return true }
            cards.removeLast()
        }
        return false
    }

    /// Tries the original size first and prefers trading places over an equally sized gap.
    private func placements(for card: HomeDashboardCard, preferring vacated: HomeDashboardCard) -> [HomeDashboardCard] {
        var sizes = [(card.width, card.height)]
        for height in Set([card.height, 1]).sorted(by: >) {
            for width in stride(from: card.width, through: Self.minimumWidth, by: -1) where (width, height) != (card.width, card.height) {
                sizes.append((width, height))
            }
        }
        return sizes.flatMap { width, height in
            var candidates: [(card: HomeDashboardCard, distance: Int)] = []
            for row in 0...(Self.rows - height) {
                for column in 0...(Self.columns - width) {
                    let candidate = HomeDashboardCard(widget: card.widget, column: column, row: row, width: width, height: height)
                    guard fits(candidate) else { continue }
                    // A row is about a column and a half tall. Trading places beats any other gap.
                    let distance = (column, row) == (vacated.column, vacated.row) ? -1
                        : 2 * abs(column - card.column) + 3 * abs(row - card.row)
                    candidates.append((candidate, distance))
                }
            }
            return candidates.sorted { $0.distance < $1.distance }.map(\.card)
        }
    }

    func frames(in width: CGFloat, rowHeight: CGFloat, gap: CGFloat, presentation: Presentation) -> [HomeDashboardWidget: CGRect] {
        let rows = presentation == .home ? Self.used(Self.rows, by: cards.map(\.rows)) : Array(0..<Self.rows)
        let unit = max(1, (width - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns))
        var frames: [HomeDashboardWidget: CGRect] = [:]
        for card in cards {
            guard let row = rows.firstIndex(of: card.row) else { continue }
            frames[card.widget] = CGRect(
                x: CGFloat(card.column) * (unit + gap),
                y: CGFloat(row) * (rowHeight + gap),
                width: CGFloat(card.width) * (unit + gap) - gap,
                height: CGFloat(card.height) * (rowHeight + gap) - gap
            )
        }
        return frames
    }

    private static func used(_ count: Int, by ranges: [Range<Int>]) -> [Int] {
        (0..<count).filter { line in ranges.contains { $0.contains(line) } }
    }

    /// The first gap a new, smallest card fits, reading across each row from the top.
    private var freeSpot: (column: Int, row: Int)? {
        for row in 0..<Self.rows {
            for column in 0...(Self.columns - Self.minimumWidth) {
                let cells = HomeDashboardCard(widget: .music, column: column, row: row, width: Self.minimumWidth, height: 1)
                if !cards.contains(where: { $0.overlaps(cells) }) { return (column, row) }
            }
        }
        return nil
    }

    private func fits(_ card: HomeDashboardCard) -> Bool {
        (Self.minimumWidth...Self.columns).contains(card.width) && (1...Self.rows).contains(card.height)
            && card.column >= 0 && card.row >= 0
            && card.column <= Self.columns - card.width && card.row <= Self.rows - card.height
            && !cards.contains { $0.widget != card.widget && $0.overlaps(card) }
    }
}
