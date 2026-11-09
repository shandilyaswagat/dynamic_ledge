import Foundation

enum DocumentDragPolicy {
    static func dropRegion(activation: CGRect, pill: CGRect) -> CGRect {
        activation.union(pill)
    }

    /// How far outside the notch the pointer may be and still count as touching it.
    static let touchMargin: CGFloat = 4

    /// A moved window opens the Tray only once the pointer touches the notch, so windows dragged
    /// near the top of the screen don't set it off. Once open, the whole drop view keeps it open.
    static func isOverTarget(_ point: CGPoint, isOpen: Bool, activation: CGRect, pill: CGRect) -> Bool {
        isOpen ? dropRegion(activation: activation, pill: pill).contains(point)
            : pill.insetBy(dx: -touchMargin, dy: -touchMargin).contains(point)
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
