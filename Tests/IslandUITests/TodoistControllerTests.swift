import Testing
import Foundation
import IslandCore
@testable import IslandUI

// MARK: Stand-ins

private final class FakeAPI: TodoistAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var open: [TodoistTask] = []
    var done: [TodoistTask] = []
    var projectList: [TodoistProject] = [TodoistProject(id: "p1", name: "Home", isInbox: false)]
    var name: String? = "Jane Doe"
    /// Thrown by every call while set.
    var failure: Error?
    var closeFailure: Error?
    var reopenFailure: Error?
    var createFailure: Error?
    /// Waits here (once) before the open tasks are returned, so a test can change something mid-refresh.
    var openGate: (@Sendable () async -> Void)?
    var created: TodoistTask = TodoistTask(id: "new", content: "New")
    /// Thrown by the completed-tasks call only.
    var completedFailure: Error?
    /// When set, Todoist's completed list is slow to show a task that was just ticked off.
    var completedLags = false

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return log }
    private func record(_ call: String) { lock.lock(); log.append(call); lock.unlock() }

    func openTasks(token: String) async throws -> [TodoistTask] {
        record("open:\(token)")
        if let failure { throw failure }
        if let gate = openGate { openGate = nil; await gate() }
        return open
    }
    func completedTasks(token: String, since: Date, until: Date) async throws -> [TodoistTask] {
        record("completed")
        if let failure { throw failure }
        if let completedFailure { throw completedFailure }
        return done
    }
    func projects(token: String) async throws -> [TodoistProject] {
        record("projects:\(token)")
        if let failure { throw failure }
        return projectList
    }
    func accountName(token: String) async throws -> String? { record("user"); return name }
    func close(_ id: String, token: String) async throws {
        record("close:\(id)")
        if let closeFailure { throw closeFailure }
        if let failure { throw failure }
        // Like the real thing: the task leaves the open list and (soon) shows in the completed one.
        guard let index = open.firstIndex(where: { $0.id == id }) else { return }
        var finished = open.remove(at: index)
        finished.isCompleted = true
        finished.completedAt = Date(timeIntervalSince1970: 1_794_000_000)
        if !completedLags { done.insert(finished, at: 0) }
    }
    func reopen(_ id: String, token: String) async throws {
        record("reopen:\(id)")
        if let reopenFailure { throw reopenFailure }
        if let failure { throw failure }
        guard let index = done.firstIndex(where: { $0.id == id }) else { return }
        var again = done.remove(at: index)
        again.isCompleted = false
        again.completedAt = nil
        open.append(again)
    }
    func create(title: String, due: Date?, token: String) async throws -> TodoistTask {
        record("create:\(title):\(due.map { String(Int($0.timeIntervalSince1970)) } ?? "-")")
        if let createFailure { throw createFailure }
        if let failure { throw failure }
        var task = created
        task.content = title
        open.append(task)
        return task
    }
    func quickAdd(text: String, token: String) async throws -> TodoistTask {
        record("quick:\(text)")
        if let createFailure { throw createFailure }
        if let failure { throw failure }
        var task = created
        task.content = text
        open.append(task)
        return task
    }
}

private final class FakeTokens: TokenStoring {
    var stored: String?
    var saveWorks = true
    private(set) var loads = 0
    init(stored: String? = nil) { self.stored = stored }
    func load() -> String? { loads += 1; return stored }
    func save(_ token: String) -> Bool { if saveWorks { stored = token }; return saveWorks }
    func delete() { stored = nil }
}

private let clock = Date(timeIntervalSince1970: 1_794_000_000)

private func task(_ id: String, _ content: String, due: Double? = nil, priority: Int = 1, project: String? = "p1", completed: Bool = false) -> TodoistTask {
    TodoistTask(
        id: id, content: content, projectID: project, priority: priority,
        due: due.map { TodoistDue(date: clock.addingTimeInterval($0), hasTime: true) },
        isCompleted: completed, completedAt: completed ? clock.addingTimeInterval(-60) : nil)
}

@MainActor private func make(api: FakeAPI = FakeAPI(), tokens: FakeTokens = FakeTokens(), linger: TimeInterval = 0)
    -> (TodoistController, FakeAPI, FakeTokens)
{
    (TodoistController(api: api, tokens: tokens, now: { clock }, refreshInterval: 0, lingerSeconds: linger), api, tokens)
}

