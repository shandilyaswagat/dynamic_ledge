import SwiftUI

// Home in the standard layout: a grid of tiles, six columns and two rows a page, arranged by the
// user like the iPhone's Control Center. Hold a tile to edit: remove it, drag it somewhere else,
// change its size with the corner handle, or add features from the list below.
// Music (or a call) shows up as a card beside the grid while it's live.

enum HomeSection {
    enum LiveItem: Hashable {
        case call, music, timer, stopwatch, stats, aiUsage

        var activity: ActivityKind {
            switch self {
            case .call: .call
            case .music: .nowPlaying
            case .timer: .timer
            case .stopwatch: .stopwatch
            case .stats: .stats
            case .aiUsage: .aiUsage
            }
        }
    }

    /// Cards that share the space beside the grid, like two apps playing.
    static let maximumLive = 2
}

struct StandardHomeBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let live = model.homeLiveItems
        let gap = IslandMetrics.Nook.homeGap * s
        VStack(alignment: .leading, spacing: 12 * s) {
            HStack(alignment: .top, spacing: gap - HomeTileGrid.badgeInset * s) {
                HomeTileGrid(model: model, tiles: model.homeTiles, isEditing: model.isEditingHome)
                if !live.isEmpty {
                    VStack(spacing: 6 * s) {
                        ForEach(live, id: \.self) { item in
                            LiveCard(model: model, item: item, compact: live.count > 1)
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                    .frame(width: IslandMetrics.Nook.homeLiveWidth * s)
                    // Lines up with the tiles, which leave room for their edit badges.
                    .padding(.vertical, HomeTileGrid.badgeInset * s)
                    .padding(.trailing, HomeTileGrid.badgeInset * s)
                    .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
                }
            }
            .frame(height: (IslandMetrics.Nook.homeBody * s).rounded() - 2 * s)
            if model.isEditingHome {
                AddHomeControls(model: model)
                    .padding(.horizontal, HomeTileGrid.badgeInset * s)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: live)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: model.isEditingHome)
    }
}

// MARK: Grid

/// The tiles, placed by HomeGridLayout. More than two rows make more pages, scrolled with the
/// dots on the right, like the launcher.
private struct HomeTileGrid: View {
    let model: IslandModel
    let tiles: [HomeTile]
    let isEditing: Bool
    @State private var page: Int? = 0
    @State private var dragging: HomeTileItem?
    @State private var dragOffset: CGSize = .zero
    @Environment(\.notchScale) private var s

    /// Half an edit badge, so the ones on the outer tiles aren't cut off.
    static let badgeInset: CGFloat = 7

