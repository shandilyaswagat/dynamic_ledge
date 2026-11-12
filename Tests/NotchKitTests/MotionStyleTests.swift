import SwiftUI
import Testing
@testable import NotchKit

@MainActor
@Suite("Motion style")
struct MotionStyleTests {
    @Test func standardOpensWithASmallOvershoot() {
        #expect(Motion.shape(to: .expanded(.nowPlaying), reduceMotion: false) == .spring(response: 0.37, dampingFraction: 0.65))
        #expect(Motion.shape(from: .compact(primary: .timer, secondary: nil), to: .expanded(.nowPlaying), reduceMotion: false) == .spring(response: 0.37, dampingFraction: 0.65))
        #expect(Motion.shape(to: .hidden(peek: false), reduceMotion: false) == .smooth(duration: 0.42))
        #expect(Motion.resize(.black) == Motion.resize)
        #expect(Motion.hover(.black) == Motion.hover)
    }

    @Test func springyBouncesMoreAndCalmNotAtAll() {
        for damping in [0.6, 0.68, 0.8, 0.92] {
            #expect(Motion.damping(damping, .springy) < damping)
            #expect(Motion.damping(damping, .springy) >= 0.56, "bouncy, never wobbly")
            #expect(Motion.damping(damping, .calm) == 1)
        }
        #expect(Motion.spring(0.48, 0.8, .calm) == .spring(response: 0.48 * 1.12, dampingFraction: 1))
        #expect(Motion.spring(0.48, 0.8, .springy) == .spring(response: 0.48 * 0.95, dampingFraction: 0.8 - 0.1))
    }

    @Test func closingNeverBounces() {
        let glassClose = Motion.shape(to: .hidden(peek: false), reduceMotion: false, theme: .glass, style: .springy)
        #expect(glassClose == .smooth(duration: 0.42), "Glass closes like Black")
        #expect(Motion.shape(to: .hidden(peek: false), reduceMotion: false, style: .springy) == .smooth(duration: 0.42))
    }

    @Test func closingToASmallerViewIsCriticallyDamped() {
        let compact = IslandPresentation.compact(primary: .timer, secondary: nil)
        for style in MotionStyle.allCases {
            for theme in NotchTheme.allCases {
                let close = Motion.shape(from: .expanded(.nowPlaying), to: compact, reduceMotion: false, theme: theme, style: style)
                let expected: Double = style == .calm ? 0.42 : 0.38
                #expect(close == .spring(response: expected, dampingFraction: 1), "\(style) \(theme)")
            }
        }
        #expect(Motion.isClosing(from: .nook(.home), to: .idle))
        #expect(!Motion.isClosing(from: .idle, to: compact))
        #expect(!Motion.isClosing(from: .nook(.home), to: .expanded(.timer)), "switching between open views isn't closing")
    }

    @Test func hoverLiftsByFivePercent() {
        #expect(IslandMetrics.hoverGrowth(for: CGSize(width: 200, height: 40)) == CGSize(width: 5, height: 2))
        #expect(IslandMetrics.hoverGrowth(for: CGSize(width: 60, height: 20)) == CGSize(width: 3, height: 2), "never less than before")
    }

    @Test func glassMovesLikeBlack() {
        for presentation: IslandPresentation in [.expanded(.nowPlaying), .nook(.home), .compact(primary: .timer, secondary: nil), .hidden(peek: true)] {
            for style in MotionStyle.allCases {
                #expect(Motion.shape(to: presentation, reduceMotion: false, theme: .glass, style: style)
                        == Motion.shape(to: presentation, reduceMotion: false, theme: .black, style: style))
            }
        }
    }

    @Test func bigPanelsBounceLess() {
        #expect(Motion.shape(to: .nook(.home), reduceMotion: false) == .spring(response: 0.4, dampingFraction: 0.74))
    }

    @Test func reduceMotionWins() {
        #expect(Motion.shape(to: .expanded(.nowPlaying), reduceMotion: true, style: .springy) == .easeInOut(duration: 0.2))
    }

    @Test func choiceIsRememberedAndStartsAtStandard() {
        let defaults = UserDefaults(suiteName: "motion-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.motionStyle == .standard)
        settings.motionStyle = .calm
        #expect(SettingsStore(defaults: defaults).motionStyle == .calm)
    }
}

@MainActor
@Suite("Resting notch")
struct RestingNotchTests {
    @Test func aRealNotchAtRestIsExactlyTheNotch() {
        let screen = ScreenMetrics(size: CGSize(width: 1470, height: 956), notch: CGRect(x: 645.5, y: 0, width: 179, height: 32), menuBarHeight: 32)
        for size in NotchSize.allCases {
            for height in [24.0, 32, 52] {
                for theme in NotchTheme.allCases {
                    var appearance = NotchAppearance.standard
                    appearance.size = size
                    appearance.height = height
                    appearance.width = NotchAppearance.widthRange.upperBound
                    appearance.theme = theme
                    let engine = LayoutEngine(screen: screen, appearance: appearance)
                    for presentation: IslandPresentation in [.idle, .hidden(peek: false)] {
                        let pill = engine.layout(for: presentation, homeHasMedia: false, hovering: false).pill
                        #expect(engine.notchInWindow.insetBy(dx: -0.5, dy: -0.5).contains(pill),
                                "\(presentation) \(size) \(height) \(theme)")
                    }
                }
            }
        }
    }

    @Test func aScreenWithoutANotchStillShowsIdle() {
        let screen = ScreenMetrics(size: CGSize(width: 1920, height: 1080), notch: nil, menuBarHeight: 24)
        let engine = LayoutEngine(screen: screen, appearance: .standard)
        let idle = engine.layout(for: .idle, homeHasMedia: false, hovering: false).pill
        #expect(idle.width > engine.notchInWindow.width, "nothing to hide behind, so it shows")
    }
}

