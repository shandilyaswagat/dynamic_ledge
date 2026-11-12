import Foundation

/// An in-memory view of one coding assistant session.
public struct AgentSession: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        case working
        case needsAttention
        case finished
        case disconnected
    }

    public let id: String
    public let kind: AgentKind
    public var project: String
    public var state: State
    public var lastUpdated: Date

    public init(id: String, kind: AgentKind, project: String, state: State, lastUpdated: Date) {
        self.id = id
        self.kind = kind
        self.project = project
        self.state = state
        self.lastUpdated = lastUpdated
    }
}
