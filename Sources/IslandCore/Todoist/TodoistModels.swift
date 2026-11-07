import Foundation

/// When a Todoist task is due.
public struct TodoistDue: Equatable, Sendable {
    /// The moment it is due, or the start of the day for a task that is due on a day but at no particular time.
    public var date: Date
    public var hasTime: Bool
    public var isRecurring: Bool
    /// Todoist's own wording ("every weekday at 9am").
    public var text: String

    public init(date: Date, hasTime: Bool, isRecurring: Bool = false, text: String = "") {
        self.date = date
        self.hasTime = hasTime
        self.isRecurring = isRecurring
        self.text = text
    }
}

/// One task in a Todoist account, reduced to what Island shows.
public struct TodoistTask: Equatable, Identifiable, Sendable {
    public let id: String
    public var content: String
    public var projectID: String?
    public var parentID: String?
    /// Todoist's numbering: 1 is normal and 4 is the most urgent (shown in Todoist as P1).
    public var priority: Int
    public var due: TodoistDue?
    public var isCompleted: Bool
    public var completedAt: Date?

    public init(
        id: String, content: String, projectID: String? = nil, parentID: String? = nil, priority: Int = 1,
        due: TodoistDue? = nil, isCompleted: Bool = false, completedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.projectID = projectID
        self.parentID = parentID
        self.priority = priority
        self.due = due
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    /// The link that opens the task in the Todoist app or website.
    public var webURL: URL? { URL(string: "https://app.todoist.com/app/task/\(id)") }
}

public struct TodoistProject: Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var isArchived: Bool
    public var isInbox: Bool

    public init(id: String, name: String, isArchived: Bool = false, isInbox: Bool = false) {
        self.id = id
        self.name = name
        self.isArchived = isArchived
        self.isInbox = isInbox
    }
}

/// One page of a list the API hands out in pieces, and where the next piece starts (nil on the last page).
public struct TodoistPage<Element: Sendable>: Sendable {
    public var items: [Element]
    public var nextCursor: String?

    public init(items: [Element], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// Why a call to Todoist did not work, in terms the person can act on.
public enum TodoistError: Error, Equatable, Sendable {
    /// The token was refused (wrong, or revoked in Todoist's settings).
    case unauthorized
    case forbidden
    case notFound
    /// Too many requests; try again after this many seconds, when Todoist says.
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int)
    /// Todoist could not be reached at all.
    case network(String)
    /// Todoist answered, but not in a form Island understands.
    case unreadable

    /// The error for an HTTP answer that was not a success.
    public static func from(status: Int, retryAfter: TimeInterval? = nil) -> TodoistError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404, 410: return .notFound
        case 429: return .rateLimited(retryAfter: retryAfter)
        default: return .server(status)
        }
    }
}

extension TaskDue {
    /// "Today", "Tomorrow", "Fri 6 Nov": the day only, for a task that is due on a day but at no particular time.
    public static func dayLabel(for due: Date, now: Date, calendar: Calendar = .current) -> Label {
        let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        let text: String
        switch difference {
        case 0: text = "Today"
        case 1: text = "Tomorrow"
        case -1: text = "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = calendar.locale ?? .current
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
            text = formatter.string(from: due)
        }
        // A task due today with no time is not overdue until the day is over.
        return Label(text: text, isOverdue: calendar.startOfDay(for: due) < calendar.startOfDay(for: now))
    }
}
