import CoreGraphics
import Testing
@testable import NotchKit

@Suite("Layout: notch style")
struct NotchLayoutTests {
    let screen = ScreenMetrics.sample
    var engine: LayoutEngine { LayoutEngine(screen: screen, appearance: .standard) }

    private func layout(_ presentation: IslandPresentation, hovering: Bool = false, media: Bool = false) -> IslandLayout {
        engine.layout(for: presentation, homeHasMedia: media, hovering: hovering)
    }

    @Test func standardIsNotchStyle() {
        #expect(NotchAppearance.standard.style == .notch)
        #expect(NotchAppearance.standard.pitchBlack)
    }

    @Test func everyShapeIsFusedToTheTopEdge() {
        let presentations: [IslandPresentation] = [
            .hidden(peek: false), .hidden(peek: true), .idle,
            .compact(primary: .timer, secondary: .nowPlaying), .expanded(.nowPlaying), .home,
            .alert(.charging(level: 50, isCharging: true)), .alert(.timerFinished), .drop(targeted: true),
        ]
        for presentation in presentations {
            let result = layout(presentation)
            #expect(result.pill.minY == 0, "\(presentation) should start at the screen edge")
            #expect(result.isAttachedToTop)
        }
    }

    @Test func centredOnTheNotch() throws {
        let notch = try #require(engine.notchInWindow)
        for presentation in [IslandPresentation.compact(primary: .timer, secondary: nil), .home, .alert(.lowBattery(level: 10))] {
            #expect(abs(layout(presentation).pill.midX - notch.midX) < 0.001)
        }
    }

    @Test func hiddenShapeStaysInsideTheRealNotch() throws {
        let notch = try #require(engine.notchInWindow)
        let hidden = layout(.hidden(peek: false))
        #expect(notch.contains(hidden.pill))
        #expect(hidden.flare == 0)
        #expect(hidden.pillOpacity == 0, "nothing drawn at rest, so screenshots stay clean")
        #expect(layout(.hidden(peek: true)).pillOpacity == 1)
    }

    @Test func peekSwellsTheNotchSlightly() throws {
        let notch = try #require(engine.notchInWindow)
        let peek = layout(.hidden(peek: true)).pill
        #expect(peek.width > notch.width && peek.width < notch.width + 40)
        #expect(peek.height > notch.height && peek.height < notch.height + 6)
    }

    @Test func compactKeepsTheCameraClearAndHasEars() throws {
        let notch = try #require(engine.notchInWindow)
        let compact = layout(.compact(primary: .timer, secondary: nil))
        #expect(compact.cameraGap == notch.width)
        #expect(compact.content.minX < notch.minX - 30)
        #expect(compact.content.maxX > notch.maxX + 30)
        #expect(compact.pill.height == notch.height)
    }

    @Test func thicknessNeverGoesBelowTheNotch() throws {
        let notch = try #require(screen.notch)
        var thin = NotchAppearance.standard
        thin.height = 24
        let engine = LayoutEngine(screen: screen, appearance: thin)
        #expect(engine.compactHeight == notch.height)
        thin.height = 44
        #expect(LayoutEngine(screen: screen, appearance: thin).compactHeight == 44)
    }

    @Test func widthSettingWidensTheEars() {
        var narrow = NotchAppearance.standard
        narrow.width = 120
        var wide = NotchAppearance.standard
        wide.width = 420
        let small = LayoutEngine(screen: screen, appearance: narrow).compactBodyWidth
        let large = LayoutEngine(screen: screen, appearance: wide).compactBodyWidth
        #expect(large > small + 200)
        #expect(small > (screen.notch?.width ?? 0) + 40, "ears never vanish")
    }

    @Test func expandedContentSitsBelowTheNotch() throws {
        let notch = try #require(screen.notch)
        for presentation in [IslandPresentation.expanded(.nowPlaying), .expanded(.timer), .drop(targeted: false), .alert(.timerFinished)] {
            let result = layout(presentation)
            #expect(result.content.minY >= notch.maxY)
            #expect(result.cameraGap == 0)
            #expect(result.pill.contains(result.content))
            #expect(result.pill.maxY - result.content.maxY >= 10, "bottom padding")
        }
    }

    @Test func homeIsTheSameSizeWithOrWithoutMedia() {
        #expect(layout(.home, media: true).pill == layout(.home, media: false).pill)
    }

