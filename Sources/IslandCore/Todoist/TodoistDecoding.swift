import Foundation

/// Reads what Todoist's API sends back. Lenient on purpose: a field that is missing or new never stops a list loading.
public enum TodoistDecoding {
    // MARK: What the wire looks like (snake_case JSON)

    private struct WireDue: Decodable {
        var date: String?
        var datetime: String?
        var string: String?
        var isRecurring: Bool?
        var timezone: String?
    }

    private struct WireTask: Decodable {
        var id: Identifier?
        var taskId: Identifier?
        var content: String?
        var projectId: Identifier?
        var parentId: Identifier?
        var priority: Int?
        var due: WireDue?
        var checked: Bool?
        var completedAt: String?
        var isDeleted: Bool?
    }

    private struct WireProject: Decodable {
        var id: Identifier?
        var name: String?
        var isArchived: Bool?
        var isDeleted: Bool?
        var inboxProject: Bool?
    }

    /// Todoist's ids are strings, but older versions of the API used numbers.
    private struct Identifier: Decodable {
        var value: String
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { value = text }
            else if let number = try? container.decode(Int.self) { value = String(number) }
            else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an id") }
        }
    }

    /// A list in either of the envelopes the API uses (`results` for lists, `items` for completed tasks) or a bare array.
    private struct Envelope<Element: Decodable>: Decodable {
        var results: [Element]?
        var items: [Element]?
        var nextCursor: String?
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func page<Wire: Decodable>(_ data: Data, as: Wire.Type) throws -> (elements: [Wire], next: String?) {
        let decoder = decoder()
        if let array = try? decoder.decode([Wire].self, from: data) { return (array, nil) }
        do {
            let envelope = try decoder.decode(Envelope<Wire>.self, from: data)
            return (envelope.results ?? envelope.items ?? [], envelope.nextCursor)
        } catch {
            throw TodoistError.unreadable
        }
    }

    // MARK: Public

    public static func tasks(from data: Data, timeZone: TimeZone = .current) throws -> TodoistPage<TodoistTask> {
        let (elements, next) = try page(data, as: WireTask.self)
        return TodoistPage(items: elements.compactMap { task(from: $0, timeZone: timeZone) }, nextCursor: next)
    }

    /// One task, as the create and quick-add calls answer.
    public static func task(from data: Data, timeZone: TimeZone = .current) throws -> TodoistTask {
        guard let wire = try? decoder().decode(WireTask.self, from: data), let task = task(from: wire, timeZone: timeZone) else {
            throw TodoistError.unreadable
        }
        return task
    }

    public static func projects(from data: Data) throws -> TodoistPage<TodoistProject> {
        let (elements, next) = try page(data, as: WireProject.self)
        let projects = elements.compactMap { wire -> TodoistProject? in
            guard let id = wire.id?.value, let name = wire.name, wire.isDeleted != true else { return nil }
            return TodoistProject(id: id, name: name, isArchived: wire.isArchived ?? false, isInbox: wire.inboxProject ?? false)
        }
        return TodoistPage(items: projects, nextCursor: next)
    }

    /// The name on the account, from the user call (its full name, else its email). Nil if it says neither.
    public static func accountName(from data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for key in ["full_name", "email"] {
            if let text = object[key] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        }
        return nil
    }

    // MARK: Internals

    private static func task(from wire: WireTask, timeZone: TimeZone) -> TodoistTask? {
        guard wire.isDeleted != true, let id = (wire.id ?? wire.taskId)?.value, let content = wire.content else { return nil }
        let completedAt = wire.completedAt.flatMap { parseMoment($0, timeZone: timeZone) }
        return TodoistTask(
            id: id, content: content, projectID: wire.projectId?.value, parentID: wire.parentId?.value,
            priority: min(max(wire.priority ?? 1, 1), 4), due: wire.due.flatMap { due(from: $0, timeZone: timeZone) },
            isCompleted: wire.checked ?? (completedAt != nil), completedAt: completedAt)
    }

    private static func due(from wire: WireDue, timeZone: TimeZone) -> TodoistDue? {
        // The zone a floating time ("9am wherever I am") means is the due's own, else the Mac's.
        let zone = wire.timezone.flatMap(TimeZone.init(identifier:)) ?? timeZone
        let text = wire.string ?? ""
        let recurring = wire.isRecurring ?? false
        for candidate in [wire.datetime, wire.date] {
            guard let candidate, !candidate.isEmpty else { continue }
            if candidate.contains("T"), let moment = parseMoment(candidate, timeZone: zone) {
                return TodoistDue(date: moment, hasTime: true, isRecurring: recurring, text: text)
            }
            if let day = parseDay(candidate, timeZone: timeZone) {
                return TodoistDue(date: day, hasTime: false, isRecurring: recurring, text: text)
            }
        }
        return nil
    }

    /// "2026-11-08T14:30:00Z", "…+05:30", with or without fractions of a second, or a time with no zone at all.
    static func parseMoment(_ text: String, timeZone: TimeZone) -> Date? {
        // Fractions of a second ("…:00.000000Z") are dropped: they are never needed and not every formatter takes them.
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let zoned = ISO8601DateFormatter()
        zoned.formatOptions = [.withInternetDateTime]
        if let date = zoned.date(from: trimmed) { return date }
        let floating = DateFormatter()
        floating.locale = Locale(identifier: "en_US_POSIX")
        floating.timeZone = timeZone
        floating.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = floating.date(from: trimmed) { return date }
        return parseDay(trimmed, timeZone: timeZone)
    }

    /// "2026-11-08" as the start of that day in the person's own time zone.
    static func parseDay(_ text: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }
}
