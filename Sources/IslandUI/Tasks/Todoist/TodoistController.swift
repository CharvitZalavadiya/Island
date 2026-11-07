import Foundation
import Observation
import IslandCore

/// The Todoist side of the Tasks tab: the connection, and the person's own Todoist tasks.
///
/// - Connecting takes a personal API token (pasted from Todoist's settings), checks it with Todoist, and keeps it in the
///   Keychain. Nothing is read from the Keychain until the Todoist view is first opened.
/// - The lists refresh when the view opens, once a minute while it is open, and after every change Island makes.
/// - Ticking a task off shows at once and is sent to Todoist; if Todoist refuses, the tick is undone and a message says so.
/// - A token Todoist stops accepting (revoked in Todoist's settings) is forgotten and the connect screen comes back.
@Observable
@MainActor
final class TodoistController {
    enum Connection: Equatable {
        case disconnected
        /// A pasted token is being checked.
        case connecting
        case connected
    }

    struct Message: Equatable {
        var text: String
        var isError: Bool
    }

    var mode: TasksController.Mode = .active
    private(set) var connection: Connection = .disconnected
    private(set) var accountName: String?
    /// Every open task, including ones just ticked off that are still showing (struck through) for a moment.
    private(set) var openTasks: [TodoistTask] = []
    private(set) var completedTasks: [TodoistTask] = []
    private(set) var projectNames: [String: String] = [:]
    private(set) var isLoading = false
    /// True once the lists have loaded at least once since connecting.
    private(set) var hasLoaded = false
    /// True when Todoist refused to list completed tasks for this account (some plans do not include it). The open tasks
    /// still work; the Completed list then only has what was ticked off here.
    private(set) var completedUnavailable = false
    /// True once Island has looked for a saved token, so the view shows neither screen until it knows which one is right.
    private(set) var isReady = false
    private(set) var message: Message?
    /// Tasks ticked off a moment ago: still in the Active list, struck through, before moving to Completed.
    private(set) var lingering: Set<String> = []
    /// Tasks a request is in flight for (a second tap on them waits).
    private(set) var busy: Set<String> = []

    @ObservationIgnored private let api: TodoistAPI
    @ObservationIgnored private let tokens: TokenStoring
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let refreshInterval: TimeInterval
    @ObservationIgnored private let lingerSeconds: TimeInterval
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var tokenLoaded = false
    @ObservationIgnored private var timer: Timer?
    /// Bumped by every change Island makes, so a refresh that began before the change cannot overwrite it.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshAgain = false
    /// Tasks ticked off in this session, kept in the Completed list until Todoist's own completed list shows them (it can
    /// lag a moment behind), so a tick never makes a task vanish from both lists.
    @ObservationIgnored private var completedHere: [TodoistTask] = []
    @ObservationIgnored private var pausedUntil = Date.distantPast

    /// How long a task ticked here is kept in Completed while waiting for Todoist's list to include it.
    static let completedHereMinutes = 10.0
    /// How far back the Completed list looks.
    static let completedDays = 30
    static let completedLimit = 50

    init(
        api: TodoistAPI = URLSessionTodoistAPI(), tokens: TokenStoring = KeychainTokenStore(forService: "todoist"),
        now: @escaping () -> Date = Date.init, refreshInterval: TimeInterval = 60, lingerSeconds: TimeInterval = 0.8
    ) {
        self.api = api
        self.tokens = tokens
        self.now = now
        self.refreshInterval = refreshInterval
        self.lingerSeconds = lingerSeconds
    }

    // MARK: What the list shows

    var visible: [TodoistTask] { mode == .active ? openTasks : completedTasks }
    var activeCount: Int { openTasks.filter { !$0.isCompleted }.count }
    var completedCount: Int { completedTasks.count }

    func projectName(for task: TodoistTask) -> String? {
        task.projectID.flatMap { projectNames[$0] }
    }

    // MARK: Opening and closing the view

