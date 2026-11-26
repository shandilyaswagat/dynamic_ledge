import SwiftUI

struct HomeDashboardEditor<Preview: View>: View {
    let model: IslandModel
    let layout: HomeDashboardLayout
    let preview: (HomeDashboardWidget) -> Preview
    @Environment(\.notchScale) private var s
    @State private var targetSlot: Int?

    private var gap: CGFloat { IslandMetrics.Nook.dashboardGap * s }
    private var cardHeight: CGFloat { IslandMetrics.Nook.body * s }

    @ViewBuilder
    var body: some View {
        if let targetSlot {
            cardPicker(for: targetSlot)
        } else {
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 7 * s) {
            GeometryReader { geometry in
                let width = max(1, (geometry.size.width - 2 * gap) / CGFloat(HomeDashboardLayout.columns))
                let columns = Array(repeating: GridItem(.fixed(width), spacing: gap), count: HomeDashboardLayout.columns)
                LazyVGrid(columns: columns, spacing: gap) {
                    ForEach(layout.slots.indices, id: \.self) { index in
                        slot(at: index, width: width)
                    }
                }
                .animation(.smooth(duration: 0.22), value: layout)
            }
            .frame(height: 2 * cardHeight + gap)
            HStack {
                Text("Drag cards between slots")
                    .foregroundStyle(NotchColor.secondaryText)
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
                onRemove: { model.updateHomeDashboard { $0.set(nil, at: index) } },
                onMove: { horizontal, vertical in
                    model.updateHomeDashboard { $0.move(from: index, horizontal: horizontal, vertical: vertical) }
                }
            ) {
                preview(widget)
            }
            .frame(width: width, height: cardHeight)
        } else {
            Button {
                targetSlot = index
            } label: {
                Label("Add Card", systemImage: "plus")
                    .font(.system(size: 12 * s, weight: .semibold))
                    .frame(width: width, height: cardHeight)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14 * s))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14 * s)
                            .strokeBorder(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Add Card"))
            .accessibilityHint(Text("Row \(index / HomeDashboardLayout.columns + 1), column \(index % HomeDashboardLayout.columns + 1)"))
        }
    }

    private func cardPicker(for index: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: HomeDashboardLayout.columns)
        return VStack(alignment: .leading, spacing: 7 * s) {
            HStack {
                Text("Choose a card")
                    .font(.system(size: 12 * s, weight: .semibold))
                Spacer()
                Button("Cancel") { targetSlot = nil }
                    .buttonStyle(PressableButtonStyle())
                    .font(.system(size: 11 * s))
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: gap) {
                    ForEach(HomeDashboardWidget.allCases.filter { !layout.widgets.contains($0) }) { widget in
                        Button {
                            model.updateHomeDashboard { $0.set(widget, at: index) }
                            targetSlot = nil
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
    let onRemove: () -> Void
    let onMove: (Int, Int) -> Void
    @ViewBuilder let preview: () -> Preview
    @Environment(\.notchScale) private var s
    @GestureState private var translation: CGSize = .zero

    var body: some View {
        preview()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                RoundedRectangle(cornerRadius: 14 * s)
                    .strokeBorder(Color.white.opacity(translation == .zero ? 0.14 : 0.50), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .global)
                            .updating($translation) { value, offset, _ in offset = value.translation }
                            .onEnded { value in
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
            .offset(x: translation.width, y: translation.height)
            .zIndex(translation == .zero ? 0 : 1)
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