@MainActor private func connected(_ api: FakeAPI = FakeAPI()) async -> (TodoistController, FakeAPI, FakeTokens) {
    let (controller, api, tokens) = make(api: api, tokens: FakeTokens(stored: "tok"))
    await controller.start()
    return (controller, api, tokens)
}

// MARK: Connecting

@Test @MainActor func theKeychainIsNotReadUntilTheTodoistViewOpens() async {
    let (controller, api, tokens) = make(tokens: FakeTokens(stored: "tok"))
    #expect(tokens.loads == 0 && controller.connection == .disconnected && api.calls.isEmpty)   // nothing at launch
    await controller.start()
    #expect(tokens.loads == 1 && controller.connection == .connected)
}

@Test @MainActor func noSavedTokenMeansTheConnectScreenAndNoNetwork() async {
    let (controller, api, _) = make()
    await controller.start()
    #expect(controller.connection == .disconnected && api.calls.isEmpty)
}

@Test @MainActor func aSavedTokenLoadsTheTasksSortedWithProjectNames() async {
    let api = FakeAPI()
    api.open = [
        task("a", "No date"), task("b", "Later", due: 7200), task("c", "Overdue", due: -3600),
        task("d", "Urgent, no date", priority: 4), task("e", "Soon", due: 600),
    ]
    api.done = [task("x", "Old", completed: true)]
    let (controller, _, _) = await connected(api)
    #expect(controller.openTasks.map(\.id) == ["c", "e", "b", "d", "a"])    // overdue, soon, later, then undated by urgency
    #expect(controller.completedTasks.map(\.id) == ["x"] && controller.hasLoaded)
    #expect(controller.projectName(for: controller.openTasks[0]) == "Home")
    #expect(controller.activeCount == 5 && controller.completedCount == 1)
}

@Test @MainActor func pastingAGoodTokenKeepsItAndLoads() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    let (controller, _, tokens) = make(api: api)
    await controller.connect(token: "  good-token\n")
    #expect(controller.connection == .connected && tokens.stored == "good-token")      // trimmed, saved
    #expect(controller.accountName == "Jane Doe" && controller.openTasks.count == 1 && controller.message == nil)
    #expect(api.calls.first == "projects:good-token")                                   // checked before anything is kept
}

@Test @MainActor func aRefusedTokenIsNotKeptAndSaysWhy() async {
    let api = FakeAPI()
    api.failure = TodoistError.unauthorized
    let (controller, _, tokens) = make(api: api)
    await controller.connect(token: "wrong")
    #expect(controller.connection == .disconnected && tokens.stored == nil)
    #expect(controller.message?.isError == true && controller.message?.text.contains("didn't accept that token") == true)
}

@Test @MainActor func connectingWithoutInternetOrWithoutKeychainAccessSaysSo() async {
    let offline = FakeAPI()
    offline.failure = TodoistError.network("offline")
    let (first, _, firstTokens) = make(api: offline)
    await first.connect(token: "t")
    #expect(first.message?.text.contains("Couldn't reach Todoist") == true && firstTokens.stored == nil)

    let (second, _, secondTokens) = make(tokens: FakeTokens())
    secondTokens.saveWorks = false
    await second.connect(token: "t")
    #expect(second.connection == .disconnected && second.message?.text.contains("Keychain") == true)
}

@Test @MainActor func anEmptyPasteDoesNothing() async {
    let (controller, api, _) = make()
    await controller.connect(token: "   ")
    #expect(controller.connection == .disconnected && api.calls.isEmpty && controller.message == nil)
}

@Test @MainActor func disconnectingForgetsTheTokenAndEverythingLoaded() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    let (controller, _, tokens) = await connected(api)
    controller.disconnect()
    #expect(tokens.stored == nil && controller.connection == .disconnected)
    #expect(controller.openTasks.isEmpty && controller.completedTasks.isEmpty && controller.accountName == nil && !controller.hasLoaded)
}

// MARK: Ticking

@Test @MainActor func tickingATaskShowsAtOnceAndMovesItToCompleted() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk"), task("b", "Call mom")]
    let (controller, _, _) = await connected(api)
    let milk = controller.openTasks[0]
    await controller.toggle(milk)
    #expect(api.calls.contains("close:a"))
    #expect(controller.openTasks.map(\.id) == ["b"] && controller.completedTasks.first?.id == "a")
    #expect(controller.completedTasks.first?.isCompleted == true && controller.lingering.isEmpty)
}

