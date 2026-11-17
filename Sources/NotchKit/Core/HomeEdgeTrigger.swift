import Foundation

/// The small screen-edge targets that open Home. Coordinates are local to a display,
/// measured in points from its top-left corner.
struct HomeEdgeTrigger {
    enum Edge: Equatable { case topLeft, topCenter, topRight, bottomCenter }

    private var occupied: Edge?

    mutating func enter(at point: CGPoint, on size: CGSize) -> Edge? {
        let edge = Self.edge(at: point, on: size)
        defer { occupied = edge }
        return edge != occupied ? edge : nil
    }

    private static func edge(at point: CGPoint, on size: CGSize) -> Edge? {
        guard size.width > 0, size.height > 0,
              point.x >= 0, point.x < size.width, point.y >= 0, point.y <= size.height else { return nil }
        if point.x < 4, point.y < 4 { return .topLeft }
        if point.x >= size.width - 4, point.y < 4 { return .topRight }
        let halfWidth = min(50, size.width / 2)
        if point.y <= 1,
           point.x >= size.width / 2 - halfWidth, point.x < size.width / 2 + halfWidth {
            return .topCenter
        }
        if point.y >= size.height - 1,
           point.x >= size.width / 2 - halfWidth, point.x < size.width / 2 + halfWidth {
            return .bottomCenter
        }
        return nil
    }
}
