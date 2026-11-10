import Foundation
import Testing
import IslandCore
@testable import IslandUI

// MARK: Stand-ins

private final class TeamsStore: TokenStoring, @unchecked Sendable {
    var value: String?
    var failSaves = false
    private(set) var saves = 0
    func load() -> String? { value }
    func save(_ token: String) -> Bool {
        guard !failSaves else { return false }
        saves += 1
        value = token
        return true
    }
    func delete() { value = nil }
}

private actor TeamsGate {
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async { if open { return }; await withCheckedContinuation { waiting.append($0) } }
    func release() { open = true; waiting.forEach { $0.resume() }; waiting = [] }
}

private final class FakeTeams: TeamsAPI, @unchecked Sendable {
    var me = TeamsAccount(id: "me-id", displayName: "Charvit Z")
    var chats: [TeamsChat] = []
    var messagesByChat: [String: [TeamsMessage]] = [:]
    /// Errors to throw from the next calls to `chats`, one each (then it answers normally).
    var chatFailures: [Error] = []
    var messageGates: [String: TeamsGate] = [:]

    // Calls can arrive from several threads at once (the controller asks without waiting), so the record is locked.
    private let lock = NSLock()
    private var recordedCalls: [String] = []
    private var recordedTokens: [String] = []
    var calls: [String] { lock.lock(); defer { lock.unlock() }; return recordedCalls }
    var tokensUsed: [String] { lock.lock(); defer { lock.unlock() }; return recordedTokens }

    private func record(_ call: String, _ token: String) {
        lock.lock(); defer { lock.unlock() }
        recordedCalls.append(call)
        recordedTokens.append(token)
    }
    private func nextFailure() -> Error? {
        lock.lock(); defer { lock.unlock() }
        return chatFailures.isEmpty ? nil : chatFailures.removeFirst()
    }

    func account(token: String) async throws -> TeamsAccount { record("account", token); return me }
    func chats(token: String) async throws -> [TeamsChat] {
        record("chats", token)
        if let failure = nextFailure() { throw failure }
        return chats
    }
    func messages(token: String, chatID: String) async throws -> [TeamsMessage] {
        record("messages:\(chatID)", token)
        if let gate = messageGates[chatID] { await gate.wait() }
        return messagesByChat[chatID] ?? []
    }
}

private final class FakeAuth: TeamsAuthenticating, @unchecked Sendable {
    var signInResult: Result<TeamsSession, Error> = .success(TeamsSession(clientID: "cid", tenant: "organizations", accessToken: "AT1", refreshToken: "RT1", expiresAt: Date(timeIntervalSinceNow: 3600)))
    /// Never finishes (until cancelled), like a browser nobody finishes signing in in.
    var hangs = false
    var refreshResult: Result<TeamsSession, Error> = .success(TeamsSession(clientID: "cid", tenant: "organizations", accessToken: "AT2", refreshToken: "RT2", expiresAt: Date(timeIntervalSinceNow: 3600)))
    var refreshDelay: UInt64 = 0
    private(set) var signIns: [(clientID: String, tenant: String)] = []
    private let lock = NSLock()
    private var refreshCount = 0
    var refreshes: Int { lock.lock(); defer { lock.unlock() }; return refreshCount }
    private func countRefresh() { lock.lock(); refreshCount += 1; lock.unlock() }

