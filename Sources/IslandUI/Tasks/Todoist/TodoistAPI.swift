import Foundation
import IslandCore

/// What Island asks of Todoist. The real one talks to the internet; tests use a stand-in.
protocol TodoistAPI: Sendable {
    /// Every task that is not done yet.
    func openTasks(token: String) async throws -> [TodoistTask]
    /// Tasks completed between two moments, most recent first.
    func completedTasks(token: String, since: Date, until: Date) async throws -> [TodoistTask]
    func projects(token: String) async throws -> [TodoistProject]
    /// The name on the account, when Todoist says it.
    func accountName(token: String) async throws -> String?
    func close(_ id: String, token: String) async throws
    func reopen(_ id: String, token: String) async throws
    /// A new task with exactly this title and, if given, this due moment.
    func create(title: String, due: Date?, token: String) async throws -> TodoistTask
    /// A new task from text Todoist reads itself ("Call mom tomorrow 6pm #Home").
    func quickAdd(text: String, token: String) async throws -> TodoistTask
}

/// Todoist over the internet. It uses an ephemeral session, so nothing about a person's tasks is cached on disk.
final class URLSessionTodoistAPI: TodoistAPI, @unchecked Sendable {
    private let session: URLSession
    /// The most pages one list is followed through (200 tasks each), so a runaway answer cannot loop forever.
    private let maxPages = 5

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func openTasks(token: String) async throws -> [TodoistTask] {
        try await allPages { cursor in
            try TodoistDecoding.tasks(from: try await self.send(TodoistRequests.listTasks(token: token, cursor: cursor)))
        }
    }

    func completedTasks(token: String, since: Date, until: Date) async throws -> [TodoistTask] {
        // One page is plenty for a "recently done" list.
        try TodoistDecoding.tasks(
            from: try await send(TodoistRequests.completedTasks(token: token, since: since, until: until))).items
    }

    func projects(token: String) async throws -> [TodoistProject] {
        try await allPages { cursor in
            try TodoistDecoding.projects(from: try await self.send(TodoistRequests.listProjects(token: token, cursor: cursor)))
        }
    }

    func accountName(token: String) async throws -> String? {
        TodoistDecoding.accountName(from: try await send(TodoistRequests.currentUser(token: token)))
    }

    func close(_ id: String, token: String) async throws {
        _ = try await send(TodoistRequests.closeTask(token: token, id: id))
    }

    func reopen(_ id: String, token: String) async throws {
        _ = try await send(TodoistRequests.reopenTask(token: token, id: id))
    }

    func create(title: String, due: Date?, token: String) async throws -> TodoistTask {
        try TodoistDecoding.task(from: try await send(TodoistRequests.createTask(token: token, content: title, due: due)))
    }

    func quickAdd(text: String, token: String) async throws -> TodoistTask {
        try TodoistDecoding.task(from: try await send(TodoistRequests.quickAdd(token: token, text: text)))
    }

    // MARK: Internals

    private func allPages<Element: Sendable>(_ fetch: (String?) async throws -> TodoistPage<Element>) async throws -> [Element] {
        var all: [Element] = []
        var cursor: String?
        for _ in 0..<maxPages {
            let page = try await fetch(cursor)
            all += page.items
            guard let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return all
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TodoistError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw TodoistError.unreadable }
        guard (200..<300).contains(http.statusCode) else {
            throw TodoistError.from(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        }
        return data
    }
}
