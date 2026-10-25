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
    /// The floating island is a very dark grey, so it reads as an object on bright wallpapers.
    /// The notch itself stays pure black to blend with the camera housing.
    static let islandFill = Color(red: 0.055, green: 0.055, blue: 0.06)

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
    /// Spring for a change of presentation, picked by where the pill is going.
    static func shape(to presentation: IslandPresentation, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.2)
        }
        switch presentation {
        case .hidden:
            return .spring(duration: 0.4, bounce: 0.1)
        case .idle, .compact:
            return .spring(duration: 0.45, bounce: 0.28)
        case .expanded, .nook, .alert, .drop:
            return .spring(duration: 0.5, bounce: 0.25)
        }
    }

    static let settings = Animation.spring(duration: 0.3, bounce: 0)
    static let hover = Animation.spring(duration: 0.3, bounce: 0.35)
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
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Old content blurs out quickly; new content blurs in once the shape is on its way.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(blur: 8, scale: 0.9, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeOut(duration: 0.3).delay(0.06)),
            removal: .modifier(
                active: BlurFade(blur: 6, scale: 1.04, opacity: 0),
                identity: BlurFade(blur: 0, scale: 1, opacity: 1)
            ).animation(.easeIn(duration: 0.15))
        )
    }
}
