import SwiftUI

private let homeDashboardGridSpace = "homeDashboardGrid"

private struct HomeDashboardDrag: Equatable {
    let widget: HomeDashboardWidget
    /// Where in the card the pointer took hold, so the card doesn't jump under it.
    let grab: CGSize
    let location: CGPoint

    /// The nearest grid cell to the card's top-left corner.
    func destination(columnPitch: CGFloat, rowPitch: CGFloat) -> CGPoint {
        CGPoint(x: ((location.x - grab.width) / columnPitch).rounded(),
                y: ((location.y - grab.height) / rowPitch).rounded())
    }
}

private struct HomeDashboardResize: Equatable {
    /// The card at the size its dragged edges ask for, snapped to the grid.
    let card: HomeDashboardCard
    /// The same, unsnapped: the held card is drawn here, following the pointer.
    let rect: CGRect
    let initialCard: HomeDashboardCard
    let initialGridFrame: CGRect
}

struct HomeDashboardEditor<Preview: View>: View {
    let model: IslandModel
    let layout: HomeDashboardLayout
    let preview: (HomeDashboardWidget) -> Preview
    @Environment(\.notchScale) private var s
    @GestureState private var drag: HomeDashboardDrag?
    @GestureState private var resizing: HomeDashboardResize?
    /// The layout as it was when the card was picked up. Every step of a drag is worked out
    /// from it, so cards pushed aside go back once the held card moves on.
    @State private var start: HomeDashboardLayout?

    private var gap: CGFloat { IslandMetrics.Nook.dashboardGap * s }
    private var cardHeight: CGFloat { IslandMetrics.Nook.body * s }
    private var isAdjusting: Bool { drag != nil || resizing != nil }

    @ViewBuilder
    var body: some View {
        if model.homeDashboardEditorMode == .choosing {
            cardPicker
        } else {
            editor
        }
    }

    private var editor: some View {
        let rowCount = model.homeDashboardRows
        return VStack(spacing: 7 * s) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let unit = (width - CGFloat(HomeDashboardLayout.columns - 1) * gap) / CGFloat(HomeDashboardLayout.columns)
                let frames = layout.frames(in: width, rowHeight: cardHeight, gap: gap, presentation: .editor)
                ZStack(alignment: .topLeading) {
                    if isAdjusting {
                        cells(unit: unit)
                        if let widget = drag?.widget ?? resizing?.card.widget, let frame = frames[widget] {
                            dropTarget(frame)
                        }
                    }
                    ForEach(layout.widgets) { widget in
                        if let frame = frames[widget] {
                            card(widget, frame: frame, unit: unit, gridWidth: width)
                        }
                    }
                }
                .frame(width: width, height: geometry.size.height, alignment: .topLeading)
                .coordinateSpace(name: homeDashboardGridSpace)
                .animation(.smooth(duration: 0.22), value: layout)
                .animation(.smooth(duration: 0.22), value: isAdjusting)
                .onChange(of: drag) { old, drag in
                    guard let drag else { return }
                    let columnPitch = unit + gap
                    let rowPitch = cardHeight + gap
                    let target = drag.destination(columnPitch: columnPitch, rowPitch: rowPitch)
                    guard old?.destination(columnPitch: columnPitch, rowPitch: rowPitch) != target else { return }
                    adjust(fromStart: old == nil) { $0.move(drag.widget, toColumn: Int(target.x), row: Int(target.y)) }
                }
                .onChange(of: resizing) { old, resizing in
                    guard let resizing, old?.card != resizing.card else { return }
                    adjust(fromStart: old == nil) { next in
                        if next.place(resizing.card) { return true }
                        // Blocked one way, the card still follows the other.
                        guard let current = layout.card(for: resizing.card.widget) else { return false }
                        var wider = resizing.card, taller = resizing.card
                        (wider.row, wider.height) = (current.row, current.height)
                        (taller.column, taller.width) = (current.column, current.width)
                        return next.place(wider) || next.place(taller)
                    }
                }
            }
            .frame(height: CGFloat(rowCount) * cardHeight + CGFloat(rowCount - 1) * gap)
            HStack {
                if layout.hasRoom {
                    Button {
                        model.setHomeDashboardEditorMode(.choosing)
                    } label: {
                        Label("Add Card", systemImage: "plus")
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                Spacer()
                Button("Reset to Automatic") { model.resetHomeDashboard() }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(model.settings.homeDashboard == nil)
            }
            .font(.system(size: 11 * s, weight: .medium))
        }
        .onChange(of: isAdjusting) { _, isAdjusting in model.setHomeDashboardDragging(isAdjusting) }
    }

    /// Applies one step of a drag to the layout the drag began with. A step with no room for
    /// it leaves the last one that worked.
    private func adjust(fromStart isFirst: Bool, _ change: (inout HomeDashboardLayout) -> Bool) {
        var next = isFirst ? layout : start ?? layout
        if isFirst { start = layout }
        if change(&next) {
            model.updateHomeDashboard { $0 = next }
        }
    }

