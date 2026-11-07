import Testing
import Foundation
@testable import IslandCore

private let utc = TimeZone(identifier: "UTC")!
private let kolkata = TimeZone(identifier: "Asia/Kolkata")!

private func moment(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

private func tasks(_ json: String, timeZone: TimeZone = utc) throws -> TodoistPage<TodoistTask> {
    try TodoistDecoding.tasks(from: Data(json.utf8), timeZone: timeZone)
}

// MARK: Reading tasks

@Test func aPageOfTasksIsReadWithItsNextCursor() throws {
    let page = try tasks("""
    {"results": [
      {"id": "8501", "user_id": "1", "project_id": "2203", "section_id": null, "parent_id": null, "content": "Buy milk",
       "description": "", "labels": ["home"], "priority": 4, "checked": false, "is_deleted": false,
       "due": {"date": "2026-11-09", "string": "9 Nov", "is_recurring": false, "lang": "en"}},
      {"id": "8502", "project_id": "2203", "content": "Standup", "priority": 1, "checked": false,
       "due": {"date": "2026-11-09T09:30:00Z", "datetime": "2026-11-09T09:30:00Z", "string": "every weekday at 9:30",
               "is_recurring": true, "timezone": "UTC"}},
      {"id": "8503", "content": "Someday", "priority": 2, "checked": false, "due": null}
    ], "next_cursor": "abc123"}
    """)
    #expect(page.nextCursor == "abc123")
    #expect(page.items.map(\.id) == ["8501", "8502", "8503"])

    let milk = page.items[0]
    #expect(milk.content == "Buy milk" && milk.projectID == "2203" && milk.priority == 4 && !milk.isCompleted)
    #expect(milk.due == TodoistDue(date: moment("2026-11-09T00:00:00Z"), hasTime: false, isRecurring: false, text: "9 Nov"))

    let standup = page.items[1]
    #expect(standup.due?.date == moment("2026-11-09T09:30:00Z") && standup.due?.hasTime == true && standup.due?.isRecurring == true)
    #expect(standup.due?.text == "every weekday at 9:30")

    #expect(page.items[2].due == nil && page.items[2].priority == 2)
    #expect(milk.webURL?.absoluteString == "https://app.todoist.com/app/task/8501")
}

@Test func theLastPageHasNoCursor() throws {
    #expect(try tasks(#"{"results": [], "next_cursor": null}"#).nextCursor == nil)
    #expect(try tasks(#"{"results": []}"#).items.isEmpty)
}

@Test func everyWayTodoistWritesATimeIsUnderstood() throws {
    func dueDate(_ due: String, in zone: TimeZone = utc) throws -> TodoistDue? {
        try tasks(#"{"results": [{"id": "1", "content": "x", "due": \#(due)}]}"#, timeZone: zone).items.first?.due
    }
    // With fractions of a second, as some responses carry them.
    #expect(try dueDate(#"{"date": "2026-11-08T09:00:00.000000Z"}"#)?.date == moment("2026-11-08T09:00:00Z"))
    // With an offset instead of Z.
    #expect(try dueDate(#"{"date": "2026-11-08T14:30:00+05:30"}"#)?.date == moment("2026-11-08T09:00:00Z"))
    // A floating time means that time on the clock of the task's own time zone...
    #expect(try dueDate(#"{"date": "2026-11-08T09:00:00", "timezone": "Asia/Kolkata"}"#)?.date == moment("2026-11-08T03:30:00Z"))
    // ...or, with no zone given, of the Mac.
    #expect(try dueDate(#"{"date": "2026-11-08T09:00:00"}"#, in: kolkata)?.date == moment("2026-11-08T03:30:00Z"))
    // A day with no time is the start of that day where the person is.
    let allDay = try dueDate(#"{"date": "2026-11-08"}"#, in: kolkata)
    #expect(allDay?.hasTime == false && allDay?.date == moment("2026-11-07T18:30:00Z"))
    // Nothing usable: no due date rather than a wrong one.
    #expect(try dueDate(#"{"date": "someday"}"#) == nil)
}

@Test func completedTasksComeInTheItemsEnvelope() throws {
    let page = try tasks("""
    {"items": [{"id": "9001", "project_id": "2203", "content": "Pay rent", "checked": true,
                "completed_at": "2026-11-06T08:15:30.123456Z", "due": null}], "next_cursor": null}
    """)
    #expect(page.items.count == 1)
    #expect(page.items[0].isCompleted && page.items[0].completedAt == moment("2026-11-06T08:15:30Z"))
}

@Test func oddEntriesAreSkippedNotFatal() throws {
    let page = try tasks("""
    {"results": [
      {"id": 77, "content": "Numeric id"},
      {"id": "78", "content": "Deleted", "is_deleted": true},
      {"id": "79"},
      {"content": "No id"},
      {"id": "80", "content": "Priority out of range", "priority": 9}
    ]}
    """)
    #expect(page.items.map(\.id) == ["77", "80"])
    #expect(page.items[1].priority == 4)
    // A bare array is accepted too.
    #expect(try tasks(#"[{"id": "1", "content": "A"}]"#).items.map(\.id) == ["1"])
}

@Test func somethingThatIsNotTodoistIsReportedAsUnreadable() {
    #expect(throws: TodoistError.unreadable) { try tasks("<html>Bad gateway</html>") }
    #expect(throws: TodoistError.unreadable) { try TodoistDecoding.task(from: Data("{}".utf8)) }
}

@Test func aSingleTaskAndProjectsAndTheAccountName() throws {
    let created = try TodoistDecoding.task(from: Data(#"{"id": "5", "content": "Call mom", "priority": 3, "due": {"date": "2026-11-08T18:00:00Z", "string": "tomorrow 6pm"}}"#.utf8))
    #expect(created.content == "Call mom" && created.due?.hasTime == true)

    let projects = try TodoistDecoding.projects(from: Data("""
    {"results": [{"id": "2203", "name": "Inbox", "inbox_project": true, "is_archived": false},
                 {"id": "2204", "name": "Old", "is_archived": true},
                 {"id": "2205", "name": "Gone", "is_deleted": true}], "next_cursor": null}
    """.utf8))
    #expect(projects.items.map(\.name) == ["Inbox", "Old"])
    #expect(projects.items[0].isInbox && projects.items[1].isArchived)

    #expect(TodoistDecoding.accountName(from: Data(#"{"full_name": "Jane Doe", "email": "j@x.com"}"#.utf8)) == "Jane Doe")
    #expect(TodoistDecoding.accountName(from: Data(#"{"full_name": " ", "email": "j@x.com"}"#.utf8)) == "j@x.com")
    #expect(TodoistDecoding.accountName(from: Data("{}".utf8)) == nil)
}

// MARK: Requests

@Test func readRequestsAreExactAndKeepTheTokenOutOfTheAddress() {
    let tasks = TodoistRequests.listTasks(token: "secret-token", cursor: nil)
    #expect(tasks.httpMethod == "GET" || tasks.httpMethod == nil)
    #expect(tasks.url?.absoluteString == "https://api.todoist.com/api/v1/tasks?limit=200")
    #expect(tasks.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    #expect(tasks.url?.absoluteString.contains("secret-token") == false)

    // A cursor is handed back exactly as Todoist gave it, whatever characters it has.
    let next = TodoistRequests.listTasks(token: "t", cursor: "cur sor/1&x=y")
    let items = URLComponents(url: next.url!, resolvingAgainstBaseURL: false)?.queryItems
    #expect(items?.first { $0.name == "cursor" }?.value == "cur sor/1&x=y")
    #expect(items?.filter { $0.name == "x" }.isEmpty == true)   // the & inside it did not start a new parameter
    // A "+" in a cursor stays a plus (not a space) on the way to the server.
    let plus = TodoistRequests.listTasks(token: "t", cursor: "a+b")
    #expect(plus.url?.query?.contains("cursor=a%2Bb") == true)

    let completed = TodoistRequests.completedTasks(
        token: "t", since: moment("2026-10-08T00:00:00Z"), until: moment("2026-11-07T10:30:00Z"))
    #expect(completed.url?.path == "/api/v1/tasks/completed/by_completion_date")
    #expect(completed.url?.query == "since=2026-10-08T00:00:00Z&until=2026-11-07T10:30:00Z&limit=100")

    #expect(TodoistRequests.listProjects(token: "t").url?.absoluteString == "https://api.todoist.com/api/v1/projects?limit=200")
    #expect(TodoistRequests.currentUser(token: "t").url?.absoluteString == "https://api.todoist.com/api/v1/user")
}

@Test func writeRequestsAreExactAndCarryARequestID() throws {
    let id = UUID()
    let close = TodoistRequests.closeTask(token: "t", id: "8501", requestID: id)
    #expect(close.httpMethod == "POST" && close.url?.absoluteString == "https://api.todoist.com/api/v1/tasks/8501/close")
    #expect(close.httpBody == nil && close.value(forHTTPHeaderField: "X-Request-Id") == id.uuidString)
    #expect(TodoistRequests.reopenTask(token: "t", id: "8501").url?.path == "/api/v1/tasks/8501/reopen")
    // An id is one path segment, whatever it contains.
    #expect(TodoistRequests.closeTask(token: "t", id: "a/b c").url?.absoluteString == "https://api.todoist.com/api/v1/tasks/a%2Fb%20c/close")

    let create = TodoistRequests.createTask(token: "t", content: "Call mom", due: moment("2026-11-08T14:30:00+05:30"), requestID: id)
    #expect(create.httpMethod == "POST" && create.url?.path == "/api/v1/tasks")
    #expect(create.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(String(data: create.httpBody ?? Data(), encoding: .utf8) == #"{"content":"Call mom","due_datetime":"2026-11-08T09:00:00Z"}"#)

    let plain = TodoistRequests.createTask(token: "t", content: "No time", due: nil)
    #expect(String(data: plain.httpBody ?? Data(), encoding: .utf8) == #"{"content":"No time"}"#)

    let quick = TodoistRequests.quickAdd(token: "t", text: "Call mom tomorrow 6pm #Home")
    #expect(quick.url?.path == "/api/v1/tasks/quick" && quick.httpMethod == "POST")
    #expect(String(data: quick.httpBody ?? Data(), encoding: .utf8) == #"{"text":"Call mom tomorrow 6pm #Home"}"#)
}

@Test func httpAnswersBecomeErrorsThePersonCanActOn() {
    #expect(TodoistError.from(status: 401) == .unauthorized)
    #expect(TodoistError.from(status: 403) == .forbidden)
    #expect(TodoistError.from(status: 404) == .notFound)
    #expect(TodoistError.from(status: 410) == .notFound)
    #expect(TodoistError.from(status: 429, retryAfter: 66) == .rateLimited(retryAfter: 66))
    #expect(TodoistError.from(status: 503) == .server(503))
}

@Test func aDayWithNoTimeIsWordedAsADayAndIsNotOverdueUntilItEnds() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let now = moment("2026-11-07T15:00:00Z")
    #expect(TaskDue.dayLabel(for: moment("2026-11-07T00:00:00Z"), now: now, calendar: calendar) == .init(text: "Today", isOverdue: false))
    #expect(TaskDue.dayLabel(for: moment("2026-11-08T00:00:00Z"), now: now, calendar: calendar) == .init(text: "Tomorrow", isOverdue: false))
    #expect(TaskDue.dayLabel(for: moment("2026-11-06T00:00:00Z"), now: now, calendar: calendar) == .init(text: "Yesterday", isOverdue: true))
    #expect(TaskDue.dayLabel(for: moment("2026-11-20T00:00:00Z"), now: now, calendar: calendar).isOverdue == false)
}
