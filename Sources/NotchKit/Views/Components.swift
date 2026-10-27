import AppKit
import SwiftUI

/// The bouncing bars from the iPhone's music activity. The motion is a Core Animation keyframe
/// loop, so it runs in the system render server and costs the app almost no CPU.
struct WaveformBars: NSViewRepresentable {
    var color: Color
    var isPlaying: Bool
    var barCount = 4

    func makeNSView(context: Context) -> WaveformBarsView {
        WaveformBarsView(barCount: barCount)
    }

    func updateNSView(_ view: WaveformBarsView, context: Context) {
        view.update(color: NSColor(color), isPlaying: isPlaying)
    }
}

final class WaveformBarsView: NSView {
    private var bars: [CALayer] = []
    private var isPlaying = false

    /// Heights per bar as a fraction of the view, looped at slightly different speeds so the
    /// bars never fall into step.
    private static let levels: [[CGFloat]] = [
        [0.35, 0.9, 0.5, 1.0, 0.4, 0.75, 0.35],
        [0.8, 0.4, 1.0, 0.55, 0.9, 0.3, 0.8],
        [0.5, 1.0, 0.35, 0.7, 0.95, 0.45, 0.5],
        [0.9, 0.45, 0.75, 0.3, 0.85, 1.0, 0.9],
    ]
    private static let restingLevel: CGFloat = 0.28

    init(barCount: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        for _ in 0..<barCount {
            let bar = CALayer()
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    func update(color: NSColor, isPlaying: Bool) {
        let cgColor = color.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = cgColor }
        CATransaction.commit()
        if isPlaying != self.isPlaying {
            self.isPlaying = isPlaying
            applyMotion(animatedTransition: true)
        }
    }

    override func layout() {
        super.layout()
        applyMotion(animatedTransition: false)
    }

    private func applyMotion(animatedTransition: Bool) {
        let size = bounds.size
        guard size.width > 0, size.height > 0, !bars.isEmpty else { return }
        let count = CGFloat(bars.count)
        let spacing = size.width * 0.12
        let width = max(1.5, (size.width - spacing * (count - 1)) / count)

        CATransaction.begin()
        CATransaction.setDisableActions(!animatedTransition)
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "level")
            bar.cornerRadius = width / 2
            bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: size.height / 2)
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: max(width, size.height * Self.restingLevel))
            guard isPlaying else { continue }

            let levels = Self.levels[index % Self.levels.count]
            let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
            animation.values = levels.map { max(width, size.height * $0) }
            animation.calculationMode = .cubic
            animation.duration = 1.2 + Double(index) * 0.23
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            bar.add(animation, forKey: "level")
        }
        CATransaction.commit()
    }
}

/// Album art, falling back to the player's icon, then to a note glyph.
struct ArtworkView: View {
    var artwork: NSImage?
    var fallbackIcon: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let fallbackIcon {
                Image(nsImage: fallbackIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.04)
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct AppIconView: View {
    var icon: NSImage?
    var symbol: String
    var tint: Color
    var size: CGFloat

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }
}

/// Scales down slightly while pressed, like iOS controls.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A click that works like a button's, while holding it down does nothing, or `onHold` when
/// given. A plain Button fires on release however long it was held, so a long press on it
/// would still open things.
struct ClickNotHold: ViewModifier {
    var onHold: (() -> Void)?
    let onClick: () -> Void

    func body(content: Content) -> some View {
        content
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first: onHold?()
                        case .second: onClick()
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onClick() }
    }
}

/// Round control from the iPhone timer and call activities.
struct CircleButton: View {
    var symbol: String
    var size: CGFloat = 44
    var foreground: Color = .white
    var background: Color = NotchColor.buttonFill
    var label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Plain glyph button for transport controls.
struct GlyphButton: View {
    var symbol: String
    var size: CGFloat
    var label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 1.8, height: size * 1.6)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

struct ChipButtonStyle: ButtonStyle {
    var tint: Color = NotchColor.orange
    var scale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12 * scale, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(tint)
            .padding(.horizontal, 4 * scale)
            .frame(height: 30 * scale)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.32 : 0.18)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

/// iOS-style battery: outlined body, fill by level, cap, and a bolt while charging.
struct BatteryGlyph: View {
    var level: Int
    var isCharging: Bool
    var color: Color
    var width: CGFloat = 27

    var body: some View {
        let height = width * 0.48
        let inset = width * 0.075
        HStack(spacing: width * 0.04) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, (width - inset * 2) * CGFloat(min(max(level, 0), 100)) / 100))
                    .padding(inset)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.72, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 0.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: height)
            Capsule()
                .fill(color.opacity(0.45))
                .frame(width: width * 0.06, height: height * 0.36)
        }
        .accessibilityHidden(true)
    }
}

/// A countdown that ticks on its own, like Live Activities.
struct CountdownText: View {
    var timer: CountdownTimer

    var body: some View {
        if let end = timer.endDate {
            let now = Date()
            Text(timerInterval: min(now, end)...end, countsDown: true)
        } else {
            Text(TimeFormatting.clock(timer.remaining(at: Date()), roundingUp: true))
        }
    }
}
