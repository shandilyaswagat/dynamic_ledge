import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("Pill style on displays without a notch")
struct PillStyleTests {
    private let external = ScreenMetrics(size: CGSize(width: 1920, height: 1080), notch: nil, menuBarHeight: 25)
    private var pill: NotchAppearance {
        var appearance = NotchAppearance.standard
        appearance.externalStyle = .pill
        return appearance
    }

    @Test func notchIsTheDefault() {
        #expect(NotchAppearance.standard.externalStyle == .notch)
        #expect(!LayoutEngine(screen: external, appearance: .standard).isPill)
    }

    @Test func aMacBookNotchStaysANotch() {
        let engine = LayoutEngine(screen: .sample, appearance: pill)
        #expect(!engine.isPill)
        let layout = engine.layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: false)
        #expect(layout.pill.minY == 0)
        #expect(layout.flare > 0)
    }

    @Test func compactPillFloatsWithRoundEnds() {
        let engine = LayoutEngine(screen: external, appearance: pill)
        #expect(engine.isPill)
        let layout = engine.layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: false)
        #expect(layout.pill.minY == IslandMetrics.pillTop)
        #expect(layout.flare == 0)
        #expect(layout.topRadius == layout.pill.height / 2)
        #expect(layout.bottomRadius == layout.pill.height / 2)
        #expect(layout.pill.midX == engine.anchorX)
    }

    @Test func openPillMovesItsContentDownWithIt() {
        let notch = LayoutEngine(screen: external, appearance: .standard).layout(for: .expanded(.timer), homeHasMedia: false, hovering: false)
        let engine = LayoutEngine(screen: external, appearance: pill)
        let layout = engine.layout(for: .expanded(.timer), homeHasMedia: false, hovering: false)
        #expect(layout.pill.minY == IslandMetrics.pillTop)
        #expect(layout.topRadius == IslandMetrics.pillExpandedRadius)
        #expect(layout.content.minY == notch.content.minY + IslandMetrics.pillTop)
        #expect(layout.pill.maxY <= engine.windowSize.height)
    }

    @Test func restsInvisibleInItsSpot() {
        let engine = LayoutEngine(screen: external, appearance: pill)
        let layout = engine.layout(for: .hidden(peek: false), homeHasMedia: false, hovering: false)
        #expect(layout.pillOpacity == 0)
        #expect(layout.pill.minY > IslandMetrics.pillTop)
        #expect(engine.notchHoverRect.contains(CGPoint(x: engine.anchorX, y: layout.pill.midY)))
    }

    @Test func theChoiceIsSaved() {
        let defaults = UserDefaults(suiteName: "PillStyle-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.appearance.externalStyle = .pill
        #expect(SettingsStore(defaults: defaults).appearance.externalStyle == .pill)
    }
}
