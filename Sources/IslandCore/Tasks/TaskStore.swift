import Foundation

/// The to-do list, kept in a file. Nothing here knows about the screen.
public final class TaskStore {
    public private(set) var items: [TaskItem]

    private let store: FileStore<[TaskItem]>
    private let now: () -> Date

    public init(store: FileStore<[TaskItem]>, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        self.items = store.load()
    }

    /// Adds a task. A title that is empty (or only spaces) adds nothing and returns nil.
    @discardableResult
    public func add(title: String, due: Date? = nil) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = TaskItem(title: trimmed, due: due, createdAt: now())
        items.append(task)
        save()
        return task
    }

    /// Ticks a task off, or puts it back on the to-do list. Unknown ids are ignored.
    public func setCompleted(_ id: UUID, _ completed: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].completedAt = completed ? now() : nil
        save()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func clearCompleted() {
        items.removeAll(where: \.isCompleted)
        save()
    }

    /// The order of the to-do list: the soonest due first, then those with no time, each group in the order they were added.
    public static func isOrderedBeforeInActiveList(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.due, rhs.due) {
        case let (l?, r?) where l != r: return l < r
        case (.some, .none): return true
        case (.none, .some): return false
        default: return lhs.createdAt < rhs.createdAt
        }
    }

    /// The tasks still to do, in that order.
    public static func active(in items: [TaskItem]) -> [TaskItem] {
        items.filter { !$0.isCompleted }.sorted(by: isOrderedBeforeInActiveList)
    }

    /// The finished tasks, the most recently finished first.
    public static func completed(in items: [TaskItem]) -> [TaskItem] {
        items.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func save() {
        try? store.save(items)
    }
}
