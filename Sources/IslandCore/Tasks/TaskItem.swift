import Foundation

/// One to-do: a title, an optional time it is due, and whether it is done.
public struct TaskItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var due: Date?
    public let createdAt: Date
    /// Set when the task is ticked off; nil while it is still to do.
    public var completedAt: Date?

    public var isCompleted: Bool { completedAt != nil }

    public init(id: UUID = UUID(), title: String, due: Date? = nil, createdAt: Date, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
