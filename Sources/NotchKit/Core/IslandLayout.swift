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
    /// Height of the camera housing from the top edge, kept black in the Glass theme so the
    /// notch never shows through. Zero on displays without a notch.
    public var notchBand: CGFloat
    /// The shape's bounds without the hover lift: the box content is laid out in. While the shape
    /// springs open or closed, or lifts under the pointer, content stretches from this size to
    /// the shape's current one, so it bounces with it. Not animated.
    public var restingPill: CGRect

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
        self.notchBand = 0
        self.restingPill = pill
    }

    /// The bubble's outline: the main shape's corners on a shape as tall as it, so a flat top
    /// with the notch's rounded bottom when it hangs from the edge, and a circle beside the
    /// floating pill.
    public var bubblePath: Path {
        IslandPath.path(in: bubble, topRadius: topRadius, bottomRadius: bottomRadius, flare: 0)
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
    /// A continuous corner of radius r starts 1.28 r from the corner…
    static let continuousReach: CGFloat = 1.28
    /// …with its control points this far along that, which keeps it close to a circle of r at
    /// the apex while easing into the straight edges.
    static let continuousHandle: CGFloat = 0.33

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
        // Continuous (squircle-like) bottom corners, as Apple draws them: the curve starts
        // further from the corner and eases in, instead of a circular arc.
        let reach = min(bottom * continuousReach, rect.height - flare, (right - left) / 2)
        let handle = reach * continuousHandle
        path.addLine(to: CGPoint(x: left, y: rect.maxY - reach))
        path.addCurve(to: CGPoint(x: left + reach, y: rect.maxY),
                      control1: CGPoint(x: left, y: rect.maxY - handle),
                      control2: CGPoint(x: left + handle, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - reach, y: rect.maxY))
        path.addCurve(to: CGPoint(x: right, y: rect.maxY - reach),
                      control1: CGPoint(x: right - handle, y: rect.maxY),
                      control2: CGPoint(x: right, y: rect.maxY - handle))
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
        let width = isPill ? IslandMetrics.pillCoreWidth : IslandMetrics.virtualNotchWidth
        let height = max(screen.menuBarHeight, IslandMetrics.virtualNotchMinHeight)
        return CGRect(x: ((screen.size.width - width) / 2).rounded(), y: 0, width: width, height: height)
    }

    /// True on displays without a notch. Nothing is drawn there until there's something to show
    /// or the pointer rests on the notch's spot.
    public var isVirtualNotch: Bool { screen.notch == nil }

    /// True when a display without a notch shows a floating pill, like the Dynamic Island,
    /// instead of a notch of its own.
    public var isPill: Bool { isVirtualNotch && appearance.externalStyle == .pill }

    /// How far everything sits below the top edge: the pill floats, the notch doesn't.
    private var topOffset: CGFloat { isPill ? IslandMetrics.pillTop : 0 }

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

    /// Music only needs the artwork on one side and the bars on the other, so its ears are
    /// slimmer, hugging the camera like the Dynamic Island. Wider width settings still widen it.
    public func compactBodyWidth(for kind: ActivityKind) -> CGFloat {
        guard kind == .nowPlaying else { return compactBodyWidth }
        let slim = (IslandMetrics.musicEarWidth(height: compactHeight) * scale).rounded()
        let ear = min(earWidth, max(slim, earWidth - (IslandMetrics.musicEarTrim * scale).rounded()))
        return notch.width + 2 * ear
    }

    /// Volume and brightness use a slimmer shape than other alerts.
    private func alertBodySize(for alert: IslandAlert) -> CGSize {
        switch alert {
        case .upcomingEvent, .shortcut, .download, .agentFinished:
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

    /// How many characters of an approval request fit on a line: 12 pt monospaced text in the
    /// usual expanded width, less the panel's padding, the Allow / Deny column beside the request
    /// and the text box's padding.
    var agentCharactersPerLine: Int {
        max(20, Int((expandedWidth / scale - 64 - IslandMetrics.agentButtonColumn) / 7.3))
    }

    /// Responds to logical display space, independently of the user's text and control size.
    /// The available width wins over the usual minimum on narrow or heavily scaled displays.
    public var elongatedWidth: CGFloat {
        let room = max(0, screen.size.width - 2 * (IslandMetrics.Nook.elongatedEdge + IslandMetrics.expandedFlare))
        let preferred = (screen.size.width * IslandMetrics.Nook.elongatedScreenFraction).rounded()
        return min(room, max(nookWidth, min(preferred, IslandMetrics.Nook.elongatedMaxWidth)))
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

    /// As tall as the compact shape, like the Dynamic Island's minimal view beside the island.
    private var bubbleDiameter: CGFloat { compactHeight }

    /// From the tip of the shape's shoulder in the notch; between the two in the floating pill.
    private let bubbleGap: CGFloat = 4
    private let floatingBubbleGap: CGFloat = 6

    private var widestContent: CGFloat {
        max(
            max(expandedWidth, appearance.nookLayout == .elongated ? elongatedWidth : nookWidth) + 2 * IslandMetrics.expandedFlare,
            compactBodyWidth + 2 * (IslandMetrics.compactFlare + bubbleGap + bubbleDiameter + IslandMetrics.hoverGrowth(for: CGSize(width: compactBodyWidth + 2 * IslandMetrics.compactFlare, height: compactHeight)).width),
            alertBodySize.width + 2 * IslandMetrics.compactFlare
        )
    }

    /// Fixed for a display: full width and tall enough for any setting, so neither settings nor
    /// presentations ever move the window under content that is animating.
    public var windowSize: CGSize {
        // At Large, the biggest size; smaller sizes fit inside it.
        let tallestShape = topOffset + notch.height + IslandMetrics.notchContentGap + IslandMetrics.ContentHeight.maximum + IslandMetrics.notchBottomPadding
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
        case .expanded(.nowPlaying):
            IslandMetrics.ContentHeight.nowPlaying
                + (home.hasLyrics ? IslandMetrics.ContentHeight.lyrics : 0)
                + (home.hasMediaSwitcher ? IslandMetrics.ContentHeight.mediaSwitcher : 0)
        case .expanded(.timer), .expanded(.stopwatch): IslandMetrics.ContentHeight.timer
        case .expanded(.call): IslandMetrics.ContentHeight.call
        case .expanded(.download): IslandMetrics.ContentHeight.download
        case .nook(.launcher): IslandMetrics.Nook.launcherBody + IslandMetrics.Nook.bodyTopInset
        case .nook(.aiUsage): IslandMetrics.Nook.aiUsageBody + IslandMetrics.Nook.bodyTopInset
        case .nook(.calendar): IslandMetrics.Nook.calendarBody + IslandMetrics.Nook.bodyTopInset
        case .nook(.clipboard):
            IslandMetrics.Nook.body + IslandMetrics.Nook.bodyTopInset + (home.hasClipboardSearch ? IslandMetrics.Nook.searchBar : 0)
        case .nook: IslandMetrics.Nook.body + IslandMetrics.Nook.bodyTopInset
        case .alert(.timerFinished): IslandMetrics.ContentHeight.timerFinished
        case .alert(.agentRequest(let request)):
            IslandMetrics.ContentHeight.agentRequest(lines: request.reviewLineCount(charactersPerLine: agentCharactersPerLine))
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
        layout.notchBand = isVirtualNotch ? 0 : notch.maxY

        if appearance.pitchBlack || appearance.theme == .glass {
            // Glass draws its own edge.
            layout.shadow = 0
            layout.stroke = 0
        }

        if isPill { layout = floating(layout, for: presentation) }
        layout.restingPill = layout.pill

        if hovering, presentation.isRestingPill {
            // Grows sideways and down; the top stays where it is.
            let growth = IslandMetrics.hoverGrowth(for: layout.pill.size)
            layout.pill = CGRect(
                x: layout.pill.minX - growth.width,
                y: layout.pill.minY,
                width: layout.pill.width + 2 * growth.width,
                height: layout.pill.height + growth.height
            )
            if isPill {
                layout.topRadius = layout.pill.height / 2
                layout.bottomRadius = layout.pill.height / 2
            }
            // The second activity's bubble moves out with the edge, so the gap stays, and lifts
            // with it, so the two stay the same height.
            if layout.bubble != .zero {
                layout.bubble = CGRect(
                    x: layout.bubble.minX + growth.width,
                    y: layout.bubble.minY,
                    width: layout.bubble.width + growth.height,
                    height: layout.bubble.height + growth.height
                )
            }
        }

        if layout.bubble == .zero {
            // A sliver at the shape's right side, as tall as it will be, so it slides out of the
            // side when it appears and back into it when it goes, like the Dynamic Island's.
            let height = min(layout.pill.height, bubbleDiameter)
            layout.bubble = CGRect(x: layout.pill.maxX - layout.flare - 1, y: layout.pill.minY, width: 0, height: height)
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
        case .idle where !isVirtualNotch:
            // With nothing going on, a real notch stays exactly the notch, whatever the size and
            // thickness settings: nothing shows around the camera.
            layout.pill = notch
            layout.flare = 0
            layout.bottomRadius = IslandMetrics.restingNotchRadius
            layout.content = layout.pill
        case .idle:
            layout.pill = shape(body: notch.width + 24, height: height, flare: IslandMetrics.compactFlare)
            layout.shadow = 0.2
            layout.content = layout.pill.insetBy(dx: IslandMetrics.compactFlare, dy: 0)
        case .compact(let primary, let secondary):
            layout.pill = shape(body: compactBodyWidth(for: primary), height: height, flare: IslandMetrics.compactFlare)
            layout.shadow = 0.3
            layout.content = layout.pill.insetBy(dx: IslandMetrics.compactFlare, dy: 0)
            layout.cameraGap = cameraGap
            if secondary != nil {
                let diameter = bubbleDiameter
                // Hangs from the top edge beside the shape, with the same corners.
                layout.bubble = CGRect(x: layout.pill.maxX + bubbleGap, y: layout.pill.minY, width: diameter, height: diameter)
            }
        case .alert(let alert) where !alert.usesExpandedLayout:
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
            let width = presentation == .expanded(.nowPlaying)
                ? max((expandedHeight(content: contentHeight) * IslandMetrics.nowPlayingAspect).rounded(), compactBodyWidth(for: .nowPlaying) + 40)
                : expandedWidth
            layout.pill = shape(body: width, height: expandedHeight(content: contentHeight), flare: IslandMetrics.expandedFlare)
            layout.flare = IslandMetrics.expandedFlare
            // Approvals fill their corners with the request and the buttons, so they keep
            // tighter corners.
            let radius = if case .alert = presentation { IslandMetrics.alertExpandedRadius } else { IslandMetrics.notchExpandedRadius }
            layout.bottomRadius = (radius * scale).rounded()
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

    /// Turns a notch layout into the floating pill: no shoulders, round ends, a little below the
    /// top edge. Everything inside moves down with it.
    private func floating(_ notchLayout: IslandLayout, for presentation: IslandPresentation) -> IslandLayout {
        var layout = notchLayout
        let top = IslandMetrics.pillTop
        layout.pill = layout.pill.insetBy(dx: layout.flare, dy: 0).offsetBy(dx: 0, dy: top)
        layout.flare = 0
        layout.content = layout.content.offsetBy(dx: 0, dy: top)
        if layout.bubble != .zero {
            layout.bubble.origin = CGPoint(x: layout.pill.maxX + floatingBubbleGap, y: layout.pill.minY)
        }
        let isOpen = layout.pill.height > alertBodySize.height + 1
        let radius = isOpen ? (IslandMetrics.pillExpandedRadius * scale).rounded() : layout.pill.height / 2
        layout.topRadius = radius
        layout.bottomRadius = radius
        if case .hidden(let peek) = presentation, !peek {
            // At rest it's a smaller, invisible pill in its spot, so it grows out of it.
            let width = (notch.width * 0.7).rounded()
            let height = (compactHeight * 0.7).rounded()
            layout.pill = CGRect(x: anchorX - width / 2, y: top + (compactHeight - height) / 2, width: width, height: height)
            layout.topRadius = height / 2
            layout.bottomRadius = height / 2
            layout.pillOpacity = 0
        }
        return layout
    }

    // MARK: Hit testing

    /// Where the pointer counts as resting on the hidden notch: the whole peek it swells into,
    /// so its edges count too.
    public var notchHoverRect: CGRect {
        let slop = IslandMetrics.hitSlop
        let notch = notchInWindow
        return CGRect(x: notch.minX - 10 - slop, y: 0, width: notch.width + 20 + 2 * slop, height: topOffset + notch.maxY + 3 + slop)
    }

    /// Where the pointer counts as on the second activity's bubble: the bubble and the gap
    /// beside it, so the shape's edge belongs to the shape and the gap to the bubble.
    public func bubbleHitRect(_ layout: IslandLayout) -> CGRect {
        let slop = IslandMetrics.hitSlop
        let gapStart = min(layout.bubble.minX, layout.pill.maxX)
        return CGRect(x: gapStart, y: layout.bubble.minY - slop, width: layout.bubble.maxX + slop - gapStart, height: layout.bubble.height + 2 * slop)
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
            height: topOffset + expandedHeight(content: IslandMetrics.ContentHeight.drop) + 24
        )
    }
}
