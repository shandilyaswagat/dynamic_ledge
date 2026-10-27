import CoreGraphics
import SwiftUI

/// Where every black shape goes, in window coordinates (top-left origin).
public struct IslandLayout: Equatable, Sendable {
    public var canvasSize: CGSize
    /// Bounds of the main shape, including the notch-style shoulders.
    public var pill: CGRect
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    /// Radius of the concave shoulders where the shape meets the top edge.
    public var flare: CGFloat
    public var pillOpacity: Double
    /// The minimal bubble. Zero-sized and tucked inside the shape when there is no second activity.
    public var bubble: CGRect
    public var shadow: Double
    public var stroke: Double
    /// Where content is laid out, in window coordinates. Not animated; content swaps instead.
    public var content: CGRect
    /// Width kept clear in the middle of the content for the camera (compact views and alerts).
    public var cameraGap: CGFloat
    /// Home tabs: height of the strip beside the camera that holds the tab header.
    public var stripHeight: CGFloat
    /// Size multiplier for everything inside the shape (Small / Medium / Large).
    public var contentScale: CGFloat

    public init(
        canvasSize: CGSize,
        pill: CGRect,
        topRadius: CGFloat,
        bottomRadius: CGFloat,
        flare: CGFloat = 0,
        pillOpacity: Double = 1,
        bubble: CGRect = .zero,
        shadow: Double = 0,
        stroke: Double = 0,
        content: CGRect = .zero,
        cameraGap: CGFloat = 0,
        contentScale: CGFloat = 1
    ) {
        self.canvasSize = canvasSize
        self.pill = pill
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.flare = flare
        self.pillOpacity = pillOpacity
        self.bubble = bubble
        self.shadow = shadow
        self.stroke = stroke
        self.content = content
        self.cameraGap = cameraGap
        self.contentScale = contentScale
        self.stripHeight = 0
    }

    /// The values SwiftUI interpolates during a spring.
    public var animatableData: AnimatableVector {
        get {
            AnimatableVector(SIMD16(
                pill.minX, pill.minY, pill.width, pill.height,
                topRadius, bottomRadius, flare, pillOpacity,
                bubble.minX, bubble.minY, bubble.width, bubble.height,
                shadow, stroke, 0, 0
            ))
        }
        set {
            let v = newValue.storage
            pill = CGRect(x: v[0], y: v[1], width: max(0, v[2]), height: max(0, v[3]))
            topRadius = max(0, v[4])
            bottomRadius = max(0, v[5])
            flare = max(0, v[6])
            pillOpacity = min(max(v[7], 0), 1)
            bubble = CGRect(x: v[8], y: v[9], width: max(0, v[10]), height: max(0, v[11]))
            shadow = max(0, v[12])
            stroke = max(0, v[13])
        }
    }
}

/// A fixed-size vector so a whole layout can animate as one value.
public struct AnimatableVector: VectorArithmetic, Sendable {
    public var storage: SIMD16<Double>

    public init(_ storage: SIMD16<Double>) {
        self.storage = storage
    }

    public static var zero: AnimatableVector { AnimatableVector(.zero) }

    public static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(lhs.storage + rhs.storage)
    }

    public static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(lhs.storage - rhs.storage)
    }

    public mutating func scale(by rhs: Double) {
        storage *= rhs
    }

    public var magnitudeSquared: Double {
        (storage * storage).sum()
    }
}

/// The outline shared by the drawn surface and the content clip.
public enum IslandPath {
    public static func path(in rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat, flare: CGFloat) -> Path {
        guard rect.width > 0.5, rect.height > 0.5 else { return Path() }
        let flare = min(max(flare, 0), rect.width / 4, rect.height / 2)
        guard flare > 0.01 else {
            let top = min(max(topRadius, 0), rect.width / 2, rect.height / 2)
            let bottom = min(max(bottomRadius, 0), rect.width / 2, rect.height / 2)
            return Path(
                roundedRect: rect,
                cornerRadii: RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top),
                style: .continuous
            )
        }

        // Flat top fused to the screen edge, concave shoulders, rounded bottom: the notch outline.
        let left = rect.minX + flare
        let right = rect.maxX - flare
        let bottom = min(max(bottomRadius, 0), (right - left) / 2, rect.height - flare)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: left, y: rect.maxY), radius: flare)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.minY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: flare)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Turns a presentation into concrete geometry for one display and one set of settings.
public struct LayoutEngine: Equatable, Sendable {
    public let screen: ScreenMetrics
    public let appearance: NotchAppearance

    public init(screen: ScreenMetrics, appearance: NotchAppearance) {
        self.screen = screen
        self.appearance = appearance.clamped()
    }

