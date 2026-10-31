import AppKit
import SwiftUI

/// The Glass theme's surface: the same shapes as `IslandSurface`, made of glass instead of black.
/// Like a slab of smoked glass under the notch: near black for most of its height (so the camera
/// never shows and the content reads like it does on black), then a soft fade into lighter,
/// frosted glass along the bottom, whose edge catches the light.
struct GlassSurface: View, Animatable {
    var layout: IslandLayout
    /// 0 clear … 1 fully tinted: how dark the glass stays at the bottom.
    var tint: Double

    nonisolated var animatableData: AnimatableVector {
        get { layout.animatableData }
        set { layout.animatableData = newValue }
    }

    var body: some View {
        let opacity = min(1, layout.pillOpacity * 20)
        let hasBubble = layout.bubble.width > 0.5 && layout.bubble.height > 0.5
        let amount = glassAmount
        ZStack(alignment: .topLeading) {
            if opacity > 0.001 {
                if amount > 0.001 {
                    glass
                        .opacity(amount)
                    ZStack(alignment: .topLeading) {
                        smoke
                        rim
                    }
                    .opacity(opacity * amount)
                }
                // The closed notch, its activities and short alerts stay plain black: glass edges
                // there would draw a light line around the camera.
                if amount < 0.999 {
                    pillShape
                        .fill(Color.black.opacity(opacity * (1 - amount)))
                        .placed(in: layout.pill)
                }
            }
            if hasBubble {
                Circle()
                    .fill(Color.black)
                    .placed(in: layout.bubble)
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pillShape: IslandShape {
        IslandShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius, flare: layout.flare)
    }

    /// 0 while the shape is about notch-sized (closed, an activity, a short alert), rising to 1 as
    /// it opens, so the glass grows in with the opening instead of switching on.
    private var glassAmount: Double {
        let closed = max(layout.notchBand, 32) + 14
        return min(max((layout.pill.height - closed) / 44, 0), 1)
    }

    /// Darkness left at the bottom edge. Never fully clear, so white text stays readable.
    private var bottomShade: Double { 0.08 + 0.5 * tint }
    /// How dark the body is above the fade.
    private static let bodyShade = 0.93
    /// Where the fade starts, as a share of the height: the last stretch is the frosted lip.
    private static let fadeStart = 0.62

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            // Liquid Glass: frosts and brightens what's behind, and bends it at the edges.
            Color.clear
                .glassEffect(.regular, in: pillShape)
                .placed(in: layout.pill)
        } else {
            FrostedGlass(shape: pillShape)
                .placed(in: layout.pill)
        }
    }

    /// Black over the camera and through the body, then an eased fade to the bottom shade, with
    /// a faint light lip at the very bottom. No visible edges anywhere.
    private var smoke: some View {
        let height = max(layout.pill.height, 1)
        let band = min(1, layout.notchBand / height)
        let start = max(band, Self.fadeStart)
        let bottom = bottomShade
        var stops: [Gradient.Stop] = [
            .init(color: .black, location: 0),
            .init(color: .black, location: band),
            .init(color: .black.opacity(Self.bodyShade), location: min(1, band + 0.08)),
            .init(color: .black.opacity(Self.bodyShade), location: start),
        ]
        for step in 1...6 {
            let t = Double(step) / 6
            // Smoothstep, so the fade has no corner where it starts or ends.
            let eased = t * t * (3 - 2 * t)
            stops.append(.init(color: .black.opacity(Self.bodyShade - (Self.bodyShade - bottom) * eased), location: start + (1 - start) * t))
        }
        // Gradient views clipped by the shape, rather than a shape filled with a gradient: the
        // graphics card draws these as the shape changes every frame, instead of the CPU.
        return ZStack {
            LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0), location: 0.82),
                    .init(color: .white.opacity(0.16), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(pillShape)
        .placed(in: layout.pill)
    }

    /// A thin light edge, invisible against the black at the top and brightest along the
    /// bottom, where real glass catches the light.
    private var rim: some View {
        let height = max(layout.pill.height, 1)
        let band = min(1, (layout.notchBand + 8) / height)
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: band),
                .init(color: .white.opacity(0.08), location: max(band, Self.fadeStart)),
                .init(color: .white.opacity(0.5), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask(pillShape.stroke(lineWidth: 1))
        .placed(in: layout.pill)
    }
}

/// Before Liquid Glass (macOS 14 and 15): the window's blurred backdrop.
private struct FrostedGlass<S: Shape>: View {
    var shape: S

    var body: some View {
        BackdropBlur()
            .clipShape(shape)
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
