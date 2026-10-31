import Foundation
import Observation

public struct BiquadCoefficients: Equatable, Sendable {
    public let b0: Double
    public let b1: Double
    public let b2: Double
    public let a1: Double
    public let a2: Double

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }
}

public enum EQPreset: String, CaseIterable, Identifiable, Sendable {
    case flat = "Flat"
    case bassBoost = "Bass Boost"
    case vocalBooster = "Vocal Booster"
    case acoustic = "Acoustic"
    case rock = "Rock"
    case podcast = "Podcast"

    public var id: String { rawValue }

    /// 10 bands: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz in dB (-12...+12)
    public var bandGains: [Double] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:
            return [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .vocalBooster:
            return [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]
        case .acoustic:
            return [3, 2, 1, 0, 1, 2, 3, 3, 2, 2]
        case .rock:
            return [5, 4, 2, -1, -2, 0, 2, 4, 5, 5]
        case .podcast:
            return [-4, -3, 0, 2, 4, 4, 2, 0, -1, -2]
        }
    }
}

public struct EQProfile: Equatable, Sendable, Codable {
    public var bundleIdentifier: String
    public var gains: [Double]
    public var isBypassed: Bool

    public init(bundleIdentifier: String, gains: [Double] = Array(repeating: 0.0, count: 10), isBypassed: Bool = false) {
        self.bundleIdentifier = bundleIdentifier
        self.gains = gains
        self.isBypassed = isBypassed
    }
}

public enum AudioDSP {
    public static let bandCenterFrequencies: [Double] = [
        32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    /// Robert Bristow-Johnson Audio EQ Cookbook Peaking Filter
    public static func peakingFilter(frequency: Double, gainDB: Double, q: Double = 1.414, sampleRate: Double = 44100) -> BiquadCoefficients {
        guard gainDB != 0 else {
            return BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
        }
        let a = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * frequency / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosW0 = cos(w0)

        let b0 = 1.0 + alpha * a
        let b1 = -2.0 * cosW0
        let b2 = 1.0 - alpha * a
        let a0 = 1.0 + alpha / a
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha / a

        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }

    /// Processes an audio buffer with a given biquad filter.
    public static func process(samples: [Double], coefficients: BiquadCoefficients) -> [Double] {
        var x1 = 0.0, x2 = 0.0
        var y1 = 0.0, y2 = 0.0
        var output = [Double](repeating: 0, count: samples.count)

        for i in 0..<samples.count {
            let x0 = samples[i]
            let y0 = coefficients.b0 * x0 + coefficients.b1 * x1 + coefficients.b2 * x2 - coefficients.a1 * y1 - coefficients.a2 * y2
            output[i] = y0
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }
        return output
    }
}

@MainActor
@Observable
public final class PerAppEQEngine {
    public private(set) var profiles: [String: EQProfile] = [:]
    public private(set) var activeAppBundleID: String?
    public var globalBypass = false

    public init() {}

    public func setProfile(_ profile: EQProfile) {
        profiles[profile.bundleIdentifier] = profile
    }

    public func activeProfile() -> EQProfile? {
        guard !globalBypass, let id = activeAppBundleID else { return nil }
        return profiles[id]
    }

    public func activateApp(bundleIdentifier: String?) {
        activeAppBundleID = bundleIdentifier
    }

    public func resetAndRecover() {
        globalBypass = false
        activeAppBundleID = nil
    }
}
