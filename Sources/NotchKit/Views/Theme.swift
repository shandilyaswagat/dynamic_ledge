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
    /// Spring for a change of presentation. Opening has the give of the iPhone's island: a quick
    /// spring that overshoots by about 7 % and settles back. Closing (to anything smaller than
    /// where it was) settles critically damped, so it never bounces. `style` makes every opening
    /// livelier or calmer.
    static func shape(
        from previous: IslandPresentation? = nil,
        to presentation: IslandPresentation,
        reduceMotion: Bool,
        theme: NotchTheme = .black,
        style: MotionStyle = .standard
    ) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.2)
        }
        switch presentation {
        case .hidden(peek: true):
            return spring(0.34, 0.72, style)
        case .hidden:
            // Retracting: smooth and deliberate, no overshoot, so it settles exactly at the edge.
            return .smooth(duration: style == .calm ? 0.5 : 0.42)
        default:
            break
        }
        if let previous, isClosing(from: previous, to: presentation) {
            return .spring(response: style == .calm ? 0.42 : 0.38, dampingFraction: 1)
        }
        switch presentation {
        case .hidden:
            return spring(0.34, 0.72, style)
        case .idle, .compact:
            return spring(0.4, 0.7, style)
        case .alert:
            return spring(0.38, 0.66, style)
        case .expanded, .drop:
            return spring(0.37, 0.65, style)
        case .nook:
            // Home and its panels are big: the same bounce in points would look like a wobble.
            return spring(0.4, 0.74, style)
        }
    }

    /// Views that open below the camera (music, Home and the panels, a drop, an approval),
    /// rather than sitting beside it.
    static func isOpenView(_ presentation: IslandPresentation) -> Bool {
        rank(presentation) >= 4
    }

    /// True when the shape is shrinking to a smaller kind of view, like the open notch going
    /// back to the activity beside the camera.
    static func isClosing(from previous: IslandPresentation, to presentation: IslandPresentation) -> Bool {
        rank(presentation) < rank(previous)
    }

    private static func rank(_ presentation: IslandPresentation) -> Int {
        switch presentation {
        case .hidden: 0
        case .idle: 1
        case .compact: 2
        case .alert(let alert): alert.usesExpandedLayout ? 4 : 3
        case .expanded, .nook, .drop: 4
        }
    }

    /// A spring tuned by `style`: Springy is a little quicker with more bounce, Calm a little
    /// slower and doesn't bounce at all.
    static func spring(_ response: Double, _ dampingFraction: Double, _ style: MotionStyle) -> Animation {
        switch style {
        case .standard: .spring(response: response, dampingFraction: dampingFraction)
        case .springy: .spring(response: response * 0.95, dampingFraction: damping(dampingFraction, style))
        case .calm: .spring(response: response * 1.12, dampingFraction: damping(dampingFraction, style))
        }
    }

    /// Springy takes away 0.1 of the damping, but never below 0.56 (about 12 % overshoot):
    /// lower than that reads as a wobble rather than a bounce.
    static func damping(_ value: Double, _ style: MotionStyle) -> Double {
        switch style {
        case .standard: value
        case .springy: max(value - 0.1, 0.56)
        case .calm: 1
        }
    }

    static let settings = Animation.spring(response: 0.3, dampingFraction: 1)
    /// The open notch growing or shrinking to fit what's in it.
    static let resize = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// The resting shape lifting under the pointer: quick and without a bounce.
    static let hover = Animation.spring(response: 0.32, dampingFraction: 0.9)

    static func resize(_ theme: NotchTheme, style: MotionStyle = .standard) -> Animation {
        spring(0.38, 0.86, style)
    }

    static func hover(_ theme: NotchTheme, style: MotionStyle = .standard) -> Animation {
        spring(0.32, 0.9, style)
    }
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
    /// An open view (music, Home, a panel) appearing: it fades in with a light blur while the
    /// shape grows, and `StretchWithShell` grows it with the shape. Leaving, it shrinks with the
    /// shape back into the notch and fades as it goes. The blur stays light: heavy blur over a large view looks
    /// smeared and costs frames.
    static var islandOpenContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(blur: 3, scale: 1, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeOut(duration: 0.18).delay(0.03)),
            removal: .modifier(
                active: BlurFade(blur: 2, scale: 1, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeIn(duration: 0.14).delay(0.03))
        )
    }

    /// What sits beside the camera: it fades as soon as the shape starts opening, and comes back
    /// once a closing shape is nearly compact again.
    /// The second activity's symbol: in once its bubble has slid clear of the shape, and out
    /// before the bubble slides back in.
    static var bubbleContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.7)).animation(.easeOut(duration: 0.2).delay(0.12)),
            removal: .opacity.combined(with: .scale(scale: 0.7)).animation(.easeIn(duration: 0.1))
        )
    }

    static var islandCompactContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(blur: 2, scale: 0.94, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeOut(duration: 0.16).delay(0.08)),
            removal: .modifier(
                active: BlurFade(blur: 2, scale: 1, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeOut(duration: 0.08))
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
