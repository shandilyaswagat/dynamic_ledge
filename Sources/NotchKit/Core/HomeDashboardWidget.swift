import Foundation

enum HomeDashboardWidget: String, CaseIterable, Identifiable {
    case music, calendar, timer, shortcuts, stats, bluetooth, aiUsage

    var id: String { rawValue }
}

struct HomeDashboardLayout: Equatable {
    static let columns = 3
    static let rows = 2
    static let capacity = columns * rows

    private(set) var slots: [HomeDashboardWidget?]

    init(slots: [HomeDashboardWidget?]) {
        var seen = Set<HomeDashboardWidget>()
        self.slots = (0..<Self.capacity).map { index in
            guard slots.indices.contains(index), let widget = slots[index], seen.insert(widget).inserted else { return nil }
            return widget
        }
    }

    init(rawValues: [String]) {
        self.init(slots: rawValues.map(HomeDashboardWidget.init(rawValue:)))
    }

    var rawValues: [String] { slots.map { $0?.rawValue ?? "" } }
    var widgets: [HomeDashboardWidget] { slots.compactMap { $0 } }
    var visibleRows: Int { slots.dropFirst(Self.columns).contains { $0 != nil } ? Self.rows : 1 }

    mutating func set(_ widget: HomeDashboardWidget?, at index: Int) {
        guard slots.indices.contains(index), widget == nil || !slots.contains(widget) else { return }
        slots[index] = widget
    }

    mutating func move(from source: Int, horizontal: Int, vertical: Int) {
        guard slots.indices.contains(source), slots[source] != nil else { return }
        let row = min(max(source / Self.columns + vertical, 0), Self.rows - 1)
        let column = min(max(source % Self.columns + horizontal, 0), Self.columns - 1)
        slots.swapAt(source, row * Self.columns + column)
    }
}