    /// Small / Medium / Large multiplier.
    public var scale: CGFloat { appearance.size.scale }

    // MARK: Shared measurements

    /// The camera housing, or on a display without one, a virtual notch of the same size at the
    /// top centre. Everything grows out of it the same way on every display.
    public var notch: CGRect {
        if let notch = screen.notch { return notch }
        let width = IslandMetrics.virtualNotchWidth
        let height = max(screen.menuBarHeight, IslandMetrics.virtualNotchMinHeight)
        return CGRect(x: ((screen.size.width - width) / 2).rounded(), y: 0, width: width, height: height)
    }

    /// True on displays without a notch. Nothing is drawn there until there's something to show
    /// or the pointer rests on the notch's spot.
    public var isVirtualNotch: Bool { screen.notch == nil }

    /// Thickness of the compact shape.
    public var compactHeight: CGFloat {
        max(appearance.height, notch.height)
    }

    /// Width the compact content must keep clear for the camera.
    public var cameraGap: CGFloat { notch.width }

    private var earWidth: CGFloat {
        (IslandMetrics.earWidth(appearance, height: compactHeight) * scale).rounded()
    }

    /// Width of the compact shape without shoulders.
    public var compactBodyWidth: CGFloat {
        notch.width + 2 * earWidth
    }

    /// Volume and brightness use a slimmer shape than other alerts.
    private func alertBodySize(for alert: IslandAlert) -> CGSize {
        switch alert {
        case .upcomingEvent, .shortcut, .download:
            // Names need room beside the camera.
            CGSize(width: notch.width + 2 * max(earWidth, (IslandMetrics.namedAlertEarWidth * scale).rounded()), height: compactHeight + (6 * scale).rounded())
        case .level:
            CGSize(width: notch.width + 2 * max(earWidth, (IslandMetrics.levelEarWidth * scale).rounded()), height: compactHeight)
        default:
            alertBodySize
        }
    }

    private var alertBodySize: CGSize {
        CGSize(
            width: notch.width + 2 * max(earWidth, (IslandMetrics.alertEarWidth * scale).rounded()),
            height: compactHeight + (6 * scale).rounded()
        )
    }

    public var expandedWidth: CGFloat {
        max((IslandMetrics.expandedWidth(appearance) * scale).rounded(), compactBodyWidth + 40)
    }

    /// Width of the Home / Tray / Mirror nook.
    public var nookWidth: CGFloat {
        max((IslandMetrics.Nook.width * scale).rounded(), compactBodyWidth + 40)
    }

    /// Width of Home, Tray, Clipboard and the grid in the elongated layout: as wide as the
    /// screen allows, up to a limit, so the widgets sit in one long row.
    public var elongatedWidth: CGFloat {
        let room = screen.size.width - 2 * (IslandMetrics.Nook.elongatedEdge + IslandMetrics.expandedFlare)
        return max(nookWidth, min(room, (IslandMetrics.Nook.elongatedMaxWidth * scale).rounded()))
    }

    /// True when this view uses the long, short elongated panel: Home, Tray and Clipboard. The
    /// grid and the panels opened from it (Timer, Calendar and the rest) keep their own size.
    public func isElongated(_ presentation: IslandPresentation) -> Bool {
        guard appearance.nookLayout == .elongated, let tab = presentation.homeTab else { return false }
        return tab.isTab
    }

    /// The nook's width for a view: elongated or standard.
    public func nookWidth(for presentation: IslandPresentation) -> CGFloat {
        isElongated(presentation) ? elongatedWidth : nookWidth
    }

    private func expandedHeight(content: CGFloat) -> CGFloat {
        notch.height + IslandMetrics.notchContentGap + content + (IslandMetrics.notchBottomPadding * scale).rounded()
    }

    private var bubbleDiameter: CGFloat {
        max(((compactHeight - 6) * scale).rounded(), 16)
    }

    private let bubbleGap: CGFloat = 4

    private var widestContent: CGFloat {
        max(
            max(expandedWidth, appearance.nookLayout == .elongated ? elongatedWidth : nookWidth) + 2 * IslandMetrics.expandedFlare,
            compactBodyWidth + 2 * (IslandMetrics.compactFlare + bubbleGap + bubbleDiameter + IslandMetrics.hoverGrowth.width),
            alertBodySize.width + 2 * IslandMetrics.compactFlare
        )
    }

    /// Fixed for a display: full width and tall enough for any setting, so neither settings nor
    /// presentations ever move the window under content that is animating.
    public var windowSize: CGSize {
        // At Large, the biggest size; smaller sizes fit inside it.
        let tallestShape = notch.height + IslandMetrics.notchContentGap + IslandMetrics.ContentHeight.maximum + IslandMetrics.notchBottomPadding
        return CGSize(
            width: screen.size.width,
            height: min(screen.size.height, (tallestShape + IslandMetrics.windowMargin).rounded(.up))
        )
    }

