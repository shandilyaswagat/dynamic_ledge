import SwiftUI
import Testing
@testable import NotchKit

@MainActor
@Suite("Motion style")
struct MotionStyleTests {
    @Test func standardKeepsTheOriginalSprings() {
        #expect(Motion.shape(to: .expanded(.nowPlaying), reduceMotion: false) == .spring(response: 0.48, dampingFraction: 0.8))
        #expect(Motion.shape(to: .hidden(peek: false), reduceMotion: false) == .smooth(duration: 0.42))
        #expect(Motion.resize(.black) == Motion.resize)
        #expect(Motion.hover(.black) == Motion.hover)
    }

    @Test func springyBouncesMoreAndCalmNotAtAll() {
        for damping in [0.6, 0.68, 0.8, 0.92] {
            #expect(Motion.damping(damping, .springy) < damping)
            #expect(Motion.damping(damping, .springy) >= 0.5, "never wobbly")
            #expect(Motion.damping(damping, .calm) == 1)
        }
        #expect(Motion.spring(0.48, 0.8, .calm) == .spring(response: 0.48 * 1.12, dampingFraction: 1))
        #expect(Motion.spring(0.48, 0.8, .springy) == .spring(response: 0.48 * 0.92, dampingFraction: 0.64))
    }

    @Test func closingNeverBounces() {
        let glassClose = Motion.shape(to: .hidden(peek: false), reduceMotion: false, theme: .glass, style: .springy)
        #expect(glassClose == .spring(response: 0.5, dampingFraction: 0.92))
        #expect(Motion.shape(to: .hidden(peek: false), reduceMotion: false, style: .springy) == .smooth(duration: 0.42))
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