    func signIn(clientID: String, tenant: String, openBrowser: @Sendable (URL) -> Void) async throws -> TeamsSession {
        signIns.append((clientID, tenant))
        openBrowser(URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/authorize?client_id=\(clientID)")!)
        if hangs { try await Task.sleep(nanoseconds: 60_000_000_000) }
        var result = try signInResult.get()
        result.clientID = clientID
        result.tenant = tenant
        return result
    }
    func refresh(_ session: TeamsSession) async throws -> TeamsSession {
        countRefresh()
        if refreshDelay > 0 { try await Task.sleep(nanoseconds: refreshDelay) }
        return try refreshResult.get()
    }
}

private let goodID = "0a1b2c3d-1234-5678-9abc-def012345678"

private func session(_ access: String = "AT0", expires: TimeInterval = 3600) -> TeamsSession {
    TeamsSession(clientID: goodID, tenant: "organizations", accessToken: access, refreshToken: "RT0", expiresAt: Date(timeIntervalSinceNow: expires))
}

private func encoded(_ session: TeamsSession) -> String {
    String(decoding: try! JSONEncoder().encode(session), as: UTF8.self)
}

private func chat(_ id: String, _ topic: String? = nil, kind: TeamsChat.Kind = .group, members: [String] = [], minutesAgo: Double = 5) -> TeamsChat {
    TeamsChat(
        id: id, kind: kind, topic: topic, members: members.map { TeamsMessageMember($0) },
        preview: TeamsPreview(text: "hello", sender: members.first, date: Date(timeIntervalSinceNow: -minutesAgo * 60)))
}

private func TeamsMessageMember(_ name: String) -> TeamsMember { TeamsMember(userID: name == "Charvit Z" ? "me-id" : name.lowercased(), name: name) }

private func message(_ id: String, from sender: String = "Ravi", text: String = "hi") -> TeamsMessage {
    TeamsMessage(id: id, senderName: sender, senderID: sender == "Charvit Z" ? "me-id" : sender.lowercased(), date: Date(), runs: [TeamsRun(text: text)])
}

private struct Rig {
    let controller: TeamsController
    let api: FakeTeams
    let auth: FakeAuth
    let sessions: TeamsStore
    let config: TeamsStore
    let opened: Opened

    final class Opened: @unchecked Sendable { var urls: [URL] = []; var browser: [URL] = []; var pullRequests: [String] = [] }
}

@MainActor private func rig(saved: TeamsSession? = nil, chats: [TeamsChat] = [], chatInterval: TimeInterval = 0, messageInterval: TimeInterval = 0) -> Rig {
    let api = FakeTeams(), auth = FakeAuth(), sessions = TeamsStore(), config = TeamsStore(), opened = Rig.Opened()
    api.chats = chats
    if let saved { sessions.value = encoded(saved) }
    let controller = TeamsController(
        api: api, auth: auth, sessions: sessions, config: config, chatInterval: chatInterval, messageInterval: messageInterval,
        openBrowser: { opened.browser.append($0) }, openExternally: { opened.urls.append($0) })
    controller.openPullRequest = { opened.pullRequests.append($0) }
    return Rig(controller: controller, api: api, auth: auth, sessions: sessions, config: config, opened: opened)
}

@MainActor private func teamsEventually(timeout: TimeInterval = 4, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 15_000_000)
    }
    return condition()
}

// MARK: Signing in

@Test @MainActor func teamsRefusesAnythingThatIsNotAClientIdBeforeOpeningTheBrowser() async {
    let r = rig()
    await r.controller.start()                       // looks for a saved sign-in: none
    r.controller.clientID = "https://entra.microsoft.com"
    await r.controller.signIn()
    #expect(r.controller.connection == .disconnected)
    #expect(r.controller.message?.text.contains("Application (client) ID") == true)
    #expect(r.auth.signIns.isEmpty && r.opened.browser.isEmpty)
    #expect(r.config.value == nil)                   // nothing was remembered either
}