    /// Centre of the shape on the display: the notch, kept far enough from the edges for the
    /// widest view.
    public var anchorScreenX: CGFloat {
        let half = widestContent / 2 + IslandMetrics.screenEdgeInset
        let lower = half
        let upper = screen.size.width - half
        guard lower <= upper else { return screen.size.width / 2 }
        return min(max(notch.midX, lower), upper)
    }

    /// Left edge of the window on the display. The window spans the display, so window and
    /// display coordinates match.
    public var windowOriginX: CGFloat { 0 }

    /// Centre of the shape in window coordinates.
    public var anchorX: CGFloat {
        anchorScreenX - windowOriginX
    }

    public var notchInWindow: CGRect {
        notch.offsetBy(dx: -windowOriginX, dy: 0)
    }

    /// Content height for the expanded family at the current size, nil for compact forms.
    public func expandedContentHeight(for presentation: IslandPresentation, home: HomeContent) -> CGFloat? {
        baseContentHeight(for: presentation, home: home).map { ($0 * scale).rounded() }
    }

    public func expandedContentHeight(for presentation: IslandPresentation, homeHasMedia: Bool) -> CGFloat? {
        expandedContentHeight(for: presentation, home: HomeContent(hasMedia: homeHasMedia))
    }

    private func baseContentHeight(for presentation: IslandPresentation, home: HomeContent) -> CGFloat? {
        switch presentation {
        case .expanded(.nowPlaying): IslandMetrics.ContentHeight.nowPlaying + (home.hasMediaSwitcher ? IslandMetrics.ContentHeight.mediaSwitcher : 0)
        case .expanded(.timer), .expanded(.stopwatch): IslandMetrics.ContentHeight.timer
        case .expanded(.call): IslandMetrics.ContentHeight.call
        case .nook(let tab): ((tab == .launcher || tab == .shortcutEditor) ? IslandMetrics.Nook.launcherBody : IslandMetrics.Nook.body) + IslandMetrics.Nook.bodyTopInset
        case .alert(.timerFinished): IslandMetrics.ContentHeight.timerFinished
        case .drop: IslandMetrics.ContentHeight.drop
        default: nil
        }
    }

    // MARK: Layout

    public func layout(for presentation: IslandPresentation, homeHasMedia: Bool, hovering: Bool) -> IslandLayout {
        layout(for: presentation, home: HomeContent(hasMedia: homeHasMedia), hovering: hovering)
    }

    public func layout(for presentation: IslandPresentation, home: HomeContent, hovering: Bool) -> IslandLayout {
        var layout = notchLayout(for: presentation, home: home)
        layout.contentScale = scale

        if hovering, presentation.isRestingPill {
            // Grows sideways and down; the top stays fused to the screen edge.
            let growth = IslandMetrics.hoverGrowth
            layout.pill = CGRect(
                x: layout.pill.minX - growth.width,
                y: layout.pill.minY,
                width: layout.pill.width + 2 * growth.width,
                height: layout.pill.height + growth.height
            )
        }

        if appearance.pitchBlack {
            layout.shadow = 0
            layout.stroke = 0
        }

        if layout.bubble == .zero {
            // Tucked into the right end of the shape, so it oozes out from there when it appears.
            let inset = layout.flare + bubbleDiameter / 2
            let midY = layout.pill.minY + min(layout.pill.height, compactHeight) / 2
            layout.bubble = CGRect(x: layout.pill.maxX - inset, y: midY, width: 0, height: 0)
        }
        return layout
    }