    /// The Todoist view is on screen: look for a saved token, load, and keep the lists fresh while it stays open.
    func start() async {
        loadTokenIfNeeded()
        guard connection == .connected else { return }
        scheduleTimer()
        await refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Connecting

    /// Checks a pasted token with Todoist and, if it works, keeps it and loads the tasks.
    func connect(token pasted: String) async {
        let candidate = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, connection != .connecting else { return }
        connection = .connecting
        message = nil
        do {
            // Asking for the projects both proves the token works and fetches the names the rows show.
            let projects = try await api.projects(token: candidate)
            guard tokens.save(candidate) else {
                connection = .disconnected
                message = Message(text: "Island couldn't save the token in your Keychain, so it didn't connect.", isError: true)
                return
            }
            token = candidate
            tokenLoaded = true
            isReady = true
            projectNames = Self.names(of: projects)
            connection = .connected
            accountName = try? await api.accountName(token: candidate)
            scheduleTimer()
            await refresh()
        } catch {
            connection = .disconnected
            message = Message(text: Self.connectMessage(for: error), isError: true)
        }
    }

    /// Forgets the token and everything loaded with it.
    func disconnect() {
        stop()
        tokens.delete()
        token = nil
        tokenLoaded = true
        isReady = true
        reset()
        connection = .disconnected
    }

    func dismissMessage() { message = nil }

    // MARK: Loading

    /// Loads the open tasks and the recently completed ones. A request already running is not doubled; it is repeated
    /// once it ends, so a change made meanwhile is never missed.
    func refresh() async {
        guard connection == .connected, let token else { return }
        guard !isLoading else {
            refreshAgain = true
            return
        }
        guard now() >= pausedUntil else { return }
        isLoading = true
        let startedAt = generation
        do {
            let current = now()
            let since = current.addingTimeInterval(-Double(Self.completedDays) * 86_400)
            async let open = api.openTasks(token: token)
            async let done = completedIfAllowed(token: token, since: since, until: current)
            let (openList, doneOrNil) = try await (open, done)
            let doneList = doneOrNil ?? []
            var names = projectNames
            if openList.contains(where: { task in task.projectID.map { names[$0] == nil } ?? false }) {
                names = Self.names(of: try await api.projects(token: token))
            }
            if generation == startedAt {
                openTasks = mergedWithLingering(openList).sorted(by: Self.isOrderedBefore)
                completedTasks = mergedCompleted(doneList)
                completedUnavailable = doneOrNil == nil
                projectNames = names
                hasLoaded = true
                if message?.isError == true { message = nil }
            }
        } catch is CancellationError {
            // The view went away: nothing to report.
        } catch {
            handle(error, doing: nil)
        }
        isLoading = false
        if refreshAgain {
            refreshAgain = false
            await refresh()
        }
    }

    /// The completed tasks, or nil when Todoist will not list them for this account. Any other failure (a bad token, no
    /// internet, being told to slow down) still counts: it is thrown, because it affects everything.
    private func completedIfAllowed(token: String, since: Date, until: Date) async throws -> [TodoistTask]? {
        do {
            return try await api.completedTasks(token: token, since: since, until: until)
        } catch let error as TodoistError {
            switch error {
            case .unauthorized, .rateLimited, .network: throw error
            case .forbidden, .notFound, .server, .unreadable: return nil
            }
        }
    }

    // MARK: Changing tasks

    /// Ticks a task off (it is struck through, then moves to Completed), or, from the Completed list, puts it back.
    func toggle(_ task: TodoistTask) async {
        guard connection == .connected, let token, !busy.contains(task.id) else { return }
        generation += 1

        if lingering.contains(task.id) {
            // Ticked a moment ago and un-ticked before it moved away.
            completedHere.removeAll { $0.id == task.id }
            lingering.remove(task.id)
            setCompleted(false, for: task.id)
            await reopen(task, token: token, restore: { [self] in
                setCompleted(true, for: task.id)
                lingering.insert(task.id)
            })
            return
        }
        if task.isCompleted {
            moveToOpen(task)
            await reopen(task, token: token, restore: { [self] in moveToCompleted(task, at: task.completedAt ?? now()) })
            return
        }

        setCompleted(true, for: task.id)
        lingering.insert(task.id)
        busy.insert(task.id)
        do {
            try await api.close(task.id, token: token)
            busy.remove(task.id)
        } catch {
            busy.remove(task.id)
            lingering.remove(task.id)
            setCompleted(false, for: task.id)
            handle(error, doing: "mark that task as done")
            return
        }
        // Let the tick show for a moment, unless it was undone meanwhile.
        if lingerSeconds > 0 { try? await Task.sleep(nanoseconds: UInt64(lingerSeconds * 1_000_000_000)) }
        guard lingering.contains(task.id) else { return }
        lingering.remove(task.id)
        openTasks.removeAll { $0.id == task.id }
        var done = task
        done.isCompleted = true
        done.completedAt = now()
        completedTasks.insert(done, at: 0)
        completedHere.append(done)
        await refresh()
    }

    /// Adds a task. With a time chosen it is added exactly as typed with that due time; without one Todoist reads the
    /// text itself, so "Call mom tomorrow 6pm" is due tomorrow at 6 PM. Returns whether it worked.
    func add(title: String, due: Date?) async -> Bool {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, connection == .connected, let token else { return false }
        generation += 1
        do {
            let created: TodoistTask
            if let due {
                created = try await api.create(title: text, due: due, token: token)
            } else {
                created = try await api.quickAdd(text: text, token: token)
            }
            openTasks.removeAll { $0.id == created.id }
            openTasks.append(created)
            openTasks.sort(by: Self.isOrderedBefore)
            if message?.isError == true { message = nil }
            await refresh()
            return true
        } catch {
            handle(error, doing: "add that task")
            return false
        }
    }

    // MARK: Internals

    /// Looks for the saved token the first time it is needed (never at launch).
    private func loadTokenIfNeeded() {
        guard !tokenLoaded else { return }
        tokenLoaded = true
        isReady = true
        if let saved = tokens.load(), !saved.isEmpty {
            token = saved
            connection = .connected
        }
    }

    private func scheduleTimer() {
        guard timer == nil, refreshInterval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func reset() {
        openTasks = []
        completedTasks = []
        completedHere = []
        projectNames = [:]
        lingering = []
        busy = []
        accountName = nil
        completedUnavailable = false
        hasLoaded = false
        isLoading = false
        message = nil
        pausedUntil = .distantPast
        generation += 1
    }

    private func reopen(_ task: TodoistTask, token: String, restore: () -> Void) async {
        busy.insert(task.id)
        do {
            try await api.reopen(task.id, token: token)
            busy.remove(task.id)
            await refresh()
        } catch {
            busy.remove(task.id)
            restore()
            handle(error, doing: "mark that task as not done")
        }
    }

    private func setCompleted(_ completed: Bool, for id: String) {
        guard let index = openTasks.firstIndex(where: { $0.id == id }) else { return }
        openTasks[index].isCompleted = completed
    }

    private func moveToOpen(_ task: TodoistTask) {
        completedTasks.removeAll { $0.id == task.id }
        completedHere.removeAll { $0.id == task.id }
        var open = task
        open.isCompleted = false
        open.completedAt = nil
        openTasks.removeAll { $0.id == task.id }
        openTasks.append(open)
        openTasks.sort(by: Self.isOrderedBefore)
    }

    private func moveToCompleted(_ task: TodoistTask, at date: Date) {
        openTasks.removeAll { $0.id == task.id }
        var done = task
        done.isCompleted = true
        done.completedAt = date
        completedTasks.insert(done, at: 0)
    }

    /// Todoist's recently completed tasks plus the ones ticked here that it has not listed yet, most recent first.
    private func mergedCompleted(_ fetched: [TodoistTask]) -> [TodoistTask] {
        let listed = Set(fetched.map(\.id))
        let cutoff = now().addingTimeInterval(-Self.completedHereMinutes * 60)
        // Todoist has caught up with these (or they are too old to still be waiting): stop holding them.
        completedHere.removeAll { listed.contains($0.id) || ($0.completedAt ?? .distantPast) < cutoff }
        let reopenedMeanwhile = Set(openTasks.filter { !$0.isCompleted }.map(\.id))
        let waiting = completedHere.filter { !reopenedMeanwhile.contains($0.id) }
        return Array(
            (fetched + waiting).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                .prefix(Self.completedLimit))
    }

    /// The server's open tasks, but with the ones ticked a moment ago still ticked (the server may not have caught up).
    private func mergedWithLingering(_ fetched: [TodoistTask]) -> [TodoistTask] {
        var merged = fetched
        for id in lingering {
            guard let local = openTasks.first(where: { $0.id == id }) else { continue }
            if let index = merged.firstIndex(where: { $0.id == id }) {
                merged[index].isCompleted = true
            } else {
                merged.append(local)
            }
        }
        return merged
    }

    private func handle(_ error: Error, doing action: String?) {
        switch error as? TodoistError {
        case .unauthorized:
            // The token is no good any more (revoked, or replaced in Todoist's settings): forget it.
            stop()
            tokens.delete()
            token = nil
            reset()
            connection = .disconnected
            message = Message(
                text: "Todoist no longer accepts this token (it may have been replaced or revoked). Paste a new one to reconnect.",
                isError: true)
        case .rateLimited(let wait):
            pausedUntil = now().addingTimeInterval(wait ?? 60)
            message = Message(text: "Todoist asked Island to slow down. It will try again in a little while.", isError: true)
        case .network:
            message = Message(
                text: action.map { "Couldn't reach Todoist, so Island couldn't \($0)." }
                    ?? (hasLoaded ? "Couldn't reach Todoist. Showing what was loaded last." : "Couldn't reach Todoist."),
                isError: true)
        default:
            message = Message(text: action.map { "Todoist wouldn't let Island \($0). Try again." } ?? "Todoist had a problem. Try again in a moment.", isError: true)
        }
    }

    private static func connectMessage(for error: Error) -> String {
        switch error as? TodoistError {
        case .unauthorized:
            return "Todoist didn't accept that token. Copy it again from Todoist: Settings, Integrations, Developer."
        case .forbidden:
            return "That token isn't allowed to read tasks."
        case .network:
            return "Couldn't reach Todoist. Check your internet connection and try again."
        case .rateLimited:
            return "Todoist is asking for a short break. Try again in a minute."
        default:
            return "Todoist had a problem. Try again in a moment."
        }
    }

    private static func names(of projects: [TodoistProject]) -> [String: String] {
        Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Soonest first (overdue at the top), tasks with no date after them, then the more urgent, then by name. A task due on
    /// a day with no time counts as due at the end of that day, so one that was due earlier today at a set time (and is
    /// overdue now) comes before it.
    static func isOrderedBefore(_ lhs: TodoistTask, _ rhs: TodoistTask) -> Bool {
        switch (lhs.due, rhs.due) {
        case let (left?, right?) where sortMoment(left) != sortMoment(right): return sortMoment(left) < sortMoment(right)
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.content.localizedCaseInsensitiveCompare(rhs.content) == .orderedAscending
    }

    private static func sortMoment(_ due: TodoistDue) -> Date {
        due.hasTime ? due.date : due.date.addingTimeInterval(86_399)
    }
}
