import Foundation

/// Clock-app style time strings: "0:42", "4:59", "1:02:03".
public enum TimeFormatting {
    public static func clock(_ seconds: TimeInterval, roundingUp: Bool = false) -> String {
        guard seconds.isFinite else { return "0:00" }
        // Some players report absurd lengths for live streams; Int() would crash on them.
        let value = min(max(0, seconds), 999 * 3600)
        let total = Int(roundingUp ? value.rounded(.up) : value.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Time left in a track, shown with a leading minus like the Music app.
    public static func remaining(elapsed: TimeInterval, duration: TimeInterval) -> String {
        "-" + clock(max(0, duration - elapsed), roundingUp: true)
    }

    /// Label for a timer preset: "1 min", "30 min", "1 hr", "1 hr 30 min".
    public static func presetLabel(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// Spoken form for VoiceOver: "4 minutes, 59 seconds".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: max(0, seconds.rounded(.up))) ?? clock(seconds, roundingUp: true)
    }
}
