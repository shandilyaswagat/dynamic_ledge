import SwiftUI

/// Colours from DESIGN.md. The surface is always black, so these are the dark-mode system values.
enum NotchColor {
    static let orange = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    static let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let yellow = Color(red: 1, green: 214 / 255, blue: 10 / 255)
    static let blue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let secondaryText = Color.white.opacity(0.55)
    static let buttonFill = Color.white.opacity(0.18)

    static func accent(_ rgb: ColorMath.RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension TimerMode {
    /// Every kind of timer shares the timer orange, as on iPhone.
    var tint: Color { NotchColor.orange }

    var title: LocalizedStringKey {
        switch self {
        case .plain: "Timer"
        case .focus: "Focus"
        case .rest: "Break"
        }
    }

    var symbol: String {
        switch self {
        case .plain: "timer"
        case .focus: "brain.head.profile.fill"
        case .rest: "cup.and.saucer.fill"
        }
    }
}

enum Motion {
    /// Spring for a change of presentation, picked by where the shape is going. Opening has a
    /// little give, like the iPhone's island; closing settles without a bounce. `style` makes
    /// every spring livelier or calmer.
    static func shape(
        to presentation: IslandPresentation,
        reduceMotion: Bool,
        theme: NotchTheme = .black,
        style: MotionStyle = .standard
    ) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.2)
        }
        if theme == .glass { return glassShape(to: presentation, style: style) }
        switch presentation {
        case .hidden(peek: true):
            return spring(0.34, 0.72, style)
        case .hidden:
            // Retracting: smooth and deliberate, no overshoot, so it settles exactly at the edge.
            return .smooth(duration: style == .calm ? 0.5 : 0.42)
        case .idle, .compact:
            return spring(0.42, 0.76, style)
        case .alert:
            return spring(0.44, 0.74, style)
        case .expanded, .nook, .drop:
            return spring(0.48, 0.8, style)
        }
    }

    /// Glass moves like a drop of liquid: a touch slower, with more give as it opens and a soft
    /// settle as it closes.
    private static func glassShape(to presentation: IslandPresentation, style: MotionStyle) -> Animation {
        switch presentation {
        case .hidden(peek: true):
            spring(0.4, 0.64, style)
        case .hidden:
            // Closing never bounces, whatever the style.
            spring(0.5, 0.92, style == .springy ? .standard : style)
        case .idle, .compact:
            spring(0.5, 0.7, style)
        case .alert:
            spring(0.52, 0.68, style)
        case .expanded, .nook, .drop:
            spring(0.56, 0.74, style)
        }
    }

    /// A spring tuned by `style`: Springy is a little quicker with more bounce, Calm a little
    /// slower and doesn't bounce at all.
    static func spring(_ response: Double, _ dampingFraction: Double, _ style: MotionStyle) -> Animation {
        switch style {
        case .standard: .spring(response: response, dampingFraction: dampingFraction)
        case .springy: .spring(response: response * 0.92, dampingFraction: damping(dampingFraction, style))
        case .calm: .spring(response: response * 1.12, dampingFraction: damping(dampingFraction, style))
        }
    }

    /// Springy takes away 0.16 of the damping, but never below 0.5, where it would wobble.
    static func damping(_ value: Double, _ style: MotionStyle) -> Double {
        switch style {
        case .standard: value
        case .springy: max(value - 0.16, 0.5)
        case .calm: 1
        }
    }

    static let settings = Animation.spring(response: 0.3, dampingFraction: 1)
    /// The open notch growing or shrinking to fit what's in it.
    static let resize = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let hover = Animation.spring(response: 0.3, dampingFraction: 0.68)

    static func resize(_ theme: NotchTheme, style: MotionStyle = .standard) -> Animation {
        theme == .glass ? spring(0.46, 0.8, style) : spring(0.38, 0.86, style)
    }

    static func hover(_ theme: NotchTheme, style: MotionStyle = .standard) -> Animation {
        theme == .glass ? spring(0.36, 0.6, style) : spring(0.3, 0.68, style)
    }
}

/// Sizes inside the compact shape scale with its thickness and with Small / Medium / Large.
struct CompactScale {
    let height: CGFloat
    var size: CGFloat = 1

    var icon: CGFloat { (height * 0.62 * size).rounded() }
    var padding: CGFloat { ((height - icon) / 2).rounded(.down) }
    var fontSize: CGFloat { min(max(height * 0.4 * size, 10), 18) }
}

private struct NotchScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Small / Medium / Large multiplier for everything drawn inside the notch.
    var notchScale: CGFloat {
        get { self[NotchScaleKey.self] }
        set { self[NotchScaleKey.self] = newValue }
    }
}

private struct BlurFade: ViewModifier {
    var blur: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Content grows out of the notch: it unblurs and scales up from the top edge as the shape
    /// opens, and leaves quickly so the shape never closes over it.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(blur: 6, scale: 0.92, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.smooth(duration: 0.34).delay(0.06)),
            removal: .modifier(
                active: BlurFade(blur: 4, scale: 0.97, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeIn(duration: 0.12))
        )
    }

    /// The Glass theme's version: content condenses out of the glass more slowly, with a deeper
    /// blur, so it reads as forming inside the liquid rather than appearing on top of it.
    static var glassContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(blur: 10, scale: 0.9, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.smooth(duration: 0.44).delay(0.08)),
            removal: .modifier(
                active: BlurFade(blur: 6, scale: 0.96, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeIn(duration: 0.14))
        )
    }

    /// Switching tabs while Home is open: a quick, soft crossfade, like a segmented control.
    static var nookTab: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(blur: 3, scale: 1, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.smooth(duration: 0.22).delay(0.04)),
            removal: .modifier(
                active: BlurFade(blur: 3, scale: 1, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeOut(duration: 0.1))
        )
    }
}
