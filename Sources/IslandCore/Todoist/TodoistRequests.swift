import Foundation

/// The calls Island makes to Todoist, as ready-to-send requests (nothing is sent here, so they can be checked exactly).
///
/// The token travels only in the `Authorization` header, never in an address. Every call that changes something carries
/// an `X-Request-Id`, so Todoist can recognise a retry of the same request and not do it twice.
public enum TodoistRequests {
    public static let base = URL(string: "https://api.todoist.com/api/v1")!

    /// Where a person finds their own token.
    public static let tokenSettingsURL = URL(string: "https://app.todoist.com/app/settings/integrations/developer")!

    public static func listTasks(token: String, cursor: String? = nil, limit: Int = 200) -> URLRequest {
        get("tasks", token: token, query: [("limit", String(limit)), ("cursor", cursor)])
    }

    /// Tasks completed between two moments (Todoist allows a range of up to three months).
    public static func completedTasks(token: String, since: Date, until: Date, cursor: String? = nil, limit: Int = 100) -> URLRequest {
        get(
            "tasks/completed/by_completion_date", token: token,
            query: [("since", iso(since)), ("until", iso(until)), ("limit", String(limit)), ("cursor", cursor)])
    }

    public static func listProjects(token: String, cursor: String? = nil) -> URLRequest {
        get("projects", token: token, query: [("limit", "200"), ("cursor", cursor)])
    }

    public static func currentUser(token: String) -> URLRequest {
        get("user", token: token, query: [])
    }

    public static func closeTask(token: String, id: String, requestID: UUID = UUID()) -> URLRequest {
        post("tasks/\(escaped(id))/close", token: token, body: nil, requestID: requestID)
    }

    public static func reopenTask(token: String, id: String, requestID: UUID = UUID()) -> URLRequest {
        post("tasks/\(escaped(id))/reopen", token: token, body: nil, requestID: requestID)
    }

    /// A new task with exactly this title and, if given, this due moment.
    public static func createTask(token: String, content: String, due: Date?, requestID: UUID = UUID()) -> URLRequest {
        var body: [String: Any] = ["content": content]
        if let due { body["due_datetime"] = iso(due) }
        return post("tasks", token: token, body: body, requestID: requestID)
    }

    /// Todoist's own quick add: it reads "tomorrow 5pm", "#Project" and "p1" out of the text, as the Todoist apps do.
    public static func quickAdd(token: String, text: String, requestID: UUID = UUID()) -> URLRequest {
        post("tasks/quick", token: token, body: ["text": text], requestID: requestID)
    }

    // MARK: Internals

    /// An ISO 8601 moment in UTC without fractions: "2026-11-08T09:00:00Z".
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func escaped(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    private static func request(_ path: String, token: String, query: [(String, String?)]) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        // `appendingPathComponent` would escape a slash inside an id; the path is built by hand to keep it as written.
        components.percentEncodedPath = base.path + "/" + path
        let items = query.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        if !items.isEmpty {
            components.queryItems = items
            // URLComponents leaves "+" as it is, and a server reads that as a space: an opaque cursor must survive intact.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func get(_ path: String, token: String, query: [(String, String?)]) -> URLRequest {
        request(path, token: token, query: query)
    }

    private static func post(_ path: String, token: String, body: [String: Any]?, requestID: UUID) -> URLRequest {
        var request = request(path, token: token, query: [])
        request.httpMethod = "POST"
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-Id")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return request
    }
}
