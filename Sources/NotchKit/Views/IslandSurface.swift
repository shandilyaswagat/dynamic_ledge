import SwiftUI

/// The black shapes behind the content: the main shape and the minimal bubble. Drawn in a Canvas
/// so the two can merge like liquid while they move.
struct IslandSurface: View, Animatable {
    var layout: IslandLayout
    /// Liquid pulse from the transition keyframes, 0…1.
    var pulse: Double
    var liquid: Bool

    @Environment(\.displayScale) private var displayScale

    nonisolated var animatableData: AnimatableVector {
        get { layout.animatableData }
        set { layout.animatableData = newValue }
    }

    var body: some View {
        let strength = liquid ? min(1, pulse) : 0
        let layout = layout
        let scale = displayScale
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let main = IslandPath.path(in: layout.pill, topRadius: layout.topRadius, bottomRadius: layout.bottomRadius, flare: layout.flare)
            // The shape stays solid while it moves and only vanishes once it is back inside the
            // notch (or the top edge), instead of fading in and out.
            let opacity = min(1, layout.pillOpacity * 20)
            guard opacity > 0.001 || layout.bubble.width > 0.5 else { return }
            let mainShading = GraphicsContext.Shading.color(Color.black.opacity(opacity))
            let black = GraphicsContext.Shading.color(Color.black)
            let hasBubble = layout.bubble.width > 0.5 && layout.bubble.height > 0.5
            let blur = GooMath.blurRadius(strength: strength)

            guard blur > 0.2 else {
                context.fill(main, with: mainShading)
                if hasBubble {
                    context.fill(Path(ellipseIn: layout.bubble), with: black)
                }
                return
            }

            context.drawLayer { goo in
                let slope = GooMath.alphaSlope(blurRadius: blur, displayScale: scale)
                var matrix = ColorMatrix()
                matrix.a4 = Float(slope)
                matrix.a5 = Float(GooMath.alphaBias(slope: slope))
                // Filters apply in reverse order: blur first, then the alpha sharpen.
                goo.addFilter(.colorMatrix(matrix))
                goo.addFilter(.blur(radius: blur))
                goo.drawLayer { layer in
                    layer.fill(main, with: mainShading)
                    if hasBubble {
                        layer.fill(Path(ellipseIn: layout.bubble), with: black)
                    }
                }
            }
            // The blur softens edges that touch the screen top; a crisp copy keeps them sharp.
            context.fill(main, with: mainShading)
        }
        .shadow(color: .black.opacity(0.35 * min(layout.shadow, 1)), radius: 18, y: 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Clip and hit shape for the content, matching the drawn surface.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var flare: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(topRadius, AnimatablePair(bottomRadius, flare)) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second.first
            flare = newValue.second.second
        }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        IslandPath.path(in: rect, topRadius: topRadius, bottomRadius: bottomRadius, flare: flare)
    }
}
