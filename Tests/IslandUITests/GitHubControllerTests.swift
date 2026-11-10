import Testing
import Foundation
import IslandCore
@testable import IslandUI

// MARK: Stand-ins

private final class FakeGitHub: GitHubAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var who = GitHubAccount(login: "octocat", name: "The Octocat")
    var repoList: [GitHubRepo] = [
        GitHubRepo(id: 1, fullName: "acme/app", owner: "acme", name: "app", defaultBranch: "main"),
        GitHubRepo(id: 2, fullName: "acme/old", owner: "acme", name: "old", isArchived: true),
        GitHubRepo(id: 3, fullName: "acme/readonly", owner: "acme", name: "readonly", canPush: false),
        GitHubRepo(id: 4, fullName: "octocat/blog", owner: "octocat", name: "blog", defaultBranch: "master"),
    ]
    var branchList: [GitHubBranch] = [GitHubBranch(name: "feature/login"), GitHubBranch(name: "main"), GitHubBranch(name: "bugfix"), GitHubBranch(name: "develop")]
    var template: String? = "## What\n\n## Why\n"
    var comparisons: [String: GitHubComparison] = [:]
    var defaultComparison = GitHubComparison(status: "ahead", aheadBy: 3, totalCommits: 3, filesChanged: 5, firstCommitMessage: "First commit")
    var existing: GitHubPullRequest?
    var mine: [GitHubPullRequest] = []
    var review: [GitHubPullRequest] = []
    /// Thrown by every call while set.
    var failure: Error?
    var createFailure: Error?
    var lookupFailure: Error?
    var templateFails = false
    /// What a search finds (by its exact query), else `searchDefault`.
    var searchAnswers: [String: [GitHubPullRequest]] = [:]
    var searchDefault: [GitHubPullRequest] = []
    var numbered: [Int: GitHubPullRequest] = [:]
    /// What opening a pull request for review shows (by its number).
    var details: [Int: GitHubPullRequestDetails] = [:]
    var detailsFailure: Error?
    /// Thrown when a review is sent.
    var reviewFailure: Error?
    /// Holds the details of one pull request back until released.
    var detailsGate: (number: Int, gate: SearchGate)?
    /// Holds every search until released, so a test can make an answer arrive late.
    var searchGate: SearchGate?
    /// Waits (once) in `compare` for the head named, so a test can make an answer arrive late.
    var compareGate: (head: String, wait: @Sendable () async -> Void)?

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return log }
    private func record(_ call: String) { lock.lock(); log.append(call); lock.unlock() }
    private func check() throws { if let failure { throw failure } }

    func account(token: String) async throws -> GitHubAccount { record("account:\(token)"); try check(); return who }
    func repos(token: String) async throws -> [GitHubRepo] { record("repos"); try check(); return repoList }
    func repo(token: String, _ ref: GitHubRepoRef) async throws -> GitHubRepo {
        record("repo:\(ref.fullName)"); try check()
        if let lookupFailure { throw lookupFailure }
        if let found = repoList.first(where: { $0.fullName.lowercased() == ref.fullName.lowercased() }) { return found }
        throw GitHubError.notFound
    }
    func branches(token: String, _ repo: GitHubRepoRef) async throws -> [GitHubBranch] { record("branches:\(repo.fullName)"); try check(); return branchList }
    func branch(token: String, _ repo: GitHubRepoRef, name: String) async throws -> GitHubBranch {
        record("branch:\(name)"); try check()
        guard name == "hidden/branch" else { throw GitHubError.notFound }
        return GitHubBranch(name: name)
    }
    func compare(token: String, _ repo: GitHubRepoRef, base: String, head: String) async throws -> GitHubComparison {
        record("compare:\(base)...\(head)"); try check()
        if let gate = compareGate, gate.head == head { await gate.wait() }
        return comparisons[head] ?? defaultComparison
    }
    func pullRequestTemplate(token: String, _ repo: GitHubRepoRef) async throws -> String? {
        record("template:\(repo.fullName)")
        if templateFails { throw GitHubError.server(500) }
        return template
    }
    func createPullRequest(token: String, _ repo: GitHubRepoRef, title: String, head: String, base: String, body: String, draft: Bool) async throws -> GitHubPullRequest {
        record("create:\(repo.fullName):\(head)->\(base):\(title):\(draft ? "draft" : "ready"):\(body.isEmpty ? "-" : "body")")
        try check()
        if let createFailure { throw createFailure }
        return GitHubPullRequest(number: 42, title: title, url: URL(string: "https://github.com/\(repo.fullName)/pull/42")!, isDraft: draft, repoFullName: repo.fullName, headBranch: head, baseBranch: base)
    }
    func openPullRequest(token: String, _ repo: GitHubRepoRef, head: String, base: String) async throws -> GitHubPullRequest? {
        record("existing:\(head)->\(base)"); try check(); return existing
    }
    func pullRequestLists(token: String) async throws -> GitHubPullRequestLists {
        record("lists"); try check()
        return GitHubPullRequestLists(mine: mine, review: review)
    }
    func searchPullRequests(token: String, query: String) async throws -> [GitHubPullRequest] {
        record("search:\(query)")
        try check()
        if let searchGate { await searchGate.wait() }
        return searchAnswers[query] ?? searchDefault
    }
    func pullRequest(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequest? {
        record("pr:\(repo.fullName)#\(number)")
        try check()
        return numbered[number]
    }
    func pullRequestDetails(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequestDetails {
        record("details:\(repo.fullName)#\(number)")
        try check()
        if let detailsGate, detailsGate.number == number { await detailsGate.gate.wait() }
        if let detailsFailure { throw detailsFailure }
        return details[number] ?? GitHubPullRequestDetails(pullRequest: numbered[number] ?? GitHubPullRequest(number: number, title: "t", url: URL(string: "https://github.com/\(repo.fullName)/pull/\(number)")!, repoFullName: repo.fullName))
    }
    func submitReview(token: String, _ repo: GitHubRepoRef, number: Int, event: GitHubReviewEvent, body: String) async throws -> GitHubReview {
        record("review:\(repo.fullName)#\(number):\(event.rawValue):\(body.isEmpty ? "-" : body)")
        try check()
        if let reviewFailure { throw reviewFailure }
        let verdict: GitHubReview.Verdict = switch event { case .approve: .approved; case .requestChanges: .changesRequested; case .comment: .commented }
        return GitHubReview(id: 900 + number, authorLogin: who.login, verdict: verdict, submittedAt: clock)
    }
}

private actor SearchGate {
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

private final class FakeTokens: TokenStoring {
    var stored: String?
    var saveWorks = true
    private(set) var loads = 0
    init(stored: String? = nil) { self.stored = stored }
    func load() -> String? { loads += 1; return stored }
    func save(_ token: String) -> Bool { if saveWorks { stored = token }; return saveWorks }
    func delete() { stored = nil }
}

private final class Clipboard: @unchecked Sendable {
    var copied: [String] = []
}

private let clock = Date(timeIntervalSince1970: 1_794_000_000)

@MainActor private func make(api: FakeGitHub = FakeGitHub(), tokens: FakeTokens = FakeTokens(), clipboard: Clipboard = Clipboard(), copiedSeconds: TimeInterval = 5)
    -> (GitHubController, FakeGitHub, FakeTokens, Clipboard)
{
    (GitHubController(api: api, tokens: tokens, now: { clock }, refreshInterval: 0, copiedSeconds: copiedSeconds, writeToClipboard: { clipboard.copied.append($0) }),
     api, tokens, clipboard)
}

@MainActor private func connected(_ api: FakeGitHub = FakeGitHub(), clipboard: Clipboard = Clipboard()) async -> (GitHubController, FakeGitHub, FakeTokens, Clipboard) {
    let made = make(api: api, tokens: FakeTokens(stored: "tok"), clipboard: clipboard)
    await made.0.start()
    return made
}

/// A controller with the "acme/app" repository chosen.
@MainActor private func withRepo(_ api: FakeGitHub = FakeGitHub()) async -> (GitHubController, FakeGitHub, FakeTokens, Clipboard) {
    let made = await connected(api)
    await made.0.selectRepo(made.0.repos[0])
    return made
}

private func pull(_ number: Int, _ title: String, repo: String = "acme/app") -> GitHubPullRequest {
    GitHubPullRequest(number: number, title: title, url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, repoFullName: repo)
}

// MARK: Connecting

@Test @MainActor func theSavedTokenIsNotReadUntilTheTabOpens() async {
    let (controller, api, tokens, _) = make(tokens: FakeTokens(stored: "tok"))
    #expect(tokens.loads == 0 && controller.connection == .disconnected && api.calls.isEmpty)
    await controller.start()
    #expect(tokens.loads == 1 && controller.connection == .connected && controller.isReady)
}

@Test @MainActor func gitHubNoSavedTokenMeansTheConnectScreenAndNoNetwork() async {
    let (controller, api, _, _) = make()
    await controller.start()
    #expect(controller.connection == .disconnected && controller.isReady && api.calls.isEmpty)
}

@Test @MainActor func aSavedTokenShowsWhoIsConnectedAndLoadsTheRepositories() async {
    let (controller, api, _, _) = await connected()
    #expect(controller.account?.login == "octocat" && controller.reposLoaded)
    #expect(api.calls.first == "account:tok" && api.calls.contains("repos"))
}

@Test @MainActor func pastingAGoodTokenKeepsItAndConnects() async {
    let (controller, _, tokens, _) = make()
    await controller.connect(token: "  ghp_good\n")
    #expect(controller.connection == .connected && tokens.stored == "ghp_good" && controller.account?.name == "The Octocat")
    #expect(controller.message == nil)
}

@Test @MainActor func gitHubRefusedTokenIsNotKeptAndSaysWhy() async {
    let api = FakeGitHub()
    api.failure = GitHubError.unauthorized
    let (controller, _, tokens, _) = make(api: api)
    await controller.connect(token: "wrong")
    #expect(controller.connection == .disconnected && tokens.stored == nil)
    #expect(controller.message?.isError == true && controller.message?.text.contains("didn't accept that token") == true)
}

@Test @MainActor func aTokenNeedingSingleSignOnOffersTheAuthorisePage() async {
    let api = FakeGitHub()
    let url = URL(string: "https://github.com/orgs/acme/sso?authorization_request=ABC")!
    api.failure = GitHubError.sso(url)
    let (controller, _, tokens, _) = make(api: api)
    await controller.connect(token: "t")
    #expect(controller.connection == .disconnected && tokens.stored == nil)
    #expect(controller.message?.action == .init(title: "Authorise in GitHub", url: url))
}

@Test @MainActor func gitHubConnectingWithoutInternetOrWhenTheTokenCannotBeSavedSaysSo() async {
    let offline = FakeGitHub()
    offline.failure = GitHubError.network("offline")
    let (first, _, _, _) = make(api: offline)
    await first.connect(token: "t")
    #expect(first.message?.text.contains("Couldn't reach GitHub") == true)

    let (second, _, secondTokens, _) = make(tokens: FakeTokens())
    secondTokens.saveWorks = false
    await second.connect(token: "t")
    #expect(second.connection == .disconnected && second.message?.text.contains("couldn't save") == true)

    let (third, thirdAPI, _, _) = make()
    await third.connect(token: "   ")
    #expect(third.connection == .disconnected && thirdAPI.calls.isEmpty && third.message == nil)
}

@Test @MainActor func disconnectingForgetsEverything() async {
    let (controller, _, tokens, _) = await withRepo()
    controller.disconnect()
    #expect(tokens.stored == nil && controller.connection == .disconnected)
    #expect(controller.repos.isEmpty && controller.repo == nil && controller.account == nil && controller.branches.isEmpty && !controller.reposLoaded)
}

@Test @MainActor func gitHubRevokedTokenIsForgottenAndTheConnectScreenReturns() async {
    let (controller, api, tokens, _) = await withRepo()
    api.failure = GitHubError.unauthorized
    await controller.selectHead("feature/login")
    #expect(controller.connection == .disconnected && tokens.stored == nil && controller.repo == nil)
    #expect(controller.message?.text.contains("no longer accepts") == true)
}

// MARK: Choosing

@Test @MainActor func onlyRepositoriesThatCanTakeAPullRequestAreOffered() async {
    let (controller, _, _, _) = await connected()
    #expect(controller.pickableRepos(matching: "").map(\.fullName) == ["acme/app", "octocat/blog"])   // not archived, not read-only
    #expect(controller.pickableRepos(matching: "BLOG").map(\.fullName) == ["octocat/blog"])
    #expect(controller.pickableRepos(matching: "acme/o").isEmpty)                                     // "acme/old" is archived
}

@Test @MainActor func choosingARepositoryOffersItsDefaultBranchAndFillsInTheTemplate() async {
    let (controller, api, _, _) = await withRepo()
    #expect(controller.repo?.fullName == "acme/app" && controller.base == "main" && controller.head == nil)
    #expect(controller.branches.count == 4 && !controller.branchesLoading)
    #expect(controller.body == "## What\n\n## Why\n")
    #expect(api.calls.contains("branches:acme/app") && api.calls.contains("template:acme/app"))
    #expect(!controller.canCreate)                                                                  // no branch to merge yet
}

@Test @MainActor func aTemplateThatCannotBeFetchedNeverBlocksTheRepository() async {
    let api = FakeGitHub()
    api.template = nil
    let (controller, _, _, _) = await withRepo(api)
    #expect(controller.repo != nil && controller.body.isEmpty && controller.branches.count == 4 && controller.message == nil)
}

@Test @MainActor func theBranchListPutsTheDefaultFirstAndLeavesTheBaseOutOfMergeFrom() async {
    let (controller, _, _, _) = await withRepo()
    #expect(controller.branches(matching: "", excludingBase: false).map(\.name) == ["main", "bugfix", "develop", "feature/login"])
    #expect(controller.branches(matching: "", excludingBase: true).map(\.name) == ["bugfix", "develop", "feature/login"])
    #expect(controller.branches(matching: "LOG", excludingBase: true).map(\.name) == ["feature/login"])
}

@Test @MainActor func aRepositoryTypedOrPastedAsALinkIsLookedUpAndChosen() async {
    let (controller, api, _, _) = await connected()
    await controller.selectRepo(typed: "https://github.com/octocat/blog/pull/12")
    #expect(controller.repo?.fullName == "octocat/blog" && controller.base == "master" && api.calls.contains("repo:octocat/blog"))
}

@Test @MainActor func aRepositoryThatCannotTakePullRequestsIsRefusedWithAReason() async {
    let (controller, _, _, _) = await connected()
    await controller.selectRepo(typed: "acme/readonly")
    #expect(controller.repo == nil && controller.message?.text.contains("don't have write access") == true)
    await controller.selectRepo(typed: "acme/old")
    #expect(controller.repo == nil && controller.message?.text.contains("archived") == true)
    await controller.selectRepo(typed: "acme/nothing-here")
    #expect(controller.message?.text == "GitHub can't find acme/nothing-here, or your token can't see it.")
    await controller.selectRepo(typed: "not a repo")
    #expect(controller.message?.text == "Type a repository as owner/name, or paste its link.")
}

@Test @MainActor func aBranchTypedInThatTheListMissedIsCheckedWithGitHub() async {
    let (controller, _, _, _) = await withRepo()
    await controller.useTypedBranch("hidden/branch", asHead: true)
    #expect(controller.head == "hidden/branch" && controller.branches.contains(GitHubBranch(name: "hidden/branch")))
    await controller.useTypedBranch("no-such-branch", asHead: true)
    #expect(controller.head == "hidden/branch" && controller.message?.text == "There's no branch called “no-such-branch” in acme/app.")
}

// MARK: Comparing and the title

@Test @MainActor func pickingABranchShowsWhatThePullRequestCarriesAndFillsInATitle() async {
    let (controller, api, _, _) = await withRepo()
    await controller.selectHead("feature/login")
    #expect(api.calls.contains("compare:main...feature/login"))
    #expect(controller.comparison == .ready(GitHubComparison(status: "ahead", aheadBy: 3, totalCommits: 3, filesChanged: 5, firstCommitMessage: "First commit")))
    #expect(controller.title == "Login")                          // several commits: the branch name, made readable
    #expect(controller.canCreate)
}

@Test @MainActor func aSingleCommitGivesItsFirstLineAsTheTitle() async {
    let api = FakeGitHub()
    api.comparisons["bugfix"] = GitHubComparison(status: "ahead", aheadBy: 1, totalCommits: 1, filesChanged: 1, firstCommitMessage: "Fix the crash on start\n\nLonger text")
    let (controller, _, _, _) = await withRepo(api)
    await controller.selectHead("bugfix")
    #expect(controller.title == "Fix the crash on start")
}

@Test @MainActor func aTitleThePersonTypedIsNeverReplaced() async {
    let (controller, _, _, _) = await withRepo()
    await controller.selectHead("feature/login")
    controller.setTitle("My own title")
    await controller.selectHead("develop")
    #expect(controller.title == "My own title")
    controller.setTitle("")                                       // emptied: automatic again
    await controller.selectHead("bugfix")
    #expect(controller.title == "Bugfix")
}

@Test @MainActor func twoIdenticalOrEmptyBranchesCannotBeOpened() async {
    let api = FakeGitHub()
    api.comparisons["develop"] = GitHubComparison(status: "identical", aheadBy: 0, totalCommits: 0)
    let (controller, _, _, _) = await withRepo(api)
    await controller.selectHead("develop")
    #expect(controller.comparison == .ready(GitHubComparison(status: "identical", aheadBy: 0, totalCommits: 0)))
    controller.setTitle("Something")
    #expect(!controller.canCreate)                                // nothing new on the branch
    await controller.selectBase("develop")                        // the same branch on both sides
    #expect(controller.comparison == .failed("Pick two different branches.") && !controller.canCreate)
}

@Test @MainActor func aLateAnswerAboutAnEarlierBranchIsIgnored() async {
    let api = FakeGitHub()
    let release = Gate()
    api.compareGate = (head: "feature/login", wait: { await release.wait() })
    api.comparisons["feature/login"] = GitHubComparison(status: "ahead", aheadBy: 9, totalCommits: 9, filesChanged: 9)
    api.comparisons["bugfix"] = GitHubComparison(status: "ahead", aheadBy: 2, totalCommits: 2, filesChanged: 2)
    let (controller, _, _, _) = await withRepo(api)
    let slow = Task { await controller.selectHead("feature/login") }     // its answer is held up
    try? await Task.sleep(nanoseconds: 100_000_000)
    await controller.selectHead("bugfix")                                 // the person moves on; this one answers at once
    await release.open()
    await slow.value
    #expect(controller.head == "bugfix")
    #expect(controller.comparison == .ready(GitHubComparison(status: "ahead", aheadBy: 2, totalCommits: 2, filesChanged: 2)))
    #expect(controller.title == "Bugfix")
}

// MARK: Creating

@Test @MainActor func creatingSendsExactlyWhatWasChosenAndGivesTheLink() async {
    let api = FakeGitHub()
    api.mine = [pull(42, "Add login")]
    let (controller, _, _, _) = await withRepo(api)
    await controller.selectHead("feature/login")
    controller.setTitle("Add login")
    controller.isDraft = true
    await controller.createPullRequest()
    #expect(api.calls.contains("create:acme/app:feature/login->main:Add login:draft:body"))
    guard case .created(let created) = controller.creation else { Issue.record("not created"); return }
    #expect(created.number == 42 && created.url.absoluteString == "https://github.com/acme/app/pull/42")
    #expect(controller.myPullRequests.map(\.number) == [42])                       // it now shows under My PRs
}

@Test @MainActor func aPullRequestThatAlreadyExistsLeadsToItsLinkNotADeadEnd() async {
    let api = FakeGitHub()
    api.createFailure = GitHubError.validation("A pull request already exists for acme:feature/login.")
    api.existing = pull(7, "Already open")
    let (controller, _, _, _) = await withRepo(api)
    await controller.selectHead("feature/login")
    await controller.createPullRequest()
    #expect(controller.creation == .idle && controller.existingPullRequest?.number == 7)
    #expect(controller.message?.isError == false && controller.message?.text.contains("#7") == true)
}

@Test @MainActor func aRefusalKeepsTheFormAndSaysWhatGitHubSaid() async {
    let api = FakeGitHub()
    api.createFailure = GitHubError.validation("No commits between main and feature/login")
    let (controller, _, _, _) = await withRepo(api)
    await controller.selectHead("feature/login")
    controller.setTitle("Add login")
    await controller.createPullRequest()
    #expect(controller.creation == .idle && controller.title == "Add login" && controller.head == "feature/login")
    #expect(controller.message == .init(text: "No commits between main and feature/login", isError: true, action: nil))

    api.createFailure = GitHubError.network("offline")
    await controller.createPullRequest()
    #expect(controller.message?.text == "Couldn't reach GitHub, so Island couldn't create the pull request." && controller.title == "Add login")

    api.createFailure = GitHubError.forbidden("Resource not accessible by personal access token")
    await controller.createPullRequest()
    #expect(controller.message?.text.contains("“repo” permission") == true)
}

@Test @MainActor func startingAnotherKeepsTheRepositoryAndClearsTheRest() async {
    let (controller, _, _, _) = await withRepo()
    await controller.selectHead("feature/login")
    controller.isDraft = true
    await controller.createPullRequest()
    controller.startAnother()
    #expect(controller.creation == .idle && controller.repo?.fullName == "acme/app" && controller.base == "main")
    #expect(controller.head == nil && controller.title.isEmpty && controller.body.isEmpty && !controller.isDraft && controller.comparison == .none)
}

@Test @MainActor func creatingNeedsATitleAndTwoDifferentBranches() async {
    let (controller, api, _, _) = await withRepo()
    await controller.selectHead("feature/login")
    controller.setTitle("   ")
    #expect(!controller.canCreate)
    await controller.createPullRequest()
    #expect(!api.calls.contains { $0.hasPrefix("create:") })
}

// MARK: Lists and messages

@Test @MainActor func theListsLoadWhenTheirSectionOpens() async {
    let api = FakeGitHub()
    api.mine = [pull(1, "Mine")]
    api.review = [pull(2, "Please review", repo: "acme/other")]
    let (controller, _, _, _) = await connected(api)
    controller.section = .mine
    await controller.loadForCurrentSection()
    #expect(controller.myPullRequests.map(\.number) == [1] && controller.reviewRequests.map(\.number) == [2] && controller.listsLoaded)
}

@Test @MainActor func aFailedListLoadKeepsWhatWasThereAndSaysSo() async {
    let api = FakeGitHub()
    api.mine = [pull(1, "Mine")]
    let (controller, _, _, _) = await connected(api)
    await controller.refreshLists()
    api.failure = GitHubError.network("offline")
    await controller.refreshLists()
    #expect(controller.myPullRequests.count == 1 && controller.message?.text == "Couldn't reach GitHub.")
    api.failure = nil
    await controller.refreshLists()
    #expect(controller.message == nil)
}

@Test @MainActor func theRateLimitPausesLoadingAndSaysWhenItComesBack() async {
    let api = FakeGitHub()
    let (controller, _, _, _) = await connected(api)
    api.failure = GitHubError.rateLimited(until: clock.addingTimeInterval(600))
    await controller.refreshLists()
    #expect(controller.message?.text.contains("request limit was reached") == true && controller.message?.text.contains("resets at") == true)
    let before = api.calls.count
    api.failure = nil
    await controller.refreshLists()
    #expect(api.calls.count == before)                                              // still inside the pause
}

// MARK: Copying

@Test @MainActor func copyingTheLinkPutsExactlyTheLinkOnTheClipboardAndSaysSoBriefly() async {
    let clipboard = Clipboard()
    let made = make(tokens: FakeTokens(stored: "tok"), clipboard: clipboard, copiedSeconds: 0.15)
    let controller = made.0
    let pr = pull(42, "Add login")
    controller.copyLink(of: pr)
    #expect(clipboard.copied == ["https://github.com/acme/app/pull/42"] && controller.copiedID == pr.id)
    // The "Copied" fades again (waited for, not slept for: a busy machine can delay the timer).
    var faded = false
    for _ in 0..<300 where !faded {
        try? await Task.sleep(nanoseconds: 10_000_000)
        faded = controller.copiedID == nil
    }
    #expect(faded)
    controller.copyMarkdown(of: pr)
    #expect(clipboard.copied.last == "[acme/app#42 Add login](https://github.com/acme/app/pull/42)")
}

private actor Gate {
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


// MARK: The status of the lists

@Test @MainActor func theListsKeepTheStatusTheyCameWith() async {
    let api = FakeGitHub()
    var failing = pull(1, "Broken build")
    failing.checks = .failing
    failing.review = .changesRequested
    failing.hasConflicts = true
    api.mine = [failing]
    let (controller, _, _, _) = await connected(api)
    await controller.refreshLists()
    #expect(controller.myPullRequests[0].checks == .failing && controller.myPullRequests[0].review == .changesRequested)
    #expect(controller.myPullRequests[0].hasConflicts)
}

@Test @MainActor func copyingTheTitleAndLinkPutsBothOnTheClipboard() async {
    let clipboard = Clipboard()
    let made = make(tokens: FakeTokens(stored: "tok"), clipboard: clipboard)
    made.0.copyTitleAndLink(of: pull(5, "Add login"))
    #expect(clipboard.copied == ["Add login\nhttps://github.com/acme/app/pull/5"])
}


// MARK: Searching a repository's pull requests

@Test @MainActor func theSearchRepositoryCanBeAnyRepositoryYouCanSeeNotOnlyOnesYouCanPushTo() async {
    let (controller, _, _, _) = await connected()
    #expect(controller.searchableRepos(matching: "").map(\.fullName) == ["acme/app", "acme/old", "acme/readonly", "octocat/blog"])
    #expect(controller.searchableRepos(matching: "READ").map(\.fullName) == ["acme/readonly"])
    #expect(controller.pickableRepos(matching: "").count == 2)                              // a new pull request is stricter
}

@Test @MainActor func searchingStartsInTheRepositoryTheNewPullRequestIsFor() async {
    let (controller, _, _, _) = await withRepo()
    controller.section = .search
    await controller.loadForCurrentSection()
    #expect(controller.searchRepo?.fullName == "acme/app")
    // From here the two are independent: choosing another repository to search leaves the new pull request alone.
    controller.selectSearchRepo(controller.repos[3])
    #expect(controller.searchRepo?.fullName == "octocat/blog" && controller.repo?.fullName == "acme/app")
}

@Test @MainActor func aSearchAsksGitHubForExactlyTheWordedQuery() async {
    let api = FakeGitHub()
    let wanted = "repo:acme/app is:pr is:open login sort:updated-desc"
    api.searchAnswers[wanted] = [pull(5, "Add login")]
    let (controller, _, _, _) = await withRepo(api)
    controller.selectSearchRepo(controller.repos[0])
    await controller.search("login")
    #expect(api.calls.contains("search:\(wanted)") && controller.searchResults.map(\.number) == [5] && controller.searchLoaded)

    controller.searchOpenOnly = false                                                    // include closed and merged
    await controller.search("@ravi")
    #expect(api.calls.contains("search:repo:acme/app is:pr author:ravi sort:updated-desc"))
}

@Test @MainActor func aNumberOrALinkFindsThatOnePullRequest() async {
    let api = FakeGitHub()
    api.numbered[482] = pull(482, "Friend's change")
    let (controller, _, _, _) = await withRepo(api)
    controller.selectSearchRepo(controller.repos[0])
    await controller.search("#482")
    #expect(api.calls.contains("pr:acme/app#482") && controller.searchResults.map(\.number) == [482])
    await controller.search("https://github.com/acme/app/pull/482")
    #expect(controller.searchResults.map(\.number) == [482])
    await controller.search("999")                                                       // there is no such number here
    #expect(controller.searchResults.isEmpty && controller.searchLoaded && controller.message == nil)
}

@Test @MainActor func aLateSearchAnswerIsIgnoredWhenTheRepositoryChangedMeanwhile() async {
    let api = FakeGitHub()
    api.searchDefault = [pull(1, "From the first repository")]
    let release = SearchGate()
    api.searchGate = release
    let (controller, _, _, _) = await withRepo(api)
    controller.selectSearchRepo(controller.repos[0])
    let slow = Task { await controller.search("") }
    try? await Task.sleep(nanoseconds: 100_000_000)
    controller.selectSearchRepo(controller.repos[3])                                     // the person moved on
    await release.open()
    await slow.value
    #expect(controller.searchRepo?.fullName == "octocat/blog" && controller.searchResults.isEmpty)
}

@Test @MainActor func aTypedRepositoryCanBeSearchedEvenWithoutWriteAccess() async {
    let (controller, _, _, _) = await connected()
    await controller.selectSearchRepo(typed: "https://github.com/acme/readonly")
    #expect(controller.searchRepo?.fullName == "acme/readonly" && controller.message == nil)   // read-only is fine for looking
    await controller.selectSearchRepo(typed: "acme/nothing-here")
    #expect(controller.message?.text == "GitHub can't find acme/nothing-here, or your token can't see it.")
    await controller.selectSearchRepo(typed: "not a repo")
    #expect(controller.message?.text == "Type a repository as owner/name, or paste its link.")
}

@Test @MainActor func aFailedSearchSaysSoAndKeepsTheResults() async {
    let api = FakeGitHub()
    api.searchDefault = [pull(1, "Found")]
    let (controller, _, _, _) = await withRepo(api)
    controller.selectSearchRepo(controller.repos[0])
    await controller.search("")
    api.failure = GitHubError.network("offline")
    await controller.search("anything")
    #expect(controller.searchResults.count == 1 && controller.message?.text == "Couldn't reach GitHub, so Island couldn't search.")
    #expect(!controller.isSearching)
}

@Test @MainActor func clearingTheSearchRepositoryEmptiesTheSearch() async {
    let api = FakeGitHub()
    api.searchDefault = [pull(1, "Found")]
    let (controller, _, _, _) = await withRepo(api)
    controller.selectSearchRepo(controller.repos[0])
    await controller.search("")
    controller.clearSearchRepo()
    #expect(controller.searchRepo == nil && controller.searchResults.isEmpty && !controller.searchLoaded)
}

@Test @MainActor func disconnectingForgetsTheSearchToo() async {
    let api = FakeGitHub()
    api.searchDefault = [pull(1, "Found")]
    let (controller, _, _, _) = await withRepo(api)
    controller.selectSearchRepo(controller.repos[0])
    await controller.search("")
    controller.disconnect()
    #expect(controller.searchRepo == nil && controller.searchResults.isEmpty)
}

// MARK: Starting over

@Test @MainActor func startingOverGoesBackToTheBeginning() async {
    let (controller, _, _, _) = await withRepo()
    await controller.selectHead("feature/login")
    controller.setTitle("My own title")
    controller.isDraft = true
    controller.resetForm()
    #expect(controller.repo == nil && controller.base == nil && controller.head == nil && controller.branches.isEmpty)
    #expect(controller.title.isEmpty && controller.body.isEmpty && !controller.isDraft && controller.comparison == .none)
    #expect(controller.creation == .idle && controller.message == nil && !controller.canCreate)
    // And the repositories are still there to choose from again.
    #expect(controller.pickableRepos(matching: "").count == 2)
    await controller.selectRepo(controller.repos[3])
    #expect(controller.repo?.fullName == "octocat/blog" && controller.base == "master")
}


// MARK: Reviewing a pull request

private func theirs(_ number: Int = 1204, author: String = "ravi-k", state: GitHubPullRequest.State = .open) -> GitHubPullRequest {
    GitHubPullRequest(number: number, title: "Invoice rounding", url: URL(string: "https://github.com/acme/app/pull/\(number)")!, state: state, repoFullName: "acme/app", authorLogin: author, headBranch: "feat/x", baseBranch: "main")
}

@Test @MainActor func openingAPullRequestLoadsItsDetailsAndTheReviewsOnIt() async {
    let api = FakeGitHub()
    var details = GitHubPullRequestDetails(pullRequest: theirs(), body: "Rounds totals.", commits: 3, changedFiles: 5, additions: 40, deletions: 8)
    details.reviews = [GitHubReview(id: 1, authorLogin: "priya", verdict: .approved, submittedAt: clock), GitHubReview(id: 2, authorLogin: "octocat", verdict: .changesRequested, submittedAt: clock)]
    api.details[1204] = details
    let (controller, _, _, _) = await connected(api)
    await controller.openReview(theirs())
    #expect(api.calls.contains("details:acme/app#1204"))
    #expect(controller.reviewTarget?.number == 1204 && controller.reviewDetails?.commits == 3 && !controller.isLoadingReview)
    #expect(controller.myStanding?.verdict == .changesRequested)               // the account is "octocat"
    #expect(controller.reviewDetails?.approvers == ["priya"])
    #expect(controller.canSubmit(.approve) && !controller.canSubmit(.requestChanges))   // changes need a comment first
}

@Test @MainActor func approvingNeedsTwoPressesAndSendsExactlyOnce() async {
    let api = FakeGitHub()
    api.mine = [pull(1, "Mine")]
    let (controller, _, _, _) = await connected(api)
    await controller.openReview(theirs())
    await controller.pressReviewButton(.approve)
    #expect(controller.confirming == .approve && !api.calls.contains { $0.hasPrefix("review:") })   // the first press only asks
    await controller.pressReviewButton(.approve)
    #expect(api.calls.filter { $0.hasPrefix("review:") } == ["review:acme/app#1204:APPROVE:-"])
    #expect(controller.reviewSubmission == .done(.approve) && controller.confirming == nil)
    #expect(controller.myStanding?.verdict == .approved)                            // shown at once
    #expect(api.calls.filter { $0 == "lists" }.count >= 2)                          // the lists were refreshed afterwards
}

@Test @MainActor func theSecondPressMustComeSoonOrTheQuestionLapses() async {
    let api = FakeGitHub()
    let made = make(api: api, tokens: FakeTokens(stored: "tok"))
    let controller = made.0
    await controller.start()
    // (a short window for the test)
    let quick = GitHubController(api: api, tokens: FakeTokens(stored: "tok"), now: { clock }, refreshInterval: 0, confirmationSeconds: 0.15, writeToClipboard: { _ in })
    await quick.start()
    await quick.openReview(theirs())
    await quick.pressReviewButton(.approve)
    #expect(quick.confirming == .approve)
    var lapsed = false
    for _ in 0..<300 where !lapsed { try? await Task.sleep(nanoseconds: 10_000_000); lapsed = quick.confirming == nil }
    #expect(lapsed)
    await quick.pressReviewButton(.approve)                                         // a late press starts the question again
    #expect(quick.confirming == .approve && !api.calls.contains { $0.hasPrefix("review:") })
}

@Test @MainActor func pressingADifferentActionMovesTheQuestionInsteadOfSending() async {
    let api = FakeGitHub()
    let (controller, _, _, _) = await connected(api)
    await controller.openReview(theirs())
    controller.reviewComment = "Please add a test."
    await controller.pressReviewButton(.approve)
    await controller.pressReviewButton(.requestChanges)                              // not the same action: asks about this one now
    #expect(controller.confirming == .requestChanges && !api.calls.contains { $0.hasPrefix("review:") })
    await controller.pressReviewButton(.requestChanges)
    #expect(api.calls.contains("review:acme/app#1204:REQUEST_CHANGES:Please add a test."))
    #expect(controller.reviewComment.isEmpty && controller.reviewSubmission == .done(.requestChanges))
}

@Test @MainActor func requestingChangesOrCommentingNeedsSomethingWritten() async {
    let api = FakeGitHub()
    let (controller, _, _, _) = await connected(api)
    await controller.openReview(theirs())
    controller.reviewComment = "   \n "
    #expect(!controller.canSubmit(.requestChanges) && !controller.canSubmit(.comment) && controller.canSubmit(.approve))
    await controller.pressReviewButton(.requestChanges)
    await controller.pressReviewButton(.comment)
    #expect(controller.confirming == nil && !api.calls.contains { $0.hasPrefix("review:") })
    controller.reviewComment = "Looks odd to me."
    await controller.pressReviewButton(.comment)                                     // a comment is sent at once, no second press
    #expect(api.calls.contains("review:acme/app#1204:COMMENT:Looks odd to me."))
}

@Test @MainActor func yourOwnPullRequestCanBeCommentedOnButNotApproved() async {
    let api = FakeGitHub()
    api.details[1204] = GitHubPullRequestDetails(pullRequest: theirs(author: "OCTOCAT"))     // as GitHub would answer
    let (controller, _, _, _) = await connected(api)
    await controller.openReview(theirs(author: "OCTOCAT"))                           // the account is octocat (any capitals)
    #expect(controller.isOwnPullRequest && controller.reviewBlockReason?.contains("your own pull request") == true)
    controller.reviewComment = "Note to self"
    #expect(!controller.canSubmit(.approve) && !controller.canSubmit(.requestChanges) && controller.canSubmit(.comment))
    await controller.pressReviewButton(.approve)
    #expect(controller.confirming == nil && !api.calls.contains { $0.hasPrefix("review:") })
}

@Test @MainActor func aClosedOrMergedPullRequestCannotBeApproved() async {
    let api = FakeGitHub()
    let (controller, _, _, _) = await connected(api)
    for (state, reason) in [(GitHubPullRequest.State.merged, "already merged"), (.closed, "is closed")] {
        api.details[1204] = GitHubPullRequestDetails(pullRequest: theirs(state: state))      // as GitHub would answer
        await controller.openReview(theirs(state: state))
        #expect(controller.reviewBlockReason?.contains(reason) == true && !controller.canSubmit(.approve))
    }
    api.details[1204] = GitHubPullRequestDetails(pullRequest: theirs(state: .open))
    await controller.openReview(theirs(state: .open))
    #expect(controller.reviewBlockReason == nil && controller.canSubmit(.approve))
}

@Test @MainActor func aRefusedReviewKeepsWhatWasWrittenAndSaysWhy() async {
    let api = FakeGitHub()
    api.reviewFailure = GitHubError.validation("Review can't be submitted on a pull request that has been closed")
    let (controller, _, _, _) = await connected(api)
    await controller.openReview(theirs())
    controller.reviewComment = "Please add a test."
    await controller.pressReviewButton(.requestChanges)
    await controller.pressReviewButton(.requestChanges)
    #expect(controller.reviewSubmission == .idle && controller.reviewComment == "Please add a test." && controller.confirming == nil)
    #expect(controller.message == .init(text: "Review can't be submitted on a pull request that has been closed", isError: true, action: nil))

    api.reviewFailure = GitHubError.network("offline")
    await controller.pressReviewButton(.comment)
    #expect(controller.message?.text == "Couldn't reach GitHub, so Island couldn't send the review." && controller.reviewComment == "Please add a test.")
}

@Test @MainActor func aLateAnswerForAPullRequestYouLeftIsIgnored() async {
    let api = FakeGitHub()
    let release = SearchGate()
    api.detailsGate = (number: 1204, gate: release)
    api.details[1204] = GitHubPullRequestDetails(pullRequest: theirs(1204), commits: 99)
    api.details[77] = GitHubPullRequestDetails(pullRequest: theirs(77), commits: 2)
    let (controller, _, _, _) = await connected(api)
    let slow = Task { await controller.openReview(theirs(1204)) }
    try? await Task.sleep(nanoseconds: 100_000_000)
    await controller.openReview(theirs(77))                                          // the person opened another one meanwhile
    await release.open()
    await slow.value
    #expect(controller.reviewTarget?.number == 77 && controller.reviewDetails?.commits == 2 && !controller.isLoadingReview)
}

@Test @MainActor func closingThePanelAndDisconnectingForgetEverything() async {
    let api = FakeGitHub()
    let (controller, _, tokens, _) = await connected(api)
    await controller.openReview(theirs())
    controller.reviewComment = "draft thoughts"
    await controller.pressReviewButton(.approve)
    controller.closeReview()
    #expect(controller.reviewTarget == nil && controller.reviewDetails == nil && controller.reviewComment.isEmpty && controller.confirming == nil)

    await controller.openReview(theirs())
    controller.disconnect()
    #expect(controller.reviewTarget == nil && tokens.stored == nil)
}

@Test @MainActor func aRevokedTokenWhileSendingBringsTheConnectScreenBack() async {
    let api = FakeGitHub()
    let (controller, _, tokens, _) = await connected(api)
    await controller.openReview(theirs())
    api.reviewFailure = GitHubError.unauthorized
    await controller.pressReviewButton(.approve)
    await controller.pressReviewButton(.approve)
    #expect(controller.connection == .disconnected && tokens.stored == nil && controller.reviewTarget == nil)
}


// MARK: Pasting a pull request link

@Test @MainActor func pastingALinkChoosesItsRepositoryAndOpensTheReviewPanel() async {
    let api = FakeGitHub()
    api.numbered[482] = GitHubPullRequest(number: 482, title: "Friend's change", url: URL(string: "https://github.com/octocat/blog/pull/482")!, repoFullName: "octocat/blog", authorLogin: "ravi-k")
    api.details[482] = GitHubPullRequestDetails(pullRequest: api.numbered[482]!, commits: 2)
    let (controller, _, _, _) = await connected(api)
    #expect(controller.searchRepo == nil)                                                   // nothing chosen yet
    let opened = await controller.openPullRequest(link: "https://github.com/octocat/blog/pull/482/files")
    #expect(opened)
    #expect(controller.searchRepo?.fullName == "octocat/blog")                              // the repository was chosen for searching
    #expect(controller.reviewTarget?.number == 482 && controller.reviewDetails?.commits == 2)   // and the review panel is open
    #expect(api.calls.contains("repo:octocat/blog") && api.calls.contains("pr:octocat/blog#482") && api.calls.contains("details:octocat/blog#482"))
    #expect(controller.message == nil)
}

@Test @MainActor func aLinkToTheRepositoryAlreadyChosenSkipsTheLookup() async {
    let api = FakeGitHub()
    api.numbered[7] = GitHubPullRequest(number: 7, title: "Seven", url: URL(string: "https://github.com/acme/app/pull/7")!, repoFullName: "acme/app")
    let (controller, _, _, _) = await connected(api)
    controller.selectSearchRepo(controller.repos[0])                                        // acme/app
    #expect(await controller.openPullRequest(link: "ACME/App#7"))                           // the short form, any capitals
    #expect(!api.calls.contains("repo:ACME/App") && !api.calls.contains("repo:acme/app"))   // no second look-up of the repository
    #expect(controller.reviewTarget?.number == 7)
}

@Test @MainActor func aLinkToAPullRequestThatDoesNotExistSaysSoAndOpensNothing() async {
    let api = FakeGitHub()
    let (controller, _, _, _) = await connected(api)
    #expect(!(await controller.openPullRequest(link: "https://github.com/octocat/blog/pull/9999")))
    #expect(controller.reviewTarget == nil && controller.message?.text == "There's no pull request #9999 in octocat/blog.")
    #expect(controller.searchRepo?.fullName == "octocat/blog")                              // the repository was still chosen
}

@Test @MainActor func aLinkToARepositoryYouCannotSeeIsExplained() async {
    let (controller, _, _, _) = await connected()
    #expect(!(await controller.openPullRequest(link: "https://github.com/secret/place/pull/1")))
    #expect(controller.message?.text == "GitHub can't find secret/place, or your token can't see it." && controller.reviewTarget == nil)
}

@Test @MainActor func somethingThatIsNotAPullRequestLinkDoesNothing() async {
    let api = FakeGitHub()
    let (controller, _, _, _) = await connected(api)
    let before = api.calls.count
    #expect(!(await controller.openPullRequest(link: "login form")))
    #expect(!(await controller.openPullRequest(link: "https://github.com/acme/app")))
    #expect(api.calls.count == before && controller.message == nil)
}

@Test @MainActor func aLinkAlsoWorksTypedIntoTheSearchRepositoryPicker() async {
    let api = FakeGitHub()
    api.numbered[3] = GitHubPullRequest(number: 3, title: "Three", url: URL(string: "https://github.com/acme/readonly/pull/3")!, repoFullName: "acme/readonly")
    let (controller, _, _, _) = await connected(api)
    await controller.selectSearchRepo(typed: "https://github.com/acme/readonly/pull/3")
    #expect(controller.searchRepo?.fullName == "acme/readonly" && controller.reviewTarget?.number == 3)   // read-only is fine for reviewing
}

@Test @MainActor func aRevokedTokenWhileOpeningALinkBringsTheConnectScreenBack() async {
    let api = FakeGitHub()
    let (controller, _, tokens, _) = await connected(api)
    api.failure = GitHubError.unauthorized
    #expect(!(await controller.openPullRequest(link: "acme/app#7")))
    #expect(controller.connection == .disconnected && tokens.stored == nil)
}
