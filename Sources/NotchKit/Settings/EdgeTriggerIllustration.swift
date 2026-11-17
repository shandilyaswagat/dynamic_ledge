import SwiftUI

struct NotchOpeningPreview<Decoration: View>: View {
    let isSelected: Bool
    @ViewBuilder let decoration: () -> Decoration

    var body: some View {
        let screen = RoundedRectangle(cornerRadius: 10, style: .continuous)
        screen
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            .overlay(screen.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                         lineWidth: isSelected ? 2.5 : 1))
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4)
            .aspectRatio(140.0 / 86.0, contentMode: .fit)
            .overlay { decoration() }
            .accessibilityHidden(true)
    }
}

/// A screen diagram with an arrow pointing to the active edge.
struct EdgeTriggerIllustration: View {
    let edge: HomeEdgeTrigger.Edge
    let isEnabled: Bool

    private var alignment: Alignment {
        switch edge {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .topCenter: .top
        case .bottomCenter: .bottom
        }
    }

    private var arrow: String {
        switch edge {
        case .topLeft: "arrow.up.left"
        case .topRight: "arrow.up.right"
        case .topCenter: "arrow.up"
        case .bottomCenter: "arrow.down"
        }
    }

    var body: some View {
        NotchOpeningPreview(isSelected: isEnabled) {
            Color.clear
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.48))
                        .frame(width: 24, height: 5)
                        .padding(.top, 3)
                }
                .overlay(alignment: alignment) {
                    if edge == .bottomCenter || edge == .topCenter {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 24, height: 4)
                            .padding(.bottom, 5)
                            .padding(.top, edge == .topCenter ? 3 : 0)
                    } else {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                            .padding(7)
                    }
                }
                .overlay(alignment: alignment) {
                    Image(systemName: arrow)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, edge == .topLeft ? 19 : 0)
                        .padding(.trailing, edge == .topRight ? 19 : 0)
                        .padding(.top, edge == .bottomCenter ? 0 : 17)
                        .padding(.bottom, edge == .bottomCenter ? 14 : 0)
                }
        }
    }
}
