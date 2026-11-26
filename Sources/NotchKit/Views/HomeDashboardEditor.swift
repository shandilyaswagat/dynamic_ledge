import SwiftUI

struct HomeDashboardEditor<Preview: View>: View {
    let model: IslandModel
    let layout: HomeDashboardLayout
    let preview: (HomeDashboardWidget) -> Preview
    @Environment(\.notchScale) private var s

    private var gap: CGFloat { IslandMetrics.Nook.dashboardGap * s }
    private var cardHeight: CGFloat { IslandMetrics.Nook.body * s }

    @ViewBuilder
    var body: some View {
        if case .choosing(let slot) = model.homeDashboardEditorMode {
            cardPicker(for: slot)
        } else {
            editor
        }
    }

    private var editor: some View {
        let rows = model.homeDashboardRows
        return VStack(spacing: 7 * s) {
            GeometryReader { geometry in
                let width = max(1, (geometry.size.width - 2 * gap) / CGFloat(HomeDashboardLayout.columns))
                let columns = Array(repeating: GridItem(.fixed(width), spacing: gap), count: HomeDashboardLayout.columns)
                LazyVGrid(columns: columns, spacing: gap) {
                    ForEach(0..<(rows * HomeDashboardLayout.columns), id: \.self) { index in
                        slot(at: index, width: width)
                    }
                }
                .animation(.smooth(duration: 0.22), value: layout)
            }
            .frame(height: CGFloat(rows) * cardHeight + CGFloat(rows - 1) * gap)
            HStack {
                if let firstEmpty = layout.slots.firstIndex(of: nil) {
                    Button {
                        model.setHomeDashboardEditorMode(.choosing(slot: firstEmpty))
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
    }

    @ViewBuilder
    private func slot(at index: Int, width: CGFloat) -> some View {
        if let widget = layout.slots[index] {
            HomeDashboardDraggableCard(
                widget: widget,
                step: CGSize(width: width + gap, height: cardHeight + gap),
                onDragChange: { model.setHomeDashboardDragging($0) },
                onRemove: { model.updateHomeDashboard { $0.set(nil, at: index) } },
                onMove: { horizontal, vertical in
                    model.updateHomeDashboard { $0.move(from: index, horizontal: horizontal, vertical: vertical) }
                }
            ) {
                preview(widget)
            }
            .frame(width: width, height: cardHeight)
        } else {
            Color.clear
                .overlay {
                    if model.homeDashboardEditorMode == .dragging {
                        RoundedRectangle(cornerRadius: 14 * s)
                            .strokeBorder(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(width: width, height: cardHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func cardPicker(for index: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: HomeDashboardLayout.columns)
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
                            model.updateHomeDashboard { $0.set(widget, at: index) }
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

private struct HomeDashboardDraggableCard<Preview: View>: View {
    let widget: HomeDashboardWidget
    let step: CGSize
    let onDragChange: (Bool) -> Void
    let onRemove: () -> Void
    let onMove: (Int, Int) -> Void
    @ViewBuilder let preview: () -> Preview
    @Environment(\.notchScale) private var s
    @GestureState private var translation: CGSize?

    var body: some View {
        preview()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                RoundedRectangle(cornerRadius: 14 * s)
                    .strokeBorder(Color.white.opacity(translation == nil ? 0.14 : 0.50), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .global)
                            .updating($translation) { value, offset, _ in offset = value.translation }
                            .onEnded { value in
                                onDragChange(false)
                                onMove(Int((value.translation.width / step.width).rounded()),
                                       Int((value.translation.height / step.height).rounded()))
                            }
                    )
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15 * s, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, NotchColor.red)
                        .frame(width: 27 * s, height: 27 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Remove \(Text(widget.title))"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(widget.title))
            .accessibilityAction(named: Text("Move left")) { onMove(-1, 0) }
            .accessibilityAction(named: Text("Move right")) { onMove(1, 0) }
            .accessibilityAction(named: Text("Move up")) { onMove(0, -1) }
            .accessibilityAction(named: Text("Move down")) { onMove(0, 1) }
            .offset(x: translation?.width ?? 0, y: translation?.height ?? 0)
            .zIndex(translation == nil ? 0 : 1)
            .onChange(of: translation != nil) { _, isDragging in onDragChange(isDragging) }
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