    /// The grid itself, shown while a card is moved or resized.
    private func cells(unit: CGFloat) -> some View {
        ForEach(0..<(HomeDashboardLayout.columns * HomeDashboardLayout.rows), id: \.self) { index in
            RoundedRectangle(cornerRadius: 12 * s)
                .fill(.white.opacity(0.035))
                .frame(width: unit, height: cardHeight)
                .position(x: CGFloat(index % HomeDashboardLayout.columns) * (unit + gap) + unit / 2,
                          y: CGFloat(index / HomeDashboardLayout.columns) * (cardHeight + gap) + cardHeight / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func dropTarget(_ frame: CGRect) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
        return shape
            .fill(NotchColor.blue.opacity(0.14))
            .overlay { shape.strokeBorder(NotchColor.blue.opacity(0.65), lineWidth: 1) }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A strip along one edge of a card that drags that edge to the nearest grid line.
    @ViewBuilder
    private func edge(_ edge: Edge, of card: HomeDashboardCard?, gridFrame: CGRect, unit: CGFloat, gridWidth: CGFloat) -> some View {
        let isSide = edge == .leading || edge == .trailing
        // Clear of the corners, where the remove button and the resize handle sit.
        Color.clear
            .frame(width: isSide ? 12 * s : nil, height: isSide ? nil : 12 * s)
            .padding(isSide ? .vertical : .horizontal, 30 * s)
            .contentShape(Rectangle())
            .gesture(resizeGesture(Edge.Set(edge), of: card, gridFrame: gridFrame, unit: unit, gridWidth: gridWidth))
            .onHover { inside in
                // Set rather than pushed: a strip that goes away mid-hover never gets to pop.
                (inside ? (isSide ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown) : NSCursor.arrow).set()
            }
            .accessibilityHidden(true)
    }

    private func grip(vertical: Bool) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.45))
            .frame(width: (vertical ? 3 : 22) * s, height: (vertical ? 22 : 3) * s)
            .padding(3 * s)
            .allowsHitTesting(false)
    }