@Test @MainActor func aTickIsStruckThroughWhileItLingers() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    let (controller, _, _) = make(api: api, tokens: FakeTokens(stored: "tok"), linger: 0.4)
    await controller.start()
    let toggling = Task { await controller.toggle(controller.openTasks[0]) }
    try? await Task.sleep(nanoseconds: 120_000_000)
    #expect(controller.lingering == ["a"] && controller.openTasks.first?.isCompleted == true)   // still in Active, ticked
    #expect(controller.activeCount == 0)                                                        // but not counted as to do
    await toggling.value
    #expect(controller.lingering.isEmpty && controller.openTasks.isEmpty)
}

@Test @MainActor func aTickTodoistRefusesIsUndoneWithAMessage() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    let (controller, _, _) = await connected(api)
    api.closeFailure = TodoistError.server(500)
    await controller.toggle(controller.openTasks[0])
    #expect(controller.openTasks.count == 1 && controller.openTasks[0].isCompleted == false && controller.lingering.isEmpty)
    #expect(controller.completedTasks.isEmpty && controller.message?.text.contains("mark that task as done") == true)
}

@Test @MainActor func puttingACompletedTaskBackReopensIt() async {
    let api = FakeAPI()
    api.done = [task("x", "Old", completed: true)]
    let (controller, _, _) = await connected(api)
    await controller.toggle(controller.completedTasks[0])
    #expect(api.calls.contains("reopen:x"))
    #expect(controller.openTasks.map(\.id) == ["x"] && controller.completedTasks.isEmpty)
}

@Test @MainActor func aFailedReopenPutsItBackInCompleted() async {
    let api = FakeAPI()
    api.done = [task("x", "Old", completed: true)]
    let (controller, _, _) = await connected(api)
    api.reopenFailure = TodoistError.network("offline")
    await controller.toggle(controller.completedTasks[0])
    #expect(controller.openTasks.isEmpty && controller.completedTasks.map(\.id) == ["x"])
    #expect(controller.message?.text.contains("Couldn't reach Todoist") == true)
}

// MARK: Adding

@Test @MainActor func aTaskWithATimeIsCreatedAsTypedAndOneWithoutIsQuickAdded() async {
    let api = FakeAPI()
    let (controller, _, _) = await connected(api)
    let due = clock.addingTimeInterval(3600)
    #expect(await controller.add(title: "  Call mom  ", due: due))
    #expect(api.calls.contains("create:Call mom:\(Int(due.timeIntervalSince1970))"))
    #expect(await controller.add(title: "Pay rent tomorrow 6pm", due: nil))
    #expect(api.calls.contains("quick:Pay rent tomorrow 6pm"))
    #expect(!(await controller.add(title: "   ", due: nil)))                       // nothing to add
    #expect(controller.openTasks.map(\.content).contains("Call mom"))
}

@Test @MainActor func aTaskThatCouldNotBeAddedReportsFalseAndSaysSo() async {
    let api = FakeAPI()
    let (controller, _, _) = await connected(api)
    api.createFailure = TodoistError.network("offline")
    #expect(!(await controller.add(title: "Call mom", due: nil)))
    #expect(controller.message?.text == "Couldn't reach Todoist, so Island couldn't add that task.")
}

// MARK: When things go wrong while loading

@Test @MainActor func aRevokedTokenIsForgottenAndTheConnectScreenReturns() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    let (controller, _, tokens) = await connected(api)
    api.failure = TodoistError.unauthorized
    await controller.refresh()
    #expect(controller.connection == .disconnected && tokens.stored == nil && controller.openTasks.isEmpty)
    #expect(controller.message?.text.contains("no longer accepts") == true)
}

@Test @MainActor func lostInternetKeepsWhatWasLoaded() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    let (controller, _, _) = await connected(api)
    api.failure = TodoistError.network("offline")
    await controller.refresh()
    #expect(controller.connection == .connected && controller.openTasks.count == 1)
    #expect(controller.message?.text == "Couldn't reach Todoist. Showing what was loaded last.")
    api.failure = nil
    await controller.refresh()
    #expect(controller.message == nil)                                              // it clears itself on the next good load
}

@Test @MainActor func beingToldToSlowDownPausesRefreshing() async {
    let api = FakeAPI()
    let (controller, _, _) = await connected(api)
    api.failure = TodoistError.rateLimited(retryAfter: 120)
    await controller.refresh()
    #expect(controller.message?.text.contains("slow down") == true)
    let before = api.calls.count
    api.failure = nil
    await controller.refresh()                                                      // still inside the 120 seconds
    #expect(api.calls.count == before)
}