@Test @MainActor func teamsSigningInKeepsTheSessionInTheKeychainAndLoadsTheChats() async throws {
    let r = rig(chats: [chat("a", "Squad")])
    await r.controller.start()
    r.controller.clientID = "  \(goodID.uppercased()) "
    await r.controller.signIn()

    #expect(r.controller.connection == .connected && r.controller.message == nil)
    #expect(r.auth.signIns.count == 1 && r.auth.signIns[0].clientID == goodID && r.auth.signIns[0].tenant == "organizations")
    #expect(r.opened.browser.count == 1)             // the sign-in page opened in the browser
    #expect(r.api.tokensUsed.allSatisfy { $0 == "AT1" })
    #expect(r.controller.account?.displayName == "Charvit Z")
    #expect(r.controller.chats.map(\.id) == ["a"] && r.controller.chatsLoaded)

    // The session is in the Keychain stand-in (and only there); the app's id is remembered too, as it holds no secret.
    let saved = try JSONDecoder().decode(TeamsSession.self, from: Data(try #require(r.sessions.value).utf8))
    #expect(saved.accessToken == "AT1" && saved.refreshToken == "RT1" && saved.clientID == goodID)
    #expect(r.config.value?.contains(goodID) == true && r.config.value?.contains("AT1") == false)
}

@Test @MainActor func teamsTheApplicationIdSurvivesALaunchButTheSessionIsReadOnlyWhenTheTabOpens() async {
    let r = rig()
    #expect(r.controller.isReady == false && r.controller.connection == .disconnected)   // nothing read from the Keychain yet
    r.config.value = #"{"clientID":"\#(goodID)","tenant":"contoso.com"}"#
    await r.controller.start()
    #expect(r.controller.isReady && r.controller.clientID == goodID && r.controller.tenant == "contoso.com")
}

@Test @MainActor func teamsACompanyThatMustApproveTheAppIsToldSoAndNothingIsSaved() async {
    let r = rig()
    r.auth.signInResult = .failure(TeamsError.needsApproval("AADSTS65001: The user or administrator has not consented to use the application."))
    r.controller.clientID = goodID
    await r.controller.signIn()
    #expect(r.controller.connection == .disconnected)
    let text = r.controller.message?.text ?? ""
    #expect(text.contains("IT admin") && text.contains("Chat.Read") && text.contains("not consented"))
    #expect(r.sessions.value == nil && r.controller.clientID == goodID)         // the id stays so trying again is one press
}

@Test @MainActor func teamsCancellingTheSignInGoesBackWithoutAComplaint() async {
    let r = rig()
    r.auth.hangs = true
    r.controller.clientID = goodID
    let signingIn = Task { await r.controller.signIn() }
    let waiting = await teamsEventually { r.controller.connection == .connecting }
    #expect(waiting)
    r.controller.cancelSignIn()
    await signingIn.value
    #expect(r.controller.connection == .disconnected && r.controller.message == nil && r.sessions.value == nil)
}

@Test @MainActor func teamsAKeychainThatRefusesTheSessionMeansNotConnected() async {
    let r = rig()
    r.sessions.failSaves = true
    r.controller.clientID = goodID
    await r.controller.signIn()
    #expect(r.controller.connection == .disconnected)
    #expect(r.controller.message?.text.contains("Keychain") == true)
}

// MARK: Staying signed in

@Test @MainActor func teamsASavedSessionLoadsTheChatsWithoutSigningInAgain() async {
    let r = rig(saved: session("AT-saved"), chats: [chat("a", "Squad"), chat("b", "Other", minutesAgo: 60)])
    await r.controller.start()
    #expect(r.controller.connection == .connected && r.auth.signIns.isEmpty && r.auth.refreshes == 0)
    #expect(r.api.tokensUsed.allSatisfy { $0 == "AT-saved" })
    #expect(r.controller.chats.count == 2 && r.controller.account?.id == "me-id")
}

@Test @MainActor func teamsAnExpiredAccessTokenIsRefreshedBeforeUseAndSeveralCallsAtOnceShareOneRefresh() async throws {
    let r = rig(saved: session("AT-old", expires: -10), chats: [chat("a", "Squad")])
    r.auth.refreshDelay = 80_000_000
    // Two things ask at the same moment (the tab opening twice, say) while the saved token has run out.
    async let first: Void = r.controller.start()
    async let second: Void = r.controller.start()
    _ = await (first, second)

    #expect(r.auth.refreshes == 1)                                   // one refresh, shared
    #expect(!r.api.tokensUsed.isEmpty && r.api.tokensUsed.allSatisfy { $0 == "AT2" })   // nothing went out with the expired token
    #expect(r.controller.connection == .connected && r.controller.chats.map(\.id) == ["a"])
    let saved = try JSONDecoder().decode(TeamsSession.self, from: Data(try #require(r.sessions.value).utf8))
    #expect(saved.accessToken == "AT2" && saved.refreshToken == "RT2")   // the fresh session is kept for next time
}

@Test @MainActor func teamsARefreshMicrosoftRefusesSignsOutAndKeepsTheApplicationId() async {
    let r = rig(saved: session("AT-old", expires: -10), chats: [chat("a", "Squad")])
    r.config.value = #"{"clientID":"\#(goodID)","tenant":"organizations"}"#
    r.auth.refreshResult = .failure(TeamsError.unauthorized)
    await r.controller.start()
    #expect(r.controller.connection == .disconnected)
    #expect(r.sessions.value == nil)                                  // the dead session is gone from the Keychain
    #expect(r.controller.message?.text.contains("Sign in again") == true)
    #expect(r.controller.clientID == goodID)
    #expect(r.controller.chats.isEmpty)
}

@Test @MainActor func teamsATokenMicrosoftTurnsDownGetsOneRefreshAndOneRetry() async {
    let r = rig(saved: session("AT-revoked"), chats: [chat("a", "Squad")])
    r.api.chatFailures = [TeamsError.unauthorized]                   // the first answer: "no" although the token looked valid
    await r.controller.start()
    #expect(r.auth.refreshes == 1)
    #expect(r.controller.connection == .connected && r.controller.chats.map(\.id) == ["a"] && r.controller.message == nil)
    #expect(r.api.tokensUsed.last == "AT2")
}

@Test @MainActor func teamsATokenMicrosoftKeepsRefusingEndsTheSession() async {
    let r = rig(saved: session("AT-revoked"), chats: [chat("a", "Squad")])
    r.api.chatFailures = [TeamsError.unauthorized, TeamsError.unauthorized]
    await r.controller.start()
    #expect(r.controller.connection == .disconnected && r.sessions.value == nil)
}

@Test @MainActor func teamsSigningOutForgetsTheSessionAndTheChatsButNotTheApplicationId() async {
    let r = rig(saved: session(), chats: [chat("a", "Squad")])
    r.config.value = #"{"clientID":"\#(goodID)","tenant":"organizations"}"#
    await r.controller.start()
    await r.controller.open(chat("a", "Squad"))
    r.controller.disconnect()
    #expect(r.controller.connection == .disconnected && r.sessions.value == nil)
    #expect(r.controller.chats.isEmpty && r.controller.openChat == nil && r.controller.account == nil)
    #expect(r.controller.clientID == goodID)
}

@Test @MainActor func teamsBeingToldToSlowDownPausesTheNextLoads() async {
    let r = rig(saved: session(), chats: [chat("a", "Squad")])
    r.api.chatFailures = [TeamsError.rateLimited(until: Date(timeIntervalSinceNow: 300))]
    await r.controller.start()
    #expect(r.controller.message?.text.contains("slow down") == true)
    let before = r.api.calls.filter { $0 == "chats" }.count
    await r.controller.refreshChats()
    #expect(r.api.calls.filter { $0 == "chats" }.count == before)    // asked for nothing while it is paused
}

// MARK: Chats and messages

@Test @MainActor func teamsChatsAreNamedAndSearchedByWhoIsInThem() async {
    let squad = chat("g", "Finance squad", members: ["Charvit Z", "Ana", "Raj"])
    let ravi = chat("r", nil, kind: .oneOnOne, members: ["Charvit Z", "Ravi Shah"])
    let r = rig(saved: session(), chats: [squad, ravi])
    await r.controller.start()
    #expect(r.controller.title(of: ravi) == "Ravi Shah" && r.controller.title(of: squad) == "Finance squad")
    r.controller.filter = "ravi"
    #expect(r.controller.visibleChats.map(\.id) == ["r"])
    r.controller.filter = "raj"                                      // a member of a group, not in its title
    #expect(r.controller.visibleChats.map(\.id) == ["g"])
    r.controller.filter = "nobody"
    #expect(r.controller.visibleChats.isEmpty)
}

@Test @MainActor func teamsOpeningAChatLoadsItsMessagesAndMarksOwnOnes() async {
    let a = chat("a", "Squad")
    let r = rig(saved: session(), chats: [a])
    r.api.messagesByChat["a"] = [message("1"), message("2", from: "Charvit Z", text: "on it")]
    await r.controller.start()
    await r.controller.open(a)
    #expect(r.controller.openChat?.id == "a" && r.controller.messages.map(\.id) == ["1", "2"] && r.controller.messagesLoaded)
    #expect(r.controller.isMine(r.controller.messages[1]) && !r.controller.isMine(r.controller.messages[0]))
    r.controller.closeChat()
    #expect(r.controller.openChat == nil && r.controller.messages.isEmpty)
}

@Test @MainActor func teamsALateAnswerForAnEarlierChatIsIgnored() async {
    let a = chat("a", "A"), b = chat("b", "B")
    let r = rig(saved: session(), chats: [a, b])
    r.api.messagesByChat["a"] = [message("from-a")]
    r.api.messagesByChat["b"] = [message("from-b")]
    let gate = TeamsGate()
    r.api.messageGates["a"] = gate
    await r.controller.start()

    let openingA = Task { await r.controller.open(a) }
    let asked = await teamsEventually { r.api.calls.contains("messages:a") }
    #expect(asked)
    await r.controller.open(b)                                       // the person moved on to B while A was still loading
    #expect(r.controller.messages.map(\.id) == ["from-b"])
    await gate.release()
    await openingA.value
    #expect(r.controller.openChat?.id == "b" && r.controller.messages.map(\.id) == ["from-b"])   // A's late answer changed nothing
}

@Test @MainActor func teamsALateMessageAnswerAfterGoingBackToTheListChangesNothing() async {
    let a = chat("a", "A")
    let r = rig(saved: session(), chats: [a])
    r.api.messagesByChat["a"] = [message("late")]
    let gate = TeamsGate()
    r.api.messageGates["a"] = gate
    await r.controller.start()
    let opening = Task { await r.controller.open(a) }
    _ = await teamsEventually { r.api.calls.contains("messages:a") }
    r.controller.closeChat()
    await gate.release()
    await opening.value
    #expect(r.controller.openChat == nil && r.controller.messages.isEmpty)
}

// MARK: Links

@Test @MainActor func teamsAClickOnAPullRequestOpensItInIslandAndACommandClickOpensItInTheBrowser() {
    let r = rig()
    let pull = URL(string: "https://github.com/shipmnts/finance/pull/757")!

    r.controller.activate(pull, commandHeld: false)
    #expect(r.opened.pullRequests == ["https://github.com/shipmnts/finance/pull/757"] && r.opened.urls.isEmpty)

    r.controller.activate(pull, commandHeld: true)                   // Command: the app that handles it (the browser), not Island
    #expect(r.opened.pullRequests.count == 1 && r.opened.urls == [pull])

    let other = URL(string: "https://example.com/docs")!             // not a pull request: always the browser
    r.controller.activate(other, commandHeld: false)
    let issue = URL(string: "https://github.com/shipmnts/finance/issues/3")!
    r.controller.activate(issue, commandHeld: false)
    #expect(r.opened.urls == [pull, other, issue] && r.opened.pullRequests.count == 1)

    // A pull request address with more on the end (the files tab) still opens for review.
    r.controller.activate(URL(string: "https://github.com/shipmnts/finance/pull/757/files")!, commandHeld: false)
    #expect(r.opened.pullRequests.last == "https://github.com/shipmnts/finance/pull/757/files")
}

@Test @MainActor func teamsTheChatsOwnPageOpensInTheBrowserOrTeams() {
    let r = rig()
    let web = URL(string: "https://teams.microsoft.com/l/chat/19%3Aabc/0")!
    r.controller.openInTeams(TeamsChat(id: "x", kind: .group, webURL: web))
    r.controller.openInTeams(TeamsChat(id: "y", kind: .group, webURL: nil))      // no address: nothing happens
    #expect(r.opened.urls == [web])
}

// MARK: Opening a pull request from a message

private final class TeamsHub: GitHubAPI, @unchecked Sendable {
    func account(token: String) async throws -> GitHubAccount { GitHubAccount(login: "charvit") }
    func repos(token: String) async throws -> [GitHubRepo] { [] }
    func repo(token: String, _ ref: GitHubRepoRef) async throws -> GitHubRepo { GitHubRepo(id: 7, fullName: ref.fullName, owner: ref.owner, name: ref.name, isPrivate: true) }
    func branches(token: String, _ repo: GitHubRepoRef) async throws -> [GitHubBranch] { [] }
    func branch(token: String, _ repo: GitHubRepoRef, name: String) async throws -> GitHubBranch { throw GitHubError.notFound }
    func compare(token: String, _ repo: GitHubRepoRef, base: String, head: String) async throws -> GitHubComparison { throw GitHubError.notFound }
    func pullRequestTemplate(token: String, _ repo: GitHubRepoRef) async throws -> String? { nil }
    func createPullRequest(token: String, _ repo: GitHubRepoRef, title: String, head: String, base: String, body: String, draft: Bool) async throws -> GitHubPullRequest { throw GitHubError.notFound }
    func openPullRequest(token: String, _ repo: GitHubRepoRef, head: String, base: String) async throws -> GitHubPullRequest? { nil }
    func pullRequestLists(token: String) async throws -> GitHubPullRequestLists { GitHubPullRequestLists(mine: [], review: []) }
    func searchPullRequests(token: String, query: String) async throws -> [GitHubPullRequest] { [] }
    func pullRequest(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequest? {
        GitHubPullRequest(number: number, title: "Use locking read", url: URL(string: "https://github.com/\(repo.fullName)/pull/\(number)")!, repoFullName: repo.fullName, authorLogin: "prasannshah", headBranch: "fix/x", baseBranch: "staging")
    }
    func pullRequestDetails(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequestDetails {
        GitHubPullRequestDetails(pullRequest: try await pullRequest(token: token, repo, number: number)!, body: "body", commits: 1, changedFiles: 2, additions: 5, deletions: 1)
    }
    func submitReview(token: String, _ repo: GitHubRepoRef, number: Int, event: GitHubReviewEvent, body: String) async throws -> GitHubReview { throw GitHubError.notFound }
}

private final class GitHubTokenBox: TokenStoring, @unchecked Sendable {
    var value: String?
    init(_ value: String?) { self.value = value }
    func load() -> String? { value }
    func save(_ token: String) -> Bool { value = token; return true }
    func delete() { value = nil }
}

@MainActor private func makeModel() -> IslandModel {
    IslandModel(settings: SettingsStore(store: FileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).json"), defaultValue: Settings())))
}

@Test @MainActor func teamsAPullRequestFromAMessageOpensItsReviewInTheGitHubTabEvenIfThatTabWasNeverOpened() async {
    let model = makeModel()
    model.selectedTab = .teams
    // GitHub has a saved token but its tab was never opened this time, so nothing has read the Keychain yet.
    let github = GitHubController(api: TeamsHub(), tokens: GitHubTokenBox("ghp_saved"), refreshInterval: 0)
    #expect(github.connection == .disconnected && github.reviewTarget == nil)

    await IslandServices.openPullRequestInGitHubTab("https://github.com/shipmnts/finance/pull/757", model: model, github: github)

    #expect(model.selectedTab == .github)
    #expect(github.reviewTarget?.number == 757 && github.reviewTarget?.repoFullName == "shipmnts/finance")
    #expect(github.searchRepo?.fullName == "shipmnts/finance")
    #expect(github.message == nil)
}

@Test @MainActor func teamsWithGitHubNotConnectedTheTabStillSwitchesSoTheConnectScreenShows() async {
    let model = makeModel()
    model.selectedTab = .teams
    let github = GitHubController(api: TeamsHub(), tokens: GitHubTokenBox(nil), refreshInterval: 0)
    await IslandServices.openPullRequestInGitHubTab("https://github.com/shipmnts/finance/pull/757", model: model, github: github)
    #expect(model.selectedTab == .github && github.isReady && github.connection == .disconnected && github.reviewTarget == nil)
}

@Test @MainActor func teamsTheTabIsInTheTabBarAfterGitHubAndEveryoneKeepsTheirOrder() {
    let model = makeModel()
    #expect(model.orderedTabs.contains(.teams) && model.orderedTabs.count == IslandTab.allCases.count)
    #expect(model.orderedTabs.firstIndex(of: .github)! + 1 == model.orderedTabs.firstIndex(of: .teams)!)
    #expect(IslandTab.teams.title == "Teams")
    // Someone who saved their own order before Teams existed still gets the new tab (at the end).
    model.settings.update { $0.tabOrder = ["github", "focus"] }
    #expect(model.orderedTabs.first == .github && model.orderedTabs.contains(.teams))
}

@Test @MainActor func teamsNothingIsPolledWhileTheTabIsNotOnScreen() async {
    // A sign-in that finishes while the island is closed must not start polling in the background.
    let r = rig(chats: [chat("a", "Squad")], chatInterval: 0.05)
    r.controller.clientID = goodID
    await r.controller.signIn()                                       // the tab was never shown (start() never ran)
    #expect(r.controller.connection == .connected)
    let afterSignIn = r.api.calls.filter { $0 == "chats" }.count
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(r.api.calls.filter { $0 == "chats" }.count == afterSignIn)

    await r.controller.start()                                        // the tab appears: now it refreshes on its own
    let started = r.api.calls.filter { $0 == "chats" }.count
    let polled = await teamsEventually { r.api.calls.filter { $0 == "chats" }.count > started }
    #expect(polled)
    r.controller.stop()
    try? await Task.sleep(nanoseconds: 150_000_000)                   // a refresh that had already started may still finish
    let stopped = r.api.calls.filter { $0 == "chats" }.count
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(r.api.calls.filter { $0 == "chats" }.count == stopped)    // and stops when it goes
}