    private func resizeGesture(_ edges: Edge.Set, of card: HomeDashboardCard?, gridFrame: CGRect, unit: CGFloat, gridWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(homeDashboardGridSpace))
            .updating($resizing) { value, state, _ in
                guard let initialCard = state?.initialCard ?? card else { return }
                let frame = state?.initialGridFrame ?? gridFrame
                let dx = value.translation.width, dy = value.translation.height
                let minimumWidth = CGFloat(HomeDashboardLayout.minimumWidth) * (unit + gap) - gap
                let gridHeight = CGFloat(HomeDashboardLayout.rows) * (cardHeight + gap) - gap
                var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
                var left = initialCard.column, right = initialCard.columns.upperBound
                var top = initialCard.row, bottom = initialCard.rows.upperBound
                if edges.contains(.trailing) {
                    maxX = min(max(frame.maxX + dx, minX + minimumWidth), gridWidth)
                    right = min(max(Int(((maxX + gap) / (unit + gap)).rounded()), left + HomeDashboardLayout.minimumWidth), HomeDashboardLayout.columns)
                }
                if edges.contains(.leading) {
                    minX = max(min(frame.minX + dx, maxX - minimumWidth), 0)
                    left = max(min(Int((minX / (unit + gap)).rounded()), right - HomeDashboardLayout.minimumWidth), 0)
                }
                if edges.contains(.bottom) {
                    maxY = min(max(frame.maxY + dy, minY + cardHeight), gridHeight)
                    bottom = min(max(Int(((maxY + gap) / (cardHeight + gap)).rounded()), top + 1), HomeDashboardLayout.rows)
                }
                if edges.contains(.top) {
                    minY = max(min(frame.minY + dy, maxY - cardHeight), 0)
                    top = max(min(Int((minY / (cardHeight + gap)).rounded()), bottom - 1), 0)
                }
                state = HomeDashboardResize(
                    card: HomeDashboardCard(widget: initialCard.widget, column: left, row: top, width: right - left, height: bottom - top),
                    rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                    initialCard: initialCard,
                    initialGridFrame: frame)
            }
    }

    private func card(_ widget: HomeDashboardWidget, frame slot: CGRect, unit: CGFloat, gridWidth: CGFloat) -> some View {
        let dragged = drag?.widget == widget ? drag : nil
        let resized = resizing?.card.widget == widget ? resizing : nil
        let isHeld = dragged != nil || resized != nil
        let shape = RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
        // A card being resized is drawn where the pointer has its edges, not where they'll snap to.
        let frame = resized?.rect ?? slot
        let origin = dragged.map { CGPoint(x: $0.location.x - $0.grab.width, y: $0.location.y - $0.grab.height) } ?? frame.origin
        let size = layout.card(for: widget)
        let step: (Int, Int) -> Void = { horizontal, vertical in
            guard let size else { return }
            model.updateHomeDashboard { $0.move(widget, toColumn: size.column + horizontal, row: size.row + vertical) }
        }
        let grow: (Int, Int) -> Void = { wider, taller in
            guard let size else { return }
            model.updateHomeDashboard { $0.resize(widget, width: size.width + wider, height: size.height + taller) }
        }
        return preview(widget)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                if isHeld {
                    shape.fill(Color(white: 0.10))
                        .shadow(color: .black.opacity(0.55), radius: 14 * s, y: 6 * s)
                }
            }
            .overlay {
                shape
                    .strokeBorder(isHeld ? NotchColor.blue.opacity(0.85) : .white.opacity(0.11), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named(homeDashboardGridSpace))
                            .updating($drag) { value, state, _ in
                                let grab = state?.grab ?? CGSize(width: value.startLocation.x - slot.minX, height: value.startLocation.y - slot.minY)
                                state = HomeDashboardDrag(widget: widget, grab: grab, location: value.location)
                            }
                    )
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    model.updateHomeDashboard { $0.remove(widget) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, NotchColor.red)
                        .frame(width: 27 * s, height: 27 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .opacity(isAdjusting ? 0 : 0.85)
                .allowsHitTesting(!isAdjusting)
                .accessibilityLabel(Text("Remove \(Text(widget.title))"))
            }
            // Every edge resizes; the grips mark the two most reached for.
            .overlay(alignment: .leading) { edge(.leading, of: size, gridFrame: slot, unit: unit, gridWidth: gridWidth) }
            .overlay(alignment: .top) { edge(.top, of: size, gridFrame: slot, unit: unit, gridWidth: gridWidth) }
            .overlay(alignment: .trailing) {
                edge(.trailing, of: size, gridFrame: slot, unit: unit, gridWidth: gridWidth)
                    .overlay(alignment: .trailing) { grip(vertical: true) }
            }
            .overlay(alignment: .bottom) {
                edge(.bottom, of: size, gridFrame: slot, unit: unit, gridWidth: gridWidth)
                    .overlay(alignment: .bottom) { grip(vertical: false) }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19 * s, height: 19 * s)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(resizing?.card.widget == widget ? 0.6 : 0.22), lineWidth: 1) }
                    .padding(5 * s)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture([.trailing, .bottom], of: size, gridFrame: slot, unit: unit, gridWidth: gridWidth))
                    .help("Drag to resize")
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(widget.title))
            .accessibilityAction(named: Text("Move left")) { step(-1, 0) }
            .accessibilityAction(named: Text("Move right")) { step(1, 0) }
            .accessibilityAction(named: Text("Move up")) { step(0, -1) }
            .accessibilityAction(named: Text("Move down")) { step(0, 1) }
            .accessibilityAction(named: Text("Wider")) { grow(1, 0) }
            .accessibilityAction(named: Text("Narrower")) { grow(-1, 0) }
            .accessibilityAction(named: Text("Taller")) { grow(0, 1) }
            .accessibilityAction(named: Text("Shorter")) { grow(0, -1) }
            .frame(width: frame.width, height: frame.height)
            .position(x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
            .zIndex(isHeld ? 1 : 0)
            // The held card tracks the pointer exactly; only the others glide into place.
            .transaction { if isHeld { $0.animation = nil } }
    }

    private var cardPicker: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: 3)
        return VStack(alignment: .leading, spacing: 7 * s) {
            HStack {
                Text("Choose a card")
                    .font(.system(size: 12 * s, weight: .semibold))
                Spacer()
                Button("Cancel") { model.setHomeDashboardEditorMode(.arranging) }
                    .buttonStyle(PressableButtonStyle())
                    .font(.system(size: 11 * s))
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: gap) {
                    ForEach(HomeDashboardWidget.allCases.filter { !layout.widgets.contains($0) }) { widget in
                        Button {
                            model.updateHomeDashboard { $0.add(widget) }
                            model.setHomeDashboardEditorMode(.arranging)
                        } label: {
                            preview(widget)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16 * s, weight: .medium))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, NotchColor.blue)
                                        .padding(6 * s)
                                        .accessibilityHidden(true)
                                }
                                .frame(height: cardHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel(Text("Add \(Text(widget.title))"))
                    }
                }
            }
        }
    }
}

extension HomeDashboardWidget {
    var title: LocalizedStringKey {
        switch self {
        case .music: "Now Playing"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .shortcuts: "Shortcuts"
        case .stats: "Stats"
        case .bluetooth: "Bluetooth"
        case .aiUsage: "AI Agent Usage"
        }
    }

    var symbol: String {
        switch self {
        case .music: LauncherItem.nowPlaying.symbolName
        case .calendar: LauncherItem.calendar.symbolName
        case .timer: LauncherItem.timer.symbolName
        case .shortcuts: "bolt.fill"
        case .stats: LauncherItem.stats.symbolName
        case .bluetooth: LauncherItem.bluetooth.symbolName
        case .aiUsage: LauncherItem.aiUsage.symbolName
        }
    }
}
