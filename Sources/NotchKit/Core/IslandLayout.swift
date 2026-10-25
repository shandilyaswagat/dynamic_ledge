import CoreGraphics
import SwiftUI

/// Where every black shape goes, in window coordinates (top-left origin).
public struct IslandLayout: Equatable, Sendable {
    public var canvasSize: CGSize
    /// Bounds of the main shape, including the notch-style shoulders.
    public var pill: CGRect
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    /// Notch style: radius of the concave shoulders at the top edge. Zero in island style.
    public var flare: CGFloat
    public var pillOpacity: Double
    /// The minimal bubble. Zero-sized and tucked inside the shape when there is no second activity.
    public var bubble: CGRect
    /// Island style: a copy of the notch drawn only while shapes melt, so the pill drips out of it.
    public var notch: CGRect?
    public var notchRadius: CGFloat
    /// Liquid strength that persists at rest (the island hover droplet).
    public var gooBase: Double
    public var shadow: Double
    public var stroke: Double
    /// Where content is laid out, in window coordinates. Not animated; content swaps instead.
    public var content: CGRect
    /// Width kept clear in the middle of the content for the camera (notch style compact/alerts).
    public var cameraGap: CGFloat
    /// True when the shape is fused to the top edge of the screen.
    public var isAttachedToTop: Bool
    /// Notch style Home tabs: height of the strip beside the camera that holds the tab header.
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
        notch: CGRect? = nil,
        notchRadius: CGFloat = 9,
        gooBase: Double = 0,
        shadow: Double = 0,
        stroke: Double = 0,
        content: CGRect = .zero,
        cameraGap: CGFloat = 0,
        isAttachedToTop: Bool = false,
        contentScale: CGFloat = 1
    ) {
        self.canvasSize = canvasSize
        self.pill = pill
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.flare = flare
        self.pillOpacity = pillOpacity
        self.bubble = bubble
        self.notch = notch
        self.notchRadius = notchRadius
        self.gooBase = gooBase
        self.shadow = shadow
        self.stroke = stroke
        self.content = content
        self.cameraGap = cameraGap
        self.isAttachedToTop = isAttachedToTop
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
                gooBase, shadow, stroke, 0
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
            gooBase = max(0, v[12])
            shadow = max(0, v[13])
            stroke = max(0, v[14])
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

    public var style: NotchStyle { appearance.style }

    /// Small / Medium / Large multiplier.
    public var scale: CGFloat { appearance.size.scale }

    // MARK: Shared measurements

    /// Top edge of the shape: the screen edge in notch style, below the notch in island style.
    public var pillTop: CGFloat {
        switch style {
        case .notch: 0
        case .island: max(0, screen.topInset + appearance.verticalOffset)
        }
    }

    /// Thickness of the compact shape.
    public var compactHeight: CGFloat {
        switch style {
        case .notch: max(appearance.height, screen.topInset)
        case .island: appearance.height
        }
    }

    /// Width of the camera housing, or of a virtual one on displays without a notch.
    private var baseWidth: CGFloat {
        screen.notch?.width ?? IslandMetrics.virtualNotchWidth
    }

    /// Width the compact content must keep clear for the camera.
    public var cameraGap: CGFloat {
        style == .notch ? (screen.notch?.width ?? 0) : 0
    }

    private var earWidth: CGFloat {
        (IslandMetrics.earWidth(appearance, height: compactHeight) * scale).rounded()
    }

    /// Width of the compact shape without shoulders.
    public var compactBodyWidth: CGFloat {
        switch style {
        case .notch: baseWidth + 2 * earWidth
        case .island: IslandMetrics.compactSize(appearance).width
        }
    }

    /// Volume and brightness use a slimmer shape than other alerts.
    private func alertBodySize(for alert: IslandAlert) -> CGSize {
        switch alert {
        case .upcomingEvent, .shortcut, .download:
            // Names need room beside the camera.
            switch style {
            case .notch:
                return CGSize(width: baseWidth + 2 * max(earWidth, (IslandMetrics.namedAlertEarWidth * scale).rounded()), height: compactHeight + (6 * scale).rounded())
            case .island:
                let base = alertBodySize
                return CGSize(width: base.width + (60 * scale).rounded(), height: base.height)
            }
        case .level:
            break
        default:
            return alertBodySize
        }
        switch style {
        case .notch:
            return CGSize(width: baseWidth + 2 * max(earWidth, (IslandMetrics.levelEarWidth * scale).rounded()), height: compactHeight)
        case .island:
            return CGSize(width: (IslandMetrics.levelPillWidth * scale).rounded(), height: appearance.height)
        }
    }

    private var alertBodySize: CGSize {
        switch style {
        case .notch:
            CGSize(
                width: baseWidth + 2 * max(earWidth, (IslandMetrics.alertEarWidth * scale).rounded()),
                height: compactHeight + (6 * scale).rounded()
            )
        case .island:
            CGSize(
                width: (IslandMetrics.alertSize(appearance).width * scale).rounded(),
                height: appearance.height + (16 * scale).rounded()
            )
        }
    }

    public var expandedWidth: CGFloat {
        switch style {
        case .notch: max((IslandMetrics.expandedWidth(appearance) * scale).rounded(), compactBodyWidth + 40)
        case .island: (IslandMetrics.expandedWidth(appearance) * scale).rounded()
        }
    }

    /// Width of the Home / Tray / Mirror nook.
    public var nookWidth: CGFloat {
        let width = (IslandMetrics.Nook.width * scale).rounded()
        switch style {
        case .notch: return max(width, compactBodyWidth + 40)
        case .island: return width
        }
    }

    private func expandedHeight(content: CGFloat) -> CGFloat {
        switch style {
        case .notch: screen.topInset + IslandMetrics.notchContentGap + content + (IslandMetrics.notchBottomPadding * scale).rounded()
        case .island: content + 2 * (IslandMetrics.islandExpandedPadding * scale).rounded()
        }
    }

    private var bubbleDiameter: CGFloat {
        style == .notch ? max(((compactHeight - 6) * scale).rounded(), 16) : appearance.height
    }

    private var bubbleGap: CGFloat {
        style == .notch ? 4 : IslandMetrics.bubbleGap(appearance)
    }

    private var widestContent: CGFloat {
        max(
            max(expandedWidth, nookWidth) + 2 * IslandMetrics.expandedFlare,
            compactBodyWidth + 2 * (IslandMetrics.compactFlare + bubbleGap + bubbleDiameter + IslandMetrics.hoverGrowth.width),
            alertBodySize.width + 2 * IslandMetrics.compactFlare
        )
    }

    /// Fixed for a display: full width and tall enough for any setting, so neither settings nor
    /// presentations ever move the window under content that is animating.
    public var windowSize: CGSize {
        let tallestShape = screen.topInset
            + NotchAppearance.verticalOffsetRange.upperBound
            + IslandMetrics.ContentHeight.maximum
            + 2 * IslandMetrics.islandExpandedPadding
            + IslandMetrics.activityHeader
        return CGSize(
            width: screen.size.width,
            height: min(screen.size.height, (tallestShape + IslandMetrics.windowMargin).rounded(.up))
        )
    }

    /// Centre of the shape on the display. Notch style always centres on the notch.
    public var anchorScreenX: CGFloat {
        let half = widestContent / 2 + IslandMetrics.screenEdgeInset
        let lower = half
        let upper = screen.size.width - half
        guard lower <= upper else { return screen.size.width / 2 }
        let offset = style == .island ? appearance.horizontalOffset : 0
        return min(max(screen.centerX + offset, lower), upper)
    }

    /// Left edge of the window on the display. The window spans the display, so window and
    /// display coordinates match.
    public var windowOriginX: CGFloat { 0 }

    /// Centre of the shape in window coordinates.
    public var anchorX: CGFloat {
        anchorScreenX - windowOriginX
    }

    public var notchInWindow: CGRect? {
        screen.notch?.offsetBy(dx: -windowOriginX, dy: 0)
    }

    /// Island style: true when the pill hangs under the notch and can retract into it.
    public var isUnderNotch: Bool {
        guard let notch = notchInWindow else { return false }
        return abs(anchorX - notch.midX) <= notch.width / 2
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
        case .nook(let tab):
            IslandMetrics.ContentHeight.nook + (tab == .launcher ? IslandMetrics.Nook.launcherBody - IslandMetrics.Nook.body : 0)
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
        var layout = switch style {
        case .notch: notchLayout(for: presentation, home: home)
        case .island: islandLayout(for: presentation, home: home)
        }
        layout.contentScale = scale

        if hovering, presentation.isRestingPill {
            let growth = IslandMetrics.hoverGrowth
            if layout.isAttachedToTop {
                layout.pill = CGRect(
                    x: layout.pill.minX - growth.width,
                    y: layout.pill.minY,
                    width: layout.pill.width + 2 * growth.width,
                    height: layout.pill.height + growth.height
                )
            } else {
                layout.pill = layout.pill.insetBy(dx: -growth.width, dy: -growth.height / 2)
                layout.topRadius += growth.height / 2
                layout.bottomRadius += growth.height / 2
            }
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
            flare: IslandMetrics.compactFlare,
            isAttachedToTop: true
        )

        switch presentation {
        case .hidden(let peek):
            if let notch = notchInWindow {
                if peek {
                    // The notch swells a little to show it can be clicked.
                    layout.pill = shape(body: notch.width + 20, height: notch.height + 3, flare: 5)
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
            } else {
                layout.pill = CGRect(x: centerX - baseWidth * 0.3, y: 0, width: baseWidth * 0.6, height: 0)
                layout.flare = 0
                layout.bottomRadius = 0
                layout.pillOpacity = 0
            }
        case .idle:
            layout.pill = shape(body: baseWidth + 24, height: height, flare: IslandMetrics.compactFlare)
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
            let width = nookWidth
            let strip = screen.topInset
            let body = ((presentation == .nook(.launcher) ? IslandMetrics.Nook.launcherBody : IslandMetrics.Nook.body) * scale).rounded()
                + (IslandMetrics.Nook.bodyTopInset * scale).rounded()
            let height = strip + IslandMetrics.notchContentGap + body + (IslandMetrics.notchBottomPadding * scale).rounded()
            layout.pill = shape(body: width, height: height, flare: IslandMetrics.expandedFlare)
            layout.flare = IslandMetrics.expandedFlare
            layout.bottomRadius = (IslandMetrics.notchExpandedRadius * scale).rounded()
            layout.shadow = 1
            layout.content = CGRect(x: centerX - width / 2, y: 0, width: width, height: strip + IslandMetrics.notchContentGap + body)
            layout.stripHeight = strip
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
                y: screen.topInset + IslandMetrics.notchContentGap,
                width: width,
                height: contentHeight
            )
        }
        return layout
    }

    private func islandLayout(for presentation: IslandPresentation, home: HomeContent) -> IslandLayout {
        let top = pillTop
        func centered(_ size: CGSize) -> CGRect {
            CGRect(x: anchorX - size.width / 2, y: top, width: size.width, height: size.height)
        }
        let notchReplica = notchInWindow.map {
            // Inset so the copy always stays hidden behind the real notch, and extended above the
            // window so its top edge never softens during the liquid blur.
            CGRect(x: $0.minX + 3, y: -16, width: $0.width - 6, height: $0.height + 16 - 1.5)
        }
        var layout = IslandLayout(canvasSize: windowSize, pill: .zero, topRadius: 0, bottomRadius: 0, notch: notchReplica)

        // A rounded rectangle rather than a full capsule: it reads as an object sitting on the
        // screen, the way Apple's floating panels do.
        func capsule(_ rect: CGRect) {
            let radius = min(rect.height / 2, (rect.height * IslandMetrics.islandCornerRatio).rounded())
            layout.pill = rect
            layout.topRadius = radius
            layout.bottomRadius = radius
            layout.content = rect
        }

        switch presentation {
        case .hidden(let peek):
            if isUnderNotch, let notch = notchInWindow {
                if peek {
                    layout.pill = CGRect(x: notch.midX - notch.width * 0.28, y: notch.maxY - 12, width: notch.width * 0.56, height: 18)
                    layout.topRadius = 9
                    layout.bottomRadius = 9
                    layout.gooBase = 1
                } else {
                    layout.pill = CGRect(x: notch.midX - notch.width * 0.3, y: notch.maxY - 12, width: notch.width * 0.6, height: 0)
                }
            } else {
                let idle = IslandMetrics.idleSize(appearance)
                layout.pill = CGRect(x: anchorX - idle.width / 4, y: top + idle.height / 4, width: idle.width / 2, height: idle.height / 2)
                layout.topRadius = idle.height / 4
                layout.bottomRadius = idle.height / 4
                layout.pillOpacity = 0
            }
        case .idle:
            capsule(centered(IslandMetrics.idleSize(appearance)))
            layout.shadow = 0.2
            layout.stroke = 0.6
        case .compact(_, let secondary):
            capsule(centered(IslandMetrics.compactSize(appearance)))
            layout.shadow = 0.3
            layout.stroke = 0.6
            if secondary != nil {
                let size = appearance.height
                layout.bubble = CGRect(x: layout.pill.maxX + bubbleGap, y: top, width: size, height: size)
            }
        case .alert(let alert) where alert != .timerFinished:
            capsule(centered(alertBodySize(for: alert)))
            layout.shadow = 0.6
            layout.stroke = 1
        default:
            let contentHeight = expandedContentHeight(for: presentation, home: home) ?? IslandMetrics.ContentHeight.timer
            let width = presentation.homeTab == nil ? expandedWidth : nookWidth
            // An open activity gets a row on top for the back button, so Home is always one click away.
            let header: CGFloat = if case .expanded = presentation { (IslandMetrics.activityHeader * scale).rounded() } else { 0 }
            let size = CGSize(width: width, height: expandedHeight(content: contentHeight) + header)
            layout.pill = centered(size)
            let radius = min((IslandMetrics.islandExpandedRadius * scale).rounded(), size.height / 2)
            layout.topRadius = radius
            layout.bottomRadius = radius
            layout.shadow = 1
            layout.stroke = 1
            layout.content = CGRect(
                x: layout.pill.minX,
                y: top + (IslandMetrics.islandExpandedPadding * scale).rounded() + header,
                width: size.width,
                height: contentHeight
            )
        }
        return layout
    }

    // MARK: Hit testing

    /// Areas that should receive the mouse, in window coordinates.
    public func interactiveRects(for presentation: IslandPresentation, layout: IslandLayout) -> [CGRect] {
        let slop = IslandMetrics.hitSlop
        switch presentation {
        case .hidden:
            guard let notch = notchInWindow, style == .notch || isUnderNotch else { return [] }
            // The whole peek the notch swells into on hover, so its edges count too.
            return [CGRect(x: notch.minX - 10 - slop, y: 0, width: notch.width + 20 + 2 * slop, height: notch.maxY + 3 + slop)]
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
            height: pillTop + expandedHeight(content: IslandMetrics.ContentHeight.drop) + 24
        )
    }
}