@MainActor
@Suite("Dynamic Island proportions")
struct IslandProportionTests {
    private let macBook = ScreenMetrics(size: CGSize(width: 1470, height: 956), notch: CGRect(x: 645.5, y: 0, width: 179, height: 32), menuBarHeight: 32)

    private var engine: LayoutEngine {
        var appearance = NotchAppearance.standard
        appearance.size = .large
        return LayoutEngine(screen: macBook, appearance: appearance)
    }

    @Test func musicHugsTheCameraButTimersKeepTheirRoom() {
        let music = engine.layout(for: .compact(primary: .nowPlaying, secondary: nil), homeHasMedia: true, hovering: false)
        let timer = engine.layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: false)
        #expect(music.pill.width - 2 * music.flare == CGFloat(179 + 2 * 33))
        #expect(timer.pill.width - 2 * timer.flare == engine.compactBodyWidth)
        #expect(music.pill.width < timer.pill.width)
    }

    @Test func wideSettingsStillWidenMusic() {
        var appearance = NotchAppearance.standard
        appearance.size = .large
        appearance.width = 360
        let wide = LayoutEngine(screen: macBook, appearance: appearance)
        #expect(wide.compactBodyWidth(for: .nowPlaying) > engine.compactBodyWidth(for: .nowPlaying) + 100)
    }

    @Test func narrowAIUsageNotchFitsTheFullPercentage() throws {
        for size in NotchSize.allCases {
            for height in [32.0, 38, 52] {
                let appearance = NotchAppearance(width: NotchAppearance.widthRange.lowerBound, height: height, size: size)
                let engine = LayoutEngine(screen: macBook, appearance: appearance)
                let layout = engine.layout(for: .compact(primary: .aiUsage, secondary: nil), homeHasMedia: false, hovering: false)
                let scale = CompactScale(height: layout.content.height, size: size.scale)
                let available = (layout.content.width - layout.cameraGap) / 2 - scale.edge - CompactScale.cameraClearance
                let renderer = ImageRenderer(content: AIUsageCompactValue(remaining: 100, fontSize: scale.fontSize))
                let badge = try #require(renderer.cgImage)
                #expect(CGFloat(badge.width) <= available)
            }
        }
    }

    @Test func openMusicHasThePlayersProportions() {
        let layout = engine.layout(for: .expanded(.nowPlaying), home: HomeContent(hasMedia: true), hovering: false)
        let aspect = layout.pill.insetBy(dx: layout.flare, dy: 0).width / layout.pill.height
        #expect(abs(aspect - IslandMetrics.nowPlayingAspect) < 0.02)
        #expect(layout.bottomRadius == IslandMetrics.notchExpandedRadius)
    }

    @Test func hoverLiftsTheShapeButNotTheContentBox() {
        let rest = engine.layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: false)
        let hover = engine.layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: true)
        #expect(hover.pill.width > rest.pill.width)
        #expect(hover.restingPill == rest.pill)
        #expect(hover.content == rest.content)
    }

    @Test func hoverKeepsTheGapToTheSecondActivity() {
        let presentation = IslandPresentation.compact(primary: .nowPlaying, secondary: .timer)
        for hovering in [false, true] {
            let layout = engine.layout(for: presentation, homeHasMedia: true, hovering: hovering)
            #expect(layout.bubble.minX - layout.pill.maxX >= 4, "hovering \(hovering)")
        }
    }

    @Test func openContentStretchesWithTheShapeWhileItSprings() {
        let resting = CGSize(width: 340, height: 190)
        let early = StretchWithShell.scale(current: CGSize(width: 170, height: 40), resting: resting, isOpenView: true, stretches: true)
        #expect(early == CGSize(width: StretchWithShell.minimumOpenScale, height: StretchWithShell.minimumOpenScale), "even, never squashed")
        let growing = StretchWithShell.scale(current: CGSize(width: 272, height: 120), resting: resting, isOpenView: true, stretches: true)
        #expect(abs(growing.width - 0.8) < 0.001 && growing.width == growing.height)
        let overshoot = StretchWithShell.scale(current: CGSize(width: 362, height: 202), resting: resting, isOpenView: true, stretches: true)
        #expect(overshoot.width > 1 && overshoot.width == overshoot.height)
        #expect(StretchWithShell.scale(current: CGSize(width: 170, height: 95), resting: resting, isOpenView: true, stretches: false) == CGSize(width: 1, height: 1),
                "a resize after it settles doesn't squash it")
    }

    @Test func compactContentOnlyLiftsWithHover() {
        let resting = CGSize(width: 245, height: 32)
        let lifted = StretchWithShell.scale(current: CGSize(width: 257, height: 34), resting: resting, isOpenView: false, stretches: true)
        #expect(lifted.width > 1 && lifted.width <= IslandMetrics.hoverScale)
        let opening = StretchWithShell.scale(current: CGSize(width: 500, height: 200), resting: resting, isOpenView: false, stretches: true)
        #expect(opening.width == IslandMetrics.hoverScale, "never blown up as the shape opens")
        let shrunk = StretchWithShell.scale(current: CGSize(width: 180, height: 31), resting: resting, isOpenView: false, stretches: true)
        #expect(shrunk == CGSize(width: 1, height: 1))
    }
}