    @Test func bubbleSitsBesideTheShape() {
        let result = layout(.compact(primary: .timer, secondary: .nowPlaying))
        #expect(result.bubble.minX > result.pill.maxX)
        #expect(result.bubble.width == result.bubble.height)
        #expect(result.bubble.maxY <= result.pill.maxY)
        let single = layout(.compact(primary: .timer, secondary: nil))
        #expect(single.bubble.width == 0, "absent bubble is tucked away")
        #expect(single.pill.contains(CGPoint(x: single.bubble.midX, y: single.bubble.midY)))
    }

    @Test func hoverGrowsDownwardOnly() {
        let rest = layout(.compact(primary: .timer, secondary: nil))
        let hover = layout(.compact(primary: .timer, secondary: nil), hovering: true)
        #expect(hover.pill.minY == 0)
        #expect(hover.pill.height > rest.pill.height)
        #expect(hover.pill.width > rest.pill.width)
        #expect(hover.content == rest.content, "content doesn't move on hover")
        #expect(layout(.home, hovering: true) == layout(.home), "expanded views don't grow on hover")
    }

    @Test func pitchBlackRemovesShadowAndOutline() {
        for presentation in [IslandPresentation.compact(primary: .timer, secondary: nil), .home, .alert(.lowBattery(level: 20))] {
            let result = layout(presentation)
            #expect(result.shadow == 0)
            #expect(result.stroke == 0)
        }
        var soft = NotchAppearance.standard
        soft.pitchBlack = false
        let shaded = LayoutEngine(screen: screen, appearance: soft).layout(for: .home, homeHasMedia: false, hovering: false)
        #expect(shaded.shadow > 0)
    }

    @Test func everyShapeFitsTheWindow() {
        var extreme = NotchAppearance.standard
        extreme.width = NotchAppearance.widthRange.upperBound
        extreme.height = NotchAppearance.heightRange.upperBound
        let engine = LayoutEngine(screen: screen, appearance: extreme)
        let bounds = CGRect(origin: .zero, size: engine.windowSize)
        let presentations: [IslandPresentation] = [
            .compact(primary: .timer, secondary: .call), .expanded(.nowPlaying), .home, .alert(.headphones(name: "A", symbol: "airpods")),
            .alert(.timerFinished), .drop(targeted: false),
        ]
        for presentation in presentations {
            let result = engine.layout(for: presentation, homeHasMedia: true, hovering: true)
            #expect(bounds.contains(result.pill), "\(presentation)")
            #expect(result.bubble.width == 0 || bounds.contains(result.bubble), "\(presentation)")
        }
    }

    @Test func screenWithoutNotchUsesAVirtualOne() {
        let external = ScreenMetrics(size: CGSize(width: 1920, height: 1080), notch: nil, menuBarHeight: 24)
        let engine = LayoutEngine(screen: external, appearance: .standard)
        let hidden = engine.layout(for: .hidden(peek: false), homeHasMedia: false, hovering: false)
        #expect(hidden.pill.height == 0, "nothing drawn when idle")
        let compact = engine.layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: false)
        #expect(compact.pill.height == 32)
        #expect(compact.cameraGap == 0)
        #expect(abs(compact.pill.midX + engine.windowOriginX - 960) < 0.001)
        #expect(engine.interactiveRects(for: .hidden(peek: false), layout: hidden).isEmpty)
    }

    @Test func notchIsClickableWhenHidden() throws {
        let notch = try #require(engine.notchInWindow)
        let rects = engine.interactiveRects(for: .hidden(peek: false), layout: layout(.hidden(peek: false)))
        #expect(rects.contains { $0.contains(CGPoint(x: notch.midX, y: notch.midY)) })
    }

    @Test func horizontalOffsetIgnoredInNotchStyle() {
        var shifted = NotchAppearance.standard
        shifted.horizontalOffset = 300
        #expect(LayoutEngine(screen: screen, appearance: shifted).anchorScreenX == engine.anchorScreenX)
    }
}

@Suite("Layout: floating pill style")
struct IslandLayoutTests {
    let screen = ScreenMetrics.sample
    var appearance: NotchAppearance {
        NotchAppearance(style: .island, width: 180, height: 34, verticalOffset: 6, horizontalOffset: 0, pitchBlack: false)
    }
    var engine: LayoutEngine { LayoutEngine(screen: screen, appearance: appearance) }

