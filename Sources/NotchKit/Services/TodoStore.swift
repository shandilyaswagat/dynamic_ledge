import Foundation
import Observation

/// A short to-do list that lives in the notch, saved on this Mac. No account, no permission.
@MainActor
@Observable
public final class TodoStore {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var isDone: Bool

        public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
            self.id = id
            self.title = title
            self.isDone = isDone
        }
    }

    public private(set) var items: [Item] {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "todos.items"
    static let capacity = 50

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }

    /// Open ones first, newest at the top, then the ticked-off ones.
    public var ordered: [Item] {
        items.filter { !$0.isDone } + items.filter(\.isDone)
    }

    public var openCount: Int { items.filter { !$0.isDone }.count }

    public func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(Item(title: String(trimmed.prefix(200))), at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    }

    public func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func clearDone() {
        items.removeAll(where: \.isDone)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
