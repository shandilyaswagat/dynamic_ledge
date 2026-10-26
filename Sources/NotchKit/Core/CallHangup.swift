import Carbon.HIToolbox
import CoreGraphics

/// The keyboard shortcut each call app documents for ending or leaving a call. Only apps with a
/// published, reliable shortcut are listed: a wrong guess (⌘W in a browser) would close
/// something else, so FaceTime, browsers and the rest get no hang-up button.
public enum CallHangup {
    public struct Shortcut: Equatable, Sendable {
        public var keyCode: CGKeyCode
        public var flags: CGEventFlags
        /// The app asks before leaving (Zoom), so the button only starts it.
        public var asksToConfirm: Bool
    }

    public static func shortcut(for bundleIdentifier: String?) -> Shortcut? {
        switch bundleIdentifier {
        // Microsoft: "End audio call / End video call: Command+Shift+H".
        case "com.microsoft.teams", "com.microsoft.teams2":
            Shortcut(keyCode: CGKeyCode(kVK_ANSI_H), flags: [.maskCommand, .maskShift], asksToConfirm: false)
        // Zoom: "Command+W: prompt to end or leave meeting".
        case "us.zoom.xos":
            Shortcut(keyCode: CGKeyCode(kVK_ANSI_W), flags: .maskCommand, asksToConfirm: true)
        // Webex App: "End a call: Command+L".
        case "Cisco-Systems.Spark":
            Shortcut(keyCode: CGKeyCode(kVK_ANSI_L), flags: .maskCommand, asksToConfirm: false)
        default:
            nil
        }
    }
}