    var body: some View {
        let placements = HomeGridLayout.place(tiles, columns: IslandMetrics.Nook.homeColumns, rowsPerPage: IslandMetrics.Nook.homeRows)
        let pages = HomeGridLayout.pageCount(placements)
        GeometryReader { geometry in
            HStack(spacing: 8 * s) {
                let width = geometry.size.width - (pages > 1 ? 22 * s : 0)
                // Room around the tiles for the edit badges on their corners.
                let inset = Self.badgeInset * s
                let metrics = GridMetrics(size: CGSize(width: width - 2 * inset, height: geometry.size.height - 2 * inset), gap: IslandMetrics.Nook.homeGap * s)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<pages, id: \.self) { index in
                            let pageTiles = placements.filter { $0.page == index }
                            ZStack(alignment: .topLeading) {
                                if isEditing { emptyCells(metrics: metrics, placements: pageTiles) }
                                ForEach(pageTiles, id: \.tile.item) { placement in
                                    tile(placement, metrics: metrics, placements: placements)
                                }
                            }
                            .padding(inset)
                            .frame(width: width, height: geometry.size.height, alignment: .topLeading)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollDisabled(dragging != nil)
                if pages > 1 {
                    PageDots(count: pages, current: page ?? 0) { index in
                        withAnimation(.smooth(duration: 0.35)) { page = index }
                    }
                }
            }
        }
        .overlay {
            if tiles.isEmpty {
                Text(isEditing ? "Add controls from the list below" : "Hold here to add controls")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        // An empty Home still has a way into editing.
        .onLongPressGesture(minimumDuration: 0.4) { if tiles.isEmpty { model.startEditingHome() } }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: tiles)
        .accessibilityIdentifier("home-grid")
    }

    private func emptyCells(metrics: GridMetrics, placements: [HomeGridLayout.Placement]) -> some View {
        let columns = IslandMetrics.Nook.homeColumns
        let rows = IslandMetrics.Nook.homeRows
        let occupied = placements.map(metrics.frame)
        return ForEach(0..<(columns * rows), id: \.self) { index in
            let x = CGFloat(index % columns) * (metrics.columnWidth + metrics.gap)
            let y = CGFloat(index / columns) * (metrics.rowHeight + metrics.gap)
            let center = CGPoint(x: x + metrics.columnWidth / 2, y: y + metrics.rowHeight / 2)
            if !occupied.contains(where: { $0.contains(center) }) {
                RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                    .strokeBorder(.white.opacity(0.22),
                                  style: StrokeStyle(lineWidth: s, lineCap: .round, dash: [2 * s, 3 * s]))
                    .frame(width: metrics.columnWidth, height: metrics.rowHeight)
                    .offset(x: x, y: y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func tile(_ placement: HomeGridLayout.Placement, metrics: GridMetrics, placements: [HomeGridLayout.Placement]) -> some View {
        let frame = metrics.frame(placement)
        let item = placement.tile.item
        let isDragging = dragging == item
        HomeTileView(model: model, tile: placement.tile, isEditing: isEditing, metrics: metrics)
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(isDragging ? 1.04 : 1)
            .offset(x: frame.minX + (isDragging ? dragOffset.width : 0), y: frame.minY + (isDragging ? dragOffset.height : 0))
            .zIndex(isDragging ? 1 : 0)
            .gesture(isEditing ? reorder(item, frame: frame, placements: placements, metrics: metrics) : nil)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// While editing, drag a tile onto another to put it there.
    private func reorder(_ item: HomeTileItem, frame: CGRect, placements: [HomeGridLayout.Placement], metrics: GridMetrics) -> some Gesture {
        DragGesture(minimumDistance: 4 * s)
            .onChanged { value in
                dragging = item
                dragOffset = value.translation
            }
            .onEnded { value in
                let point = CGPoint(x: frame.midX + value.translation.width, y: frame.midY + value.translation.height)
                let current = placements.first { $0.tile.item == item }?.page ?? 0
                if let target = placements.first(where: { $0.page == current && $0.tile.item != item && metrics.frame($0).contains(point) }) {
                    model.moveHomeTile(item, to: target.tile.item)
                    Haptics.perform(enabled: model.settings.hapticsEnabled)
                }
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    dragging = nil
                    dragOffset = .zero
                }
            }
    }
}

/// Cell sizes for the space the grid has.
private struct GridMetrics {
    let size: CGSize
    let gap: CGFloat

    var columnWidth: CGFloat {
        let columns = CGFloat(IslandMetrics.Nook.homeColumns)
        return (size.width - gap * (columns - 1)) / columns
    }

    var rowHeight: CGFloat {
        let rows = CGFloat(IslandMetrics.Nook.homeRows)
        return (size.height - gap * (rows - 1)) / rows
    }

    func frame(_ placement: HomeGridLayout.Placement) -> CGRect {
        let size = placement.tile.size
        return CGRect(
            x: CGFloat(placement.column) * (columnWidth + gap),
            y: CGFloat(placement.row) * (rowHeight + gap),
            width: CGFloat(size.columns) * columnWidth + CGFloat(size.columns - 1) * gap,
            height: CGFloat(size.rows) * rowHeight + CGFloat(size.rows - 1) * gap
        )
    }
}

// MARK: Tile

/// One tile: its content on a rounded card. Click to open it, hold to edit. While editing, the
/// minus removes it and the corner handle changes its size.
private struct HomeTileView: View {
    let model: IslandModel
    let tile: HomeTile
    let isEditing: Bool
    let metrics: GridMetrics
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
        HomeTileContent(model: model, tile: tile)
            .padding(tile.size == .small ? 6 * s : 10 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tile.size == .small ? .center : .topLeading)
            .background(shape.fill(Color.white.opacity(isHovering && !isEditing ? 0.1 : 0.07)))
            .contentShape(shape)
            .allowsHitTesting(true)
            .modifier(TileTap(isEditing: isEditing, onHold: model.startEditingHome, onClick: { model.openTile(tile.item) }))
            .overlay(alignment: .topTrailing) {
                if !isEditing, tile.size == .small, model.isTileLive(tile.item) {
                    // On right now: kept awake, a timer running, shown in the notch.
                    Circle()
                        .fill(HomeTileContent.tint(tile.item))
                        .frame(width: 6 * s, height: 6 * s)
                        .padding(9 * s)
                }
            }
            .overlay(alignment: .topLeading) {
                if isEditing {
                    EditBadge(symbol: "minus", label: "Remove \(tile.item.title)") {
                        model.removeHomeTile(tile.item)
                        Haptics.perform(enabled: model.settings.hapticsEnabled)
                    }
                    .offset(x: -HomeTileGrid.badgeInset * s, y: -HomeTileGrid.badgeInset * s)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isEditing {
                    ResizeHandle(model: model, tile: tile, metrics: metrics)
                        .offset(x: HomeTileGrid.badgeInset * s, y: HomeTileGrid.badgeInset * s)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .help(isEditing ? "Drag to move" : "Hold to edit Home")
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(tile.item.title))
    }
}

/// Click opens and holding starts editing; while editing, the tile only moves.
private struct TileTap: ViewModifier {
    let isEditing: Bool
    let onHold: () -> Void
    let onClick: () -> Void

    func body(content: Content) -> some View {
        if isEditing {
            content
        } else {
            content.modifier(ClickNotHold(onHold: onHold, onClick: onClick))
        }
    }
}

/// A small round button on a tile's corner while editing.
private struct EditBadge: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9 * s, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18 * s, height: 18 * s)
                .background(Circle().fill(Color(white: 0.28)))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Drag it to pick a size, or press it to step through small, wide and large.
private struct ResizeHandle: View {
    let model: IslandModel
    let tile: HomeTile
    let metrics: GridMetrics
    @Environment(\.notchScale) private var s

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8 * s, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18 * s, height: 18 * s)
            .background(Circle().fill(Color(white: 0.28)))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let moved = abs(value.translation.width) + abs(value.translation.height)
                        let size: HomeTileSize
                        if moved < 4 * s {
                            size = tile.size.next
                        } else {
                            let columns = tile.size.columns + Int((value.translation.width / (metrics.columnWidth + metrics.gap)).rounded())
                            let rows = tile.size.rows + Int((value.translation.height / (metrics.rowHeight + metrics.gap)).rounded())
                            size = HomeTileSize.fitting(columns: columns, rows: rows)
                        }
                        guard size != tile.size else { return }
                        model.resizeHomeTile(tile.item, to: size)
                        Haptics.perform(enabled: model.settings.hapticsEnabled)
                    }
            )
            .help("Drag to resize, or press to change size")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Change size of \(tile.item.title)"))
            .accessibilityAction { model.resizeHomeTile(tile.item, to: tile.size.next) }
    }
}

// MARK: Add controls

/// Below the grid while editing: the features that aren't on Home yet. Click one to add it.
private struct AddHomeControls: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let items = model.addableHomeItems
        VStack(alignment: .leading, spacing: 8 * s) {
            Text("Add controls")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(.white)
            if items.isEmpty {
                Text("Everything is on Home")
                    .font(.system(size: 11 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(spacing: 8 * s) {
                        ForEach(items) { item in
                            Button {
                                model.addHomeTile(item)
                                Haptics.perform(enabled: model.settings.hapticsEnabled)
                            } label: {
                                HStack(spacing: 6 * s) {
                                    Image(systemName: item.symbolName)
                                        .foregroundStyle(HomeTileContent.tint(item))
                                    Text(item.title)
                                        .foregroundStyle(.white)
                                    Image(systemName: "plus")
                                        .font(.system(size: 9 * s, weight: .bold))
                                        .foregroundStyle(NotchColor.secondaryText)
                                }
                                .font(.system(size: 11.5 * s, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 11 * s)
                                .frame(height: 28 * s)
                                .background(Capsule().fill(Color.white.opacity(0.09)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel(Text("Add \(item.title)"))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("home-add-controls")
    }
}

/// Lays chips out in rows, wrapping when a row is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: Tile content

/// What a tile shows at its size. Small is the feature's symbol and name, like the launcher;
/// wide and large show what's going on (readings, the next event, the to-dos, the presets).
private struct HomeTileContent: View {
    let model: IslandModel
    let tile: HomeTile
    @Environment(\.notchScale) private var s

    var body: some View {
        if tile.size == .small {
            smallTile
        } else {
            switch tile.item {
            case .stats: HomeStatsTile(model: model, large: tile.size == .large)
            case .calendar: CalendarTile(model: model, calendar: model.calendar, large: tile.size == .large)
            case .reminders: RemindersTile(model: model, reminders: model.reminders, large: tile.size == .large)
            case .timer: TimerSection(model: model, compact: tile.size == .wide)
            case .shortcuts: ShortcutsSection(model: model, compact: tile.size == .wide)
            case .aiUsage where !model.aiUsage.visibleUsages(selected: model.settings.selectedAIProviders).isEmpty:
                LiveAIUsage(model: model, compact: tile.size == .wide)
            default: wideTile
            }
        }
    }

    private var smallTile: some View {
        VStack(spacing: 6 * s) {
            Image(systemName: Self.symbol(tile.item, live: model.isTileLive(tile.item)))
                .font(.system(size: 19 * s, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Self.tint(tile.item))
                .frame(height: 24 * s)
            Text(tile.item.title)
                .font(.system(size: 11 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    /// A feature without more to show: its name, and whether it's on.
    private var wideTile: some View {
        let live = model.isTileLive(tile.item)
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(symbol: Self.symbol(tile.item, live: live), tint: Self.tint(tile.item), title: LocalizedStringKey(tile.item.title))
            Spacer(minLength: 4 * s)
            if let state = Self.state(tile.item, live: live) {
                Text(state)
                    .font(.system(size: 11 * s, weight: .medium))
                    .foregroundStyle(live ? Self.tint(tile.item) : NotchColor.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func symbol(_ item: HomeTileItem, live: Bool) -> String {
        item.launcherItem.map { LauncherTile.symbol($0, live: live) } ?? item.symbolName
    }

    static func tint(_ item: HomeTileItem) -> Color {
        item.launcherItem.map(LauncherTile.tint) ?? NotchColor.blue
    }

    /// "On" or "Off" for the switches.
    static func state(_ item: HomeTileItem, live: Bool) -> LocalizedStringKey? {
        switch item {
        case .keepAwake, .stats, .aiUsage: live ? "On" : "Off"
        case .timer, .stopwatch: live ? "Running" : nil
        default: nil
        }
    }
}

/// The next event, or a way to connect the calendar. Clicking it opens the month once connected.
private struct CalendarTile: View {
    let model: IslandModel
    let calendar: CalendarService
    let large: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            SectionHeader(symbol: "calendar", tint: NotchColor.red, title: "Calendar")
            switch calendar.access {
            case .notAsked: message("Connect calendar")
            case .denied, .limited: message("Calendar access is off")
            case .granted:
                if let event = calendar.nextEvent {
                    Text(event.title)
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(large ? 3 : 1)
                    TimelineView(.everyMinute) { context in
                        Text(CalendarRules.relativeLabel(for: event, at: context.date))
                            .font(.system(size: 11 * s, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(event.isHappening(at: context.date) ? NotchColor.green : NotchColor.secondaryText)
                            .lineLimit(1)
                    }
                } else {
                    message("No more events this week")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11 * s, weight: .medium))
            .foregroundStyle(NotchColor.secondaryText)
            .lineLimit(2)
    }
}

/// Today's first to-dos, or a way to connect Reminders. Clicking it opens the list.
private struct RemindersTile: View {
    let model: IslandModel
    let reminders: RemindersService
    let large: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            SectionHeader(symbol: "checklist", tint: NotchColor.blue, title: "Reminders")
            switch reminders.access {
            case .notAsked: message("Connect Reminders")
            case .denied: message("Reminders access is off")
            case .granted:
                if reminders.items.isEmpty {
                    message("Nothing left for today")
                } else {
                    ForEach(reminders.items.prefix(large ? 4 : 1)) { item in
                        HStack(spacing: 6 * s) {
                            Image(systemName: "circle")
                                .font(.system(size: 10 * s, weight: .regular))
                                .foregroundStyle(NotchColor.accent(item.color))
                            Text(item.title)
                                .font(.system(size: 11.5 * s, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11 * s, weight: .medium))
            .foregroundStyle(NotchColor.secondaryText)
            .lineLimit(2)
    }
}

/// A section's name, with a chevron when clicking it opens more.
private struct SectionHeader: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    var showsChevron = false
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: symbol)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(height: 16 * s)
    }
}

// MARK: Live

/// A live activity as a card. Clicking anywhere but its buttons opens that activity's full view.
/// Compact is one row, for when it shares its section.
private struct LiveCard: View {
    let model: IslandModel
    let item: HomeSection.LiveItem
    let compact: Bool
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: (compact ? 12 : 16) * s, style: .continuous)
        Group {
            switch item {
            case .call: LiveCall(model: model, compact: compact)
            case .music: LiveMusic(service: model.nowPlaying, lyrics: model.showsLyrics ? model.lyrics.current : nil,
                                   timingAdjustment: model.lyricTimingAdjustment, compact: compact)
            case .timer: LiveTimer(model: model)
            case .stopwatch: LiveStopwatch(model: model)
            case .stats: LiveStats(stats: model.stats)
            case .aiUsage: LiveAIUsage(model: model, compact: compact)
            }
        }
        .padding(.horizontal, (compact ? 8 : 10) * s)
        .padding(.vertical, (compact ? 6 : 10) * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
        .background(shape.fill(Color.white.opacity(isHovering && opensFullView ? 0.11 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if opensFullView && !compact {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isHovering ? 0.7 : 0.3))
                    .padding(10 * s)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
        .onTapGesture {
            guard opensFullView else { return }
            model.expand(.activity(item.activity))
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(opensFullView ? "Open" : "")
        .accessibilityAddTraits(opensFullView ? .isButton : [])
    }

    /// Paused music can stay on Home after its own view has gone.
    private var opensFullView: Bool {
        model.activeActivities.contains(item.activity)
    }
}

/// Stats as a Home tile: CPU and memory side by side; large adds live rates and network history.
/// Clicking it opens the Stats panel.
private struct HomeStatsTile: View {
    let model: IslandModel
    let large: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let stats = model.stats
        let snapshot = stats.snapshot
        let pressure = stats.panelMemoryPressure ?? snapshot.memoryPressure
        Button { model.showTab(.stats) } label: {
            VStack(alignment: .leading, spacing: 6 * s) {
                HStack(spacing: 4 * s) {
                    LiveCardTitle(symbol: "gauge.with.dots.needle.33percent", tint: StatsColor.cpu, title: "Stats")
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9 * s, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .accessibilityHidden(true)
                }
                HStack(alignment: .top, spacing: 0) {
                    reading("CPU", value: stats.hasReading ? StatsMath.percent(snapshot.cpu) : nil, level: StatsMath.level(snapshot.cpu))
                    reading("Memory", value: snapshot.memoryTotal > 0 ? StatsMath.percent(snapshot.memory) : nil, level: pressure)
                }
                if large {
                    let ready = stats.hasNetworkReading
                    HStack(spacing: 6 * s) {
                        networkRate("Download", value: ready ? StatsMath.rate(snapshot.networkIn) : "–",
                                    symbol: "arrow.down", color: StatsColor.network)
                        networkRate("Upload", value: ready ? StatsMath.rate(snapshot.networkOut) : "–",
                                    symbol: "arrow.up", color: StatsColor.networkUpload)
                    }
                    .font(.system(size: 10.5 * s, weight: .medium))
                    .monospacedDigit()
                    .labelStyle(TightLabelStyle(spacing: 2 * s))
                    Spacer(minLength: 0)
                    networkGraph(stats.networkHistory, sampledAt: stats.sampledAt)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens Stats"))
        .accessibilityIdentifier("home-stats-tile")
    }

    private func networkRate(_ caption: LocalizedStringKey, value: String, symbol: String, color: Color) -> some View {
        Label {
            Text(value)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(caption))
        .accessibilityValue(Text(value))
    }

    /// A caption over a big percentage; the caption takes the reading's colour once it's busy
    /// (CPU by load, memory by pressure, as in the notch).
    private func reading(_ caption: LocalizedStringKey, value: String?, level: StatsMath.Level) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.system(size: 10.5 * s, weight: .medium))
                .foregroundStyle(value != nil && level != .normal ? level.tint : NotchColor.secondaryText)
            Text(value ?? "–")
                .font(.system(size: (large ? 24 : 20) * s, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(value == nil ? NotchColor.secondaryText : .white)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func networkGraph(_ history: [StatsService.NetworkSample], sampledAt: Date) -> some View {
        let peak = history.reduce(1024.0) { max($0, $1.download, $1.upload) }
        let scale = s
        return Canvas { context, size in
            let padding = 4 * scale
            let bottom = size.height - padding
            let width = max(0, size.width - 2 * padding)
            let height = max(0, bottom - padding)
            func trace(_ rate: KeyPath<StatsService.NetworkSample, Double>, color: Color) {
                let points = history.map { sample in
                    let age = sampledAt.timeIntervalSince(sample.time) / StatsService.historyDuration
                    return CGPoint(x: size.width - padding - width * age,
                                   y: bottom - height * sample[keyPath: rate] / peak)
                }
                guard let latest = points.last else { return }
                let line = Path { $0.addLines(points) }
                context.drawLayer { glow in
                    glow.addFilter(.shadow(color: color.opacity(0.65), radius: 2.5 * scale))
                    glow.stroke(line, with: .color(color),
                                style: StrokeStyle(lineWidth: 1.25 * scale, lineCap: .round, lineJoin: .round))
                    let dot = CGRect(x: latest.x - 2 * scale, y: latest.y - 2 * scale, width: 4 * scale, height: 4 * scale)
                    glow.fill(Path(ellipseIn: dot), with: .color(color))
                }
            }
            trace(\.download, color: StatsColor.network)
            trace(\.upload, color: StatsColor.networkUpload)
        }
        .frame(height: 34 * s)
        .accessibilityHidden(true)
    }
}

/// A symbol and its text close together.
private struct TightLabelStyle: LabelStyle {
    let spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// Memory and CPU when Stats shares the live section with another activity.
private struct LiveStats: View {
    let stats: StatsService
    @Environment(\.notchScale) private var s

    var body: some View {
        let snapshot = stats.snapshot
        let memory = snapshot.memoryTotal > 0 ? snapshot.memory : nil
        let cpu = stats.hasReading ? snapshot.cpu : nil

        HStack(spacing: 8 * s) {
            LiveCardTitle(symbol: "gauge.with.dots.needle.33percent", tint: NotchColor.green, title: "Stats")
            Spacer(minLength: 4 * s)
            HStack(spacing: 10 * s) {
                LiveReading(caption: "MEM", share: memory, level: snapshot.memoryPressure, size: 15)
                LiveReading(caption: "CPU", share: cpu, level: nil, size: 15)
            }
        }
    }
}

/// The lowest AI agent limit left and when the first one resets. Compact is one row.
private struct LiveAIUsage: View {
    let model: IslandModel
    let compact: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let windows = model.aiUsage.visibleUsages(selected: model.settings.selectedAIProviders).flatMap(\.windows)
        let remaining = windows.compactMap(\.remainingPercent).min()
        let tint = remaining.map { $0 > 25 ? NotchColor.green : NotchColor.yellow } ?? NotchColor.secondaryText
        let value = Text(remaining.map { "\(Int($0.rounded()))%" } ?? "–")
            .font(.system(size: (compact ? 15 : 22) * s, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
        if compact {
            HStack(spacing: 8 * s) {
                LiveCardTitle(symbol: "sparkles", tint: NotchColor.orange, title: "AI usage")
                Spacer(minLength: 4 * s)
                HStack(alignment: .firstTextBaseline, spacing: 3 * s) {
                    value
                    Text("left").font(.system(size: 10 * s, weight: .medium)).foregroundStyle(NotchColor.secondaryText)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                LiveCardTitle(symbol: "sparkles", tint: NotchColor.orange, title: "AI Agent Usage")
                Spacer(minLength: 6 * s)
                HStack(alignment: .firstTextBaseline, spacing: 4 * s) {
                    value
                    Text("left").font(.system(size: 11 * s, weight: .medium)).foregroundStyle(NotchColor.secondaryText)
                }
                if let reset = windows.compactMap(\.resetsAt).filter({ $0 > Date() }).min() {
                    Text("Resets \(reset, style: .relative)")
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A live card's symbol and name.
private struct LiveCardTitle: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: symbol)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

/// A caption over a percentage, coloured by how busy it is.
private struct LiveReading: View {
    let caption: LocalizedStringKey
    let share: Double?
    /// Colour override (memory follows pressure, not percentage).
    let level: StatsMath.Level?
    let size: CGFloat
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.system(size: 8 * s, weight: .bold))
                .kerning(0.3)
                .foregroundStyle(NotchColor.secondaryText)
            Text(share.map(StatsMath.percent) ?? "–")
                .font(.system(size: size * s, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(share.map { (level ?? StatsMath.level($0)).tint } ?? NotchColor.secondaryText)
        }
        .lineLimit(1)
    }
}

/// App, what it's doing and for how long, then mute and hang up (or show the app). Compact puts
/// the buttons beside the name.
private struct LiveCall: View {
    let model: IslandModel
    let compact: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        if let session = model.calls.session {
            let tint = session.isCall ? NotchColor.green : NotchColor.orange
            let title = HStack(spacing: 8 * s) {
                AppIconView(icon: model.calls.appIcon, symbol: session.isCall ? "phone.fill" : "mic.fill", tint: tint, size: (compact ? 24 : 30) * s)
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(session.appName)
                        .font(.system(size: (compact ? 12 : 13) * s, weight: .semibold))
                        .foregroundStyle(.white)
                    if let message = model.calls.hangUpMessage {
                        Text(message)
                            .font(.system(size: 10 * s, weight: .medium))
                            .foregroundStyle(NotchColor.secondaryText)
                    } else {
                        HStack(spacing: 4 * s) {
                            Text(session.isCall ? "On Call" : "Mic")
                            Text(session.startDate, style: .timer)
                                .monospacedDigit()
                        }
                        .font(.system(size: (compact ? 10.5 : 11) * s, weight: .medium))
                        .foregroundStyle(tint)
                    }
                }
                .lineLimit(1)
            }
            if compact {
                HStack(spacing: 6 * s) {
                    title
                    Spacer(minLength: 4 * s)
                    buttons(session, size: 28 * s)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    title
                        .padding(.trailing, 12 * s)
                    Spacer(minLength: 6 * s)
                    HStack(spacing: 8 * s) {
                        if session.usesCamera {
                            Image(systemName: "video.fill")
                                .font(.system(size: 11 * s, weight: .semibold))
                                .foregroundStyle(NotchColor.green)
                                .accessibilityLabel(Text("Camera in use"))
                        }
                        Spacer(minLength: 0)
                        buttons(session, size: 34 * s)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func buttons(_ session: CallMonitor.Session, size: CGFloat) -> some View {
        let tint = session.isCall ? NotchColor.green : NotchColor.orange
        if model.microphone.canMute {
            let muted = model.microphone.isMuted
            CircleButton(
                symbol: muted ? "mic.slash.fill" : "mic.fill",
                size: size,
                foreground: muted ? .white : NotchColor.orange,
                background: muted ? NotchColor.red : NotchColor.orange.opacity(0.22),
                label: muted ? "Unmute Microphone" : "Mute Microphone"
            ) { model.microphone.toggle() }
        }
        if model.calls.canHangUp {
            CircleButton(symbol: "phone.down.fill", size: size, foreground: .white, background: NotchColor.red, label: "Hang Up") {
                Task { @MainActor in
                    if await model.calls.hangUp() == .sent { model.collapse() }
                }
            }
            .help(CallHangup.shortcut(for: session.bundleIdentifier)?.asksToConfirm == true
                  ? "Leave the call (\(session.appName) asks you to confirm)"
                  : "Hang up")
        } else if !compact || !model.microphone.canMute {
            CircleButton(symbol: "arrow.up.forward", size: size, foreground: .white, background: tint, label: "Show \(session.appName)") {
                model.calls.showApp()
                model.collapse()
            }
        }
    }
}

private struct LiveTimer: View {
    let model: IslandModel

    var body: some View {
        if let timer = model.timer.timer {
            LiveClock(
                symbol: timer.mode.symbol,
                title: timer.mode.title,
                isPaused: timer.isPaused,
                pauseLabel: timer.isPaused ? "Resume Timer" : "Pause Timer",
                cancelLabel: "Cancel Timer",
                togglePause: { model.timer.togglePause() },
                cancel: { model.cancelTimer() }
            ) {
                CountdownText(timer: timer)
            }
        }
    }
}

private struct LiveStopwatch: View {
    let model: IslandModel

    var body: some View {
        let isRunning = model.stopwatch.stopwatch?.isRunning == true
        LiveClock(
            symbol: "stopwatch",
            title: "Stopwatch",
            isPaused: !isRunning,
            pauseLabel: isRunning ? "Pause Stopwatch" : "Resume Stopwatch",
            cancelLabel: "Reset Stopwatch",
            togglePause: { model.stopwatch.togglePause() },
            cancel: { model.resetStopwatch() }
        ) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !isRunning)) { context in
                Text(StopwatchFormat.text(model.stopwatch.elapsed(at: context.date)))
            }
        }
    }
}

/// A running clock in one row: its name and time, then cancel and pause.
private struct LiveClock<Clock: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let isPaused: Bool
    let pauseLabel: LocalizedStringKey
    let cancelLabel: LocalizedStringKey
    let togglePause: () -> Void
    let cancel: () -> Void
    @ViewBuilder var clock: Clock
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            VStack(alignment: .leading, spacing: 0) {
                // Beside a live card the section is narrow; the symbol alone is enough.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4 * s) {
                        Image(systemName: symbol)
                        Text(title)
                    }
                    Image(systemName: symbol)
                }
                .font(.system(size: 10 * s, weight: .semibold))
                .foregroundStyle(NotchColor.secondaryText)
                .lineLimit(1)
                clock
                    .font(.system(size: 18 * s, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchColor.orange.opacity(isPaused ? 0.6 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2 * s)
            CircleButton(symbol: "xmark", size: 26 * s, foreground: .white, background: NotchColor.buttonFill, label: cancelLabel, action: cancel)
            CircleButton(
                symbol: isPaused ? "play.fill" : "pause.fill",
                size: 26 * s,
                foreground: NotchColor.orange,
                background: NotchColor.orange.opacity(0.22),
                label: pauseLabel,
                action: togglePause
            )
        }
    }
}

/// Artwork, title and the transport controls. Compact keeps play and next beside the title.
private struct LiveMusic: View {
    let service: NowPlayingService
    /// Shown as one line under the title when the song has timed lyrics.
    let lyrics: SyncedLyrics?
    let timingAdjustment: TimeInterval
    let compact: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        let playPause = GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: (compact ? 14 : 17) * s, label: info?.isPlaying == true ? "Pause" : "Play") {
            service.togglePlayPause()
        }
        let next = GlyphButton(symbol: "forward.fill", size: 12 * s, label: "Next Track") { service.nextTrack() }
        let title = HStack(spacing: 8 * s) {
            Button { service.openSourceApp() } label: {
                ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon, size: (compact ? 26 : 40) * s, cornerRadius: (compact ? 6 : 9) * s)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Open player"))
            VStack(alignment: .leading, spacing: (compact ? 0 : 2) * s) {
                Text(info?.title ?? "")
                    .font(.system(size: (compact ? 12 : 12.5) * s, weight: .semibold))
                    .foregroundStyle(.white)
                Text(info?.artist.isEmpty == false ? info?.artist ?? "" : service.appName ?? "")
                    .font(.system(size: 10.5 * s))
                    .foregroundStyle(NotchColor.secondaryText)
            }
            .lineLimit(1)
        }
        if compact {
            HStack(spacing: 2 * s) {
                title
                Spacer(minLength: 2 * s)
                playPause
                next
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                title
                    .padding(.trailing, 12 * s)
                if let lyrics {
                    LyricsLine(lyrics: lyrics, service: service, size: 11 * s, timingAdjustment: timingAdjustment, alignment: .leading)
                        .frame(height: 16 * s)
                        .padding(.top, 4 * s)
                }
                Spacer(minLength: 4 * s)
                MiniProgress(service: service)
                    .frame(height: 3 * s)
                HStack(spacing: 16 * s) {
                    GlyphButton(symbol: "backward.fill", size: 12 * s, label: "Previous Track") { service.previousTrack() }
                    playPause
                    next
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4 * s)
            }
        }
    }
}

// MARK: Timer

/// "Timer ›" opens the full timer; the capsules start one straight away.
private struct TimerSection: View {
    let model: IslandModel
    let compact: Bool
    var showsHeader = true
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            if showsHeader {
                Button {
                    model.timerPanelMode = .timer
                    model.showTab(.timers)
                } label: {
                    SectionHeader(symbol: "timer", tint: NotchColor.orange, title: "Timer", showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Any length, Pomodoro or Stopwatch")
                .accessibilityLabel(Text("Timer"))
            }
            HStack(spacing: 6 * s) {
                ForEach(TimerService.presets.prefix(3), id: \.self) { preset in
                    Button("\(Int(preset / 60))m") { model.startTimer(preset) }
                        .buttonStyle(QuickActionStyle(tint: NotchColor.orange, scale: s, width: 38 * s))
                        .accessibilityLabel(Text("Start \(TimeFormatting.spoken(preset)) timer"))
                }
            }
            if !compact {
                Button {
                    model.startSession(.focus)
                } label: {
                    Label("Focus \(model.settings.focusMinutes)m", systemImage: TimerMode.focus.symbol)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(QuickActionStyle(tint: NotchColor.orange, scale: s))
                .help("Focus for \(model.settings.focusMinutes) minutes, then take a \(model.settings.breakMinutes) minute break")
                .accessibilityLabel(Text("Start a \(model.settings.focusMinutes) minute focus session"))
            }
        }
    }
}

// MARK: Shortcuts

/// The favourite shortcuts, one tap to run. Compact shows only the first.
private struct ShortcutsSection: View {
    let model: IslandModel
    let compact: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            SectionHeader(symbol: "bolt.fill", tint: NotchColor.blue, title: "Shortcuts")
            ForEach(model.favoriteShortcuts.prefix(compact ? 1 : 3), id: \.self) { name in
                let isRunning = model.shortcuts.running.contains(name)
                Button {
                    model.shortcuts.run(name)
                } label: {
                    HStack(spacing: 5 * s) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(name)
                            .truncationMode(.tail)
                            .frame(maxWidth: 112 * s, alignment: .leading)
                    }
                }
                .buttonStyle(QuickActionStyle(tint: NotchColor.blue, scale: s))
                .disabled(isRunning)
                .help(name)
                .accessibilityLabel(Text("Run shortcut \(name)"))
            }
        }
    }
}
