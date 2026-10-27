import Foundation
import Carbon.HIToolbox
import CoreGraphics

/// The documented shortcut or exact accessible control each app exposes for ending a call.
/// A guessed browser shortcut could close the wrong window, so unsupported apps get no button.
public enum CallHangup {
    public struct Shortcut: Equatable, Sendable {
        public var keyCode: CGKeyCode
        public var flags: CGEventFlags
        /// The app asks before leaving (Zoom), so the button only starts it.
        public var asksToConfirm: Bool
    }

    /// A safe, app-specific way to end a call.
    public enum Route: Equatable, Sendable {
        case shortcut(Shortcut)
        case accessibilityButton
    }

    public static func route(for bundleIdentifier: String?) -> Route? {
        switch bundleIdentifier {
        // Microsoft: "End audio call / End video call: Command+Shift+H".
        case "com.microsoft.teams", "com.microsoft.teams2":
            .shortcut(Shortcut(keyCode: CGKeyCode(kVK_ANSI_H), flags: [.maskCommand, .maskShift], asksToConfirm: false))
        // Zoom: "Command+W: prompt to end or leave meeting".
        case "us.zoom.xos":
            .shortcut(Shortcut(keyCode: CGKeyCode(kVK_ANSI_W), flags: .maskCommand, asksToConfirm: true))
        // Webex App: "End a call: Command+L".
        case "Cisco-Systems.Spark", "com.cisco.webexmeetingsapp":
            .shortcut(Shortcut(keyCode: CGKeyCode(kVK_ANSI_L), flags: .maskCommand, asksToConfirm: false))
        // WhatsApp for Mac documents an End call button but no end-call keyboard shortcut.
        case "net.whatsapp.WhatsApp", "desktop.WhatsApp":
            .accessibilityButton
        default:
            nil
        }
    }

    /// Kept for callers that only need the app's documented keyboard shortcut.
    public static func shortcut(for bundleIdentifier: String?) -> Shortcut? {
        guard case let .shortcut(shortcut) = route(for: bundleIdentifier) else { return nil }
        return shortcut
    }

    /// WhatsApp keeps the microphone after a call and for voice notes, so its mic use alone
    /// isn't a call. With the camera on, or a window titled as a call, it is. Without
    /// Accessibility the windows can't be read, so mic use counts as a call, as it always has:
    /// better a call that lingers than a call that never shows.
    public static func isWhatsAppOnCall(cameraOn: Bool, canReadWindows: Bool, callWindowOpen: Bool?) -> Bool {
        cameraOn || !canReadWindows || callWindowOpen == true
    }

    /// WhatsApp adds invisible direction marks to accessibility labels.
    public static func isWhatsAppEndCallLabel(_ label: String) -> Bool {
        let withoutDirectionMarks = String(label.unicodeScalars.filter {
            !CharacterSet(charactersIn: "\u{200E}\u{200F}\u{061C}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}").contains($0)
        })
        let normalized = withoutDirectionMarks.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "end call" || normalized == "leave call"
    }
}
