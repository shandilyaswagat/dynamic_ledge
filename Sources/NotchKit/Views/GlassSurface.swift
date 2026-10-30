import AppKit
import SwiftUI

/// The Glass theme's surface: the same shapes as `IslandSurface`, made of frosted glass instead
/// of black. The band around the camera stays black and fades into the glass, so the notch
/// hardware never shows through and the glass seems to pour out of it.
struct GlassSurface: View, Animatable {
    var layout: IslandLayout
    /// 0 clear … 1 fully tinted.
    var tint: Double

    nonisolated var animatableData: AnimatableVector {
        get { layout.animatableData }
        set { layout.animatableData = newValue }
    }

    var body: some View {
        let opacity = min(1, layout.pillOpacity * 20)
        let hasBubble = layout.bubble.width > 0.5 && layout.bubble.height > 0.5
        ZStack(alignment: .topLeading) {
            if opacity > 0.001 || hasBubble {
                glass(hasBubble: hasBubble)
                    .opacity(opacity > 0.001 ? 1 : 0)
                notchBand
                    .opacity(opacity)
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pillShape: IslandShape {
        IslandShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius, flare: layout.flare)
    }

    /// How dark the glass is: never fully clear, so white text stays readable.
    private var tintOpacity: Double { 0.12 + 0.68 * tint }

    @ViewBuilder
    private func glass(hasBubble: Bool) -> some View {
        if #available(macOS 26.0, *) {
            // Liquid Glass: the pill and the bubble melt into each other as they separate.
            GlassEffectContainer(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .glassEffect(.regular.tint(.black.opacity(tintOpacity)), in: pillShape)
                        .placed(in: layout.pill)
                    if hasBubble {
                        Color.clear
                            .glassEffect(.regular.tint(.black.opacity(tintOpacity)), in: Circle())
                            .placed(in: layout.bubble)
                    }
                }
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
            }
        } else {
            ZStack(alignment: .topLeading) {
                FrostedGlass(tintOpacity: tintOpacity, shape: pillShape)
                    .placed(in: layout.pill)
                if hasBubble {
                    FrostedGlass(tintOpacity: tintOpacity, shape: Circle())
                        .placed(in: layout.bubble)
                }
            }
        }
    }

    /// Black over the camera housing, fading into the glass just below it.
    private var notchBand: some View {
        let band = layout.notchBand
        let fade: CGFloat = 12
        let height = max(layout.pill.height, 1)
        return pillShape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: min(1, band / height)),
                        .init(color: .black.opacity(0), location: min(1, (band + fade) / height)),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .placed(in: layout.pill)
            .opacity(band > 0 ? 1 : 0)
    }
}

/// Before Liquid Glass (macOS 14 and 15): the window's blurred backdrop, tinted, with a thin
/// light edge so the shape still reads as glass.
private struct FrostedGlass<S: Shape>: View {
    var tintOpacity: Double
    var shape: S

    var body: some View {
        BackdropBlur()
            .overlay(Color.black.opacity(tintOpacity))
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8
                )
            }
    }
}

/// Blurs whatever is behind the window. Always "active": the notch's panel never becomes the key
/// window, and an inactive backdrop turns flat grey.
private struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private extension View {
    /// Sizes the view to `rect` and puts it there, in a top-left-aligned container.
    func placed(in rect: CGRect) -> some View {
        frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .padding(.leading, rect.minX)
            .padding(.top, rect.minY)
    }
}