    @Test func floatsBelowTheNotch() throws {
        let notch = try #require(engine.notchInWindow)
        let compact = engine.layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: false)
        #expect(compact.pill.minY == notch.maxY + 6)
        #expect(compact.pill.height == 34)
        // A rounded rectangle, not a full capsule.
        #expect(compact.topRadius == 13 && compact.bottomRadius == 13)
        #expect(compact.flare == 0)
        #expect(!compact.isAttachedToTop)
    }

    @Test func horizontalOffsetMovesThePillButStaysOnScreen() {
        var moved = appearance
        moved.horizontalOffset = 200
        let shifted = LayoutEngine(screen: screen, appearance: moved)
        #expect(shifted.anchorScreenX == screen.centerX + 200)
        moved.horizontalOffset = 600
        let far = LayoutEngine(screen: screen, appearance: moved)
        #expect(far.windowOriginX + far.windowSize.width <= screen.size.width)
        #expect(far.anchorScreenX < screen.size.width - 200)
    }

    @Test func hiddenRetractsIntoTheNotch() throws {
        let notch = try #require(engine.notchInWindow)
        let hidden = engine.layout(for: .hidden(peek: false), homeHasMedia: false, hovering: false)
        #expect(hidden.pill.height == 0)
        #expect(hidden.pill.minY < notch.maxY)
        let peek = engine.layout(for: .hidden(peek: true), homeHasMedia: false, hovering: false)
        #expect(peek.gooBase == 1)
    }

    @Test func negativeOffsetCanTouchTheTop() {
        var up = appearance
        up.verticalOffset = -40
        #expect(LayoutEngine(screen: screen, appearance: up).pillTop == 0)
    }

    @Test func expandedHasPaddingAroundContent() {
        // An open activity also has the back-button row above its content.
        let expanded = engine.layout(for: .expanded(.timer), homeHasMedia: false, hovering: false)
        #expect(expanded.content.minY - expanded.pill.minY == IslandMetrics.islandExpandedPadding + IslandMetrics.activityHeader)
        #expect(expanded.pill.maxY - expanded.content.maxY == IslandMetrics.islandExpandedPadding)
        let home = engine.layout(for: .home, homeHasMedia: false, hovering: false)
        #expect(home.content.minY - home.pill.minY == IslandMetrics.islandExpandedPadding)
    }

    @Test func everyOpenActivityFitsTheWindow() {
        for kind in ActivityKind.allCases {
            let layout = engine.layout(for: .expanded(kind), homeHasMedia: true, hovering: false)
            #expect(layout.pill.maxY <= engine.windowSize.height)
        }
    }
}

@Suite("Shape path")
struct IslandPathTests {
    @Test func emptyRectGivesEmptyPath() {
        #expect(IslandPath.path(in: .zero, topRadius: 4, bottomRadius: 4, flare: 4).isEmpty)
    }

    @Test func notchOutlineCoversItsBodyButNotTheShoulderGap() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
        let path = IslandPath.path(in: rect, topRadius: 0, bottomRadius: 12, flare: 6)
        #expect(path.contains(CGPoint(x: 100, y: 16)))
        #expect(path.contains(CGPoint(x: 5, y: 0.5)), "shoulder fills the top corner")
        #expect(!path.contains(CGPoint(x: 1, y: 20)), "below the shoulder is outside")
        #expect(!path.contains(CGPoint(x: 7, y: 31.5)), "bottom corner is rounded")
    }

    @Test func capsuleWhenNoFlare() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 30)
        let path = IslandPath.path(in: rect, topRadius: 15, bottomRadius: 15, flare: 0)
        #expect(path.contains(CGPoint(x: 50, y: 15)))
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
    }

    @Test func layoutAnimatableRoundTrip() {
        var layout = LayoutEngine(screen: .sample, appearance: .standard)
            .layout(for: .compact(primary: .timer, secondary: .call), homeHasMedia: false, hovering: false)
        let original = layout
        layout.animatableData = original.animatableData
        #expect(layout == original)
        var vector = original.animatableData
        vector.scale(by: 2)
        #expect(abs(vector.storage[2] - Double(original.pill.width) * 2) < 1e-9)
        let difference = (vector - original.animatableData).storage - original.animatableData.storage
        #expect((difference * difference).sum() < 1e-12)
    }
}
