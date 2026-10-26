import Foundation

enum DocumentDragPolicy {
    static func dropRegion(activation: CGRect, pill: CGRect) -> CGRect {
        activation.union(pill)
    }

    static func hasMoved(from origin: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - origin.x, current.y - origin.y) > 3
    }
}

public enum FileDropDestination: Sendable, Equatable {
    case tray
    case airDrop
}

enum DropPolicy {
    static func isSupported(_ url: URL) -> Bool {
        url.isFileURL || ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    }

    /// With both on, Tray takes this share of the width on the left and AirDrop the rest.
    public static let trayShare: CGFloat = 0.6

    static func destination(at point: CGPoint, content: CGRect, tray: Bool, airDrop: Bool) -> FileDropDestination? {
        guard content.contains(point) else { return nil }
        if tray && airDrop { return point.x < content.minX + content.width * trayShare ? .tray : .airDrop }
        if tray { return .tray }
        if airDrop { return .airDrop }
        return nil
    }
}