@Test @MainActor func aRefreshThatStartedBeforeAChangeCannotUndoIt() async {
    let api = FakeAPI()
    api.open = [task("a", "Old list")]
    let (controller, _, _) = await connected(api)
    // The next refresh will hang at the open tasks until released, and then report the list as it was.
    let release = Release()
    api.openGate = { await release.wait() }
    let refreshing = Task { await controller.refresh() }
    try? await Task.sleep(nanoseconds: 100_000_000)
    api.open = [task("a", "Old list"), task("new", "Added meanwhile")]
    _ = await controller.add(title: "Added meanwhile", due: nil)       // a change made while the refresh is waiting
    await release.open()
    await refreshing.value
    #expect(controller.openTasks.map(\.id).contains("new"))
}

@Test @MainActor func aProjectNobodyKnowsIsFetchedWhenATaskPointsAtIt() async {
    let api = FakeAPI()
    api.open = [task("a", "Elsewhere", project: "p-new")]
    api.projectList = [TodoistProject(id: "p-new", name: "Garden")]
    let (controller, _, _) = await connected(api)
    #expect(controller.projectName(for: controller.openTasks[0]) == "Garden")
}

/// A gate a test can hold something at and then open.
private actor Release {
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        opened = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

@Test @MainActor func aTickedTaskStaysInCompletedEvenIfTodoistsListLagsBehind() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    api.completedLags = true                                    // Todoist's completed list will not show it yet
    let (controller, _, _) = await connected(api)
    await controller.toggle(controller.openTasks[0])
    #expect(controller.openTasks.isEmpty && controller.completedTasks.map(\.id) == ["a"])
    await controller.refresh()                                   // still not listed there: it is held on to
    #expect(controller.completedTasks.map(\.id) == ["a"])
    api.done = [task("a", "Buy milk", completed: true)]          // now Todoist lists it: no duplicate
    await controller.refresh()
    #expect(controller.completedTasks.map(\.id) == ["a"])
    api.done = []                                                // (listed once, then gone: nothing keeps it any more)
    await controller.refresh()
    #expect(controller.completedTasks.isEmpty)
}

@Test @MainActor func aTaskPutBackIsNotShownAsCompletedAnyMore() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    api.completedLags = true
    let (controller, _, _) = await connected(api)
    await controller.toggle(controller.openTasks[0])
    #expect(controller.completedTasks.map(\.id) == ["a"])
    api.open = [task("a", "Buy milk")]                           // reopened in Todoist
    await controller.toggle(controller.completedTasks[0])
    #expect(controller.completedTasks.isEmpty && controller.openTasks.map(\.id) == ["a"])
}

@Test @MainActor func anAccountThatCannotListCompletedTasksStillGetsItsOpenOnes() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    api.completedFailure = TodoistError.forbidden
    let (controller, _, _) = await connected(api)
    #expect(controller.connection == .connected && controller.openTasks.map(\.id) == ["a"])
    #expect(controller.completedUnavailable && controller.message == nil)       // not an error: nothing to retry
    #expect(controller.hasLoaded)
    // What is ticked off here still lands in Completed.
    await controller.toggle(controller.openTasks[0])
    #expect(controller.completedTasks.map(\.id) == ["a"])
}

@Test @MainActor func aBadTokenOnTheCompletedCallStillDisconnects() async {
    let api = FakeAPI()
    api.open = [task("a", "Buy milk")]
    let (controller, _, tokens) = await connected(api)
    api.completedFailure = TodoistError.unauthorized
    await controller.refresh()
    #expect(controller.connection == .disconnected && tokens.stored == nil)
}

@Test @MainActor func aTaskDueTodayWithNoTimeComesAfterOneThatIsOverdueTodayAtASetTime() async {
    let api = FakeAPI()
    let startOfDay = TodoistTask(
        id: "day", content: "All day today", projectID: "p1",
        due: TodoistDue(date: clock.addingTimeInterval(-10 * 3600), hasTime: false))      // midnight, 10 hours ago
    api.open = [startOfDay, task("late", "Overdue at a set time", due: -3 * 3600), task("none", "No date")]
    let (controller, _, _) = await connected(api)
    #expect(controller.openTasks.map(\.id) == ["late", "day", "none"])
}
