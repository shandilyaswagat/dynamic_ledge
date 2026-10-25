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
    /// little give, like the iPhone's island; closing settles without a bounce.
    static func shape(to presentation: IslandPresentation, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.2)
        }
        switch presentation {
        case .hidden(peek: true):
            return .spring(response: 0.34, dampingFraction: 0.72)
        case .hidden:
            // Retracting: smooth and deliberate, no overshoot, so it settles exactly at the edge.
            return .smooth(duration: 0.42)
        case .idle, .compact:
            return .spring(response: 0.42, dampingFraction: 0.76)
        case .alert:
            return .spring(response: 0.44, dampingFraction: 0.74)
        case .expanded, .nook, .drop:
            return .spring(response: 0.48, dampingFraction: 0.8)
        }
    }

    static let settings = Animation.spring(response: 0.3, dampingFraction: 1)
    static let hover = Animation.spring(response: 0.3, dampingFraction: 0.68)
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