    private func notchLayout(for presentation: IslandPresentation, home: HomeContent) -> IslandLayout {
        let centerX = anchorX
        let notch = notchInWindow
        let height = compactHeight
        let compactRadius = min(height * 0.42, 14)

        func shape(body: CGFloat, height: CGFloat, flare: CGFloat) -> CGRect {
            CGRect(x: centerX - body / 2 - flare, y: 0, width: body + 2 * flare, height: height)
        }

        var layout = IslandLayout(
            canvasSize: windowSize,
            pill: .zero,
            topRadius: 0,
            bottomRadius: compactRadius,
            flare: IslandMetrics.compactFlare
        )

        switch presentation {
        case .hidden(let peek):
            if peek {
                // The notch swells a little to show it can be clicked. On a display without a
                // notch this is the moment it appears.
                layout.pill = shape(body: notch.width + 20, height: notch.height + 3, flare: 5)
                layout.flare = 5
                layout.bottomRadius = 11
            } else if isVirtualNotch {
                // Nothing to hide behind, so it slides up into the top edge of the screen, keeping
                // its shoulders and rounded corners all the way. At zero height nothing is drawn,
                // so it never has to fade or pop out.
                let width = ((notch.width + 20) * 0.86).rounded()
                layout.pill = shape(body: width, height: 0, flare: 5)
                layout.flare = 5
                layout.bottomRadius = 11
            } else {
                // Tucked just inside the real notch so growth starts from the notch itself.
                // Fully transparent at rest, so screenshots and recordings show nothing.
                layout.pill = CGRect(x: notch.minX + 1.5, y: 0, width: notch.width - 3, height: notch.height - 1)
                layout.flare = 0
                layout.bottomRadius = 9
                layout.pillOpacity = 0
            }
        case .idle:
            layout.pill = shape(body: notch.width + 24, height: height, flare: IslandMetrics.compactFlare)
            layout.shadow = 0.2
            layout.content = layout.pill.insetBy(dx: IslandMetrics.compactFlare, dy: 0)
        case .compact(_, let secondary):
            layout.pill = shape(body: compactBodyWidth, height: height, flare: IslandMetrics.compactFlare)
            layout.shadow = 0.3
            layout.content = layout.pill.insetBy(dx: IslandMetrics.compactFlare, dy: 0)
            layout.cameraGap = cameraGap
            if secondary != nil {
                let diameter = bubbleDiameter
                layout.bubble = CGRect(x: layout.pill.maxX + bubbleGap, y: (height - diameter) / 2, width: diameter, height: diameter)
            }
        case .alert(let alert) where alert != .timerFinished:
            let size = alertBodySize(for: alert)
            layout.pill = shape(body: size.width, height: size.height, flare: IslandMetrics.compactFlare)
            layout.bottomRadius = min(size.height * 0.42, 16)
            layout.shadow = 0.6
            layout.content = layout.pill.insetBy(dx: IslandMetrics.compactFlare, dy: 0)
            layout.cameraGap = cameraGap
        case .nook:
            // The tab header lives in the strip beside the camera; widgets sit below it.
            let width = nookWidth(for: presentation)
            let body = expandedContentHeight(for: presentation, home: home) ?? 0
            layout.pill = shape(body: width, height: expandedHeight(content: body), flare: IslandMetrics.expandedFlare)
            layout.flare = IslandMetrics.expandedFlare
            layout.bottomRadius = (IslandMetrics.notchExpandedRadius * scale).rounded()
            layout.shadow = 1
            layout.content = CGRect(x: centerX - width / 2, y: 0, width: width, height: notch.height + IslandMetrics.notchContentGap + body)
            layout.stripHeight = notch.height
            layout.cameraGap = cameraGap
        default:
            let contentHeight = expandedContentHeight(for: presentation, home: home) ?? IslandMetrics.ContentHeight.timer
            let width = expandedWidth
            layout.pill = shape(body: width, height: expandedHeight(content: contentHeight), flare: IslandMetrics.expandedFlare)
            layout.flare = IslandMetrics.expandedFlare
            layout.bottomRadius = (IslandMetrics.notchExpandedRadius * scale).rounded()
            layout.shadow = 1
            layout.content = CGRect(
                x: centerX - width / 2,
                y: notch.height + IslandMetrics.notchContentGap,
                width: width,
                height: contentHeight
            )
        }
        return layout
    }

    // MARK: Hit testing

    /// Where the pointer counts as resting on the hidden notch: the whole peek it swells into,
    /// so its edges count too.
    public var notchHoverRect: CGRect {
        let slop = IslandMetrics.hitSlop
        let notch = notchInWindow
        return CGRect(x: notch.minX - 10 - slop, y: 0, width: notch.width + 20 + 2 * slop, height: notch.maxY + 3 + slop)
    }

    /// Areas that should receive the mouse, in window coordinates.
    public func interactiveRects(for presentation: IslandPresentation, layout: IslandLayout) -> [CGRect] {
        let slop = IslandMetrics.hitSlop
        switch presentation {
        case .hidden:
            return [notchHoverRect]
        case .compact(_, let secondary):
            var rects = [layout.pill.insetBy(dx: -slop, dy: -slop)]
            if secondary != nil {
                rects.append(layout.bubble.insetBy(dx: -slop, dy: -slop))
            }
            return rects
        default:
            return [layout.pill.insetBy(dx: -slop, dy: -slop)]
        }
    }

    /// Region where a file drag turns the shape into a drop target.
    public var dropZone: CGRect {
        let width = expandedWidth + 80
        return CGRect(
            x: anchorX - width / 2,
            y: 0,
            width: width,
            height: expandedHeight(content: IslandMetrics.ContentHeight.drop) + 24
        )
    }
}
