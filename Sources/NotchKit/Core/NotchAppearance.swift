import CoreGraphics

/// Overall size of everything the notch shows. Large is the original design.
public enum NotchSize: String, CaseIterable, Sendable, Codable, Identifiable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    /// Multiplier applied to ears, alerts, expanded views and all content inside them.
    public var scale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 0.9
        case .large: 1
        }
    }
}

/// How Home and its tabs are laid out when the notch opens.
public enum NookLayout: String, CaseIterable, Sendable, Codable, Identifiable {
    /// A compact panel: music on the left, rows beside it.
    case standard
    /// A long, short panel across the top of the screen with a row of widgets you scroll through.
    case elongated

    public var id: String { rawValue }
}

/// The user's size choices.
public struct NotchAppearance: Equatable, Sendable, Codable {
    /// How far the shape reaches either side of the camera.
    public var width: Double
    /// Thickness of the compact shape. It never goes below the notch height.
    public var height: Double
    /// Pure black with no shadow or outline, so the shape is indistinguishable from the notch.
    public var pitchBlack: Bool
    /// Small, medium or large. Width and thickness fine-tune on top of it.
    public var size: NotchSize
    public var nookLayout: NookLayout

    public init(
        width: Double,
        height: Double,
        pitchBlack: Bool = true,
        size: NotchSize = .large,
        nookLayout: NookLayout = .standard
    ) {
        self.width = width
        self.height = height
        self.pitchBlack = pitchBlack
        self.size = size
        self.nookLayout = nookLayout
    }

    public static let standard = NotchAppearance(
        width: 200,
        height: 32,
        pitchBlack: true,
        size: .large
    )

    public static let widthRange: ClosedRange<Double> = 120...420
    public static let heightRange: ClosedRange<Double> = 24...52

    /// Brings every value into its supported range, replacing non-finite values with defaults.
    public func clamped() -> NotchAppearance {
        NotchAppearance(
            width: Self.clamp(width, to: Self.widthRange, fallback: Self.standard.width),
            height: Self.clamp(height, to: Self.heightRange, fallback: Self.standard.height),
            pitchBlack: pitchBlack,
            size: size,
            nookLayout: nookLayout
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
