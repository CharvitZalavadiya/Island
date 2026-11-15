import Foundation
import Testing
@testable import IslandCore

// Finding a branch: the lists open with the 20 pushed to most recently (read from the repository's activity list), and every
// other branch is found by searching GitHub for part of its name.

private let formatter = ISO8601DateFormatter()
private func date(_ text: String) -> Date { formatter.date(from: text)! }

private func json(_ entries: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: entries) }

private func entry(_ ref: String, _ type: String, _ timestamp: String) -> [String: Any] {
    ["ref": ref, "timestamp": timestamp, "activity_type": type]
}

private func push(_ branch: String, _ day: Int) -> GitHubBranchActivity {
    GitHubBranchActivity(branch: branch, kind: .pushed, date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400))
}

private func deletion(_ branch: String, _ day: Int) -> GitHubBranchActivity {
    GitHubBranchActivity(branch: branch, kind: .deleted, date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400))
}

// MARK: Reading the activity list

@Test func theActivityListGivesPushesAndDeletionsOfBranchesAndNothingElse() throws {
    // The first four are real entries of cli/cli's activity list (newest first); the rest are the other kinds of entry.
    let entries = try GitHubDecoding.branchActivity(from: json([
        entry("refs/heads/bagtoad/direct-triage-labels", "push", "2026-11-10T14:31:57Z"),
        entry("refs/heads/copilot/fix-gh-auth-status-errors", "push", "2026-11-10T10:13:05Z"),
        entry("refs/heads/copilot/fix-gh-auth-status-errors", "push", "2026-11-10T09:48:13Z"),
        entry("refs/heads/bagtoad/triage-ghmock-skill", "push", "2026-11-07T01:41:59Z"),
        entry("refs/heads/forced", "force_push", "2026-11-09T00:00:00Z"),
        entry("refs/heads/brand-new", "branch_creation", "2026-11-11T00:00:00Z"),
        entry("refs/heads/develop", "pr_merge", "2026-11-11T01:00:00Z"),
        entry("refs/heads/queue", "merge_queue_merge", "2026-11-11T02:00:00Z"),
        entry("refs/heads/gone", "branch_deletion", "2026-11-12T00:00:00Z"),
        entry("refs/tags/v1", "push", "2026-11-12T02:00:00Z"),
        entry("refs/heads/no-date", "push", ""),
        entry("refs/heads/odd-kind", "something_new", "2026-11-12T03:00:00Z"),
    ]))
    #expect(entries.map(\.branch) == [
        "bagtoad/direct-triage-labels", "copilot/fix-gh-auth-status-errors", "copilot/fix-gh-auth-status-errors",
        "bagtoad/triage-ghmock-skill", "forced", "brand-new", "develop", "queue", "gone",
    ])
    #expect(entries.last == GitHubBranchActivity(branch: "gone", kind: .deleted, date: date("2026-11-12T00:00:00Z")))
    #expect(entries.dropLast().allSatisfy { $0.kind == .pushed })
    #expect(entries[0].date == date("2026-11-10T14:31:57Z"))
}

@Test func anUnreadableActivityListIsAnErrorAndAnEmptyOneIsNothing() throws {
    #expect(throws: GitHubError.self) { try GitHubDecoding.branchActivity(from: Data("{}".utf8)) }
    #expect(throws: GitHubError.self) { try GitHubDecoding.branchActivity(from: Data("nope".utf8)) }
    #expect(try GitHubDecoding.branchActivity(from: json([])).isEmpty)
}

// MARK: Picking the most recent branches

@Test func theNewestPushOfEachBranchCountsOnceAndTheOrderIsNewestFirst() {
    var recent = GitHubRecentBranches(limit: 20)
    recent.add([push("a", 10), push("b", 9), push("a", 8), push("c", 7), push("b", 6)])
    #expect(recent.branches.map(\.name) == ["a", "b", "c"])
    #expect(recent.branches.map(\.lastPushed) == [push("a", 10).date, push("b", 9).date, push("c", 7).date])   // each branch's newest push
}

@Test func aBranchWhoseNewestEntryIsItsDeletionIsGoneHoweverMuchWasPushedBefore() {
    var recent = GitHubRecentBranches(limit: 20)
    recent.add([push("kept", 10), deletion("merged-and-deleted", 9), push("merged-and-deleted", 8), push("merged-and-deleted", 7), push("other", 6)])
    #expect(recent.branches.map(\.name) == ["kept", "other"])
}

@Test func aBranchPushedToAgainAfterItWasDeletedIsThereAgain() {
    var recent = GitHubRecentBranches(limit: 20)
    recent.add([push("reborn", 10), deletion("reborn", 9), push("reborn", 8)])                  // newest first: pushed, after being deleted
    #expect(recent.branches.map(\.name) == ["reborn"])
    #expect(recent.branches.first?.lastPushed == push("reborn", 10).date)
}

@Test func theCollectorStopsAtTheLimitAndSaysSoSoNoMorePagesAreRead() {
    var recent = GitHubRecentBranches(limit: 3)
    #expect(!recent.isFull)
    recent.add([push("a", 10), push("b", 9)])
    #expect(!recent.isFull)
    recent.add([push("c", 8), push("d", 7), push("e", 6)])
    #expect(recent.isFull && recent.branches.map(\.name) == ["a", "b", "c"])
    recent.add([push("f", 5)])                                                                   // a later page changes nothing
    #expect(recent.branches.map(\.name) == ["a", "b", "c"])
}

@Test func theCollectorWorksAcrossPagesAndKeepsDeletionsInMind() {
    var recent = GitHubRecentBranches(limit: 3)
    recent.add([push("a", 10), deletion("x", 9)])                                                // page 1
    recent.add([push("x", 8), push("b", 7), push("a", 6), push("c", 5), push("d", 4)])           // page 2: x was deleted later than this push
    #expect(recent.branches.map(\.name) == ["a", "b", "c"])
}

@Test func noEntriesMeansNoBranchesAndALimitOfZeroTakesNone() {
    var recent = GitHubRecentBranches(limit: 20)
    recent.add([])
    #expect(recent.branches.isEmpty && !recent.isFull)
    var none = GitHubRecentBranches(limit: 0)
    none.add([push("a", 1)])
    #expect(none.branches.isEmpty && none.isFull)
}

// MARK: Searching by name

@Test func theBranchSearchIsAskedForExactlyAndTheTokenStaysInTheHeader() throws {
    let request = GitHubRequests.searchBranches(token: "tok", GitHubRepoRef(fullName: "acme/app"), matching: "login fix")
    #expect(request.url?.absoluteString == "https://api.github.com/graphql" && request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    let body = try #require(request.httpBody)
    #expect(!String(decoding: body, as: UTF8.self).contains("tok"))
    let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let variables = try #require(sent["variables"] as? [String: Any])
    #expect(variables["owner"] as? String == "acme" && variables["name"] as? String == "app")
    #expect(variables["query"] as? String == "login fix" && variables["first"] as? Int == 30)         // text goes as a variable, never into the query
    let query = try #require(sent["query"] as? String)
    #expect(query.contains("refPrefix: \"refs/heads/\"") && query.contains("query: $query") && query.contains("ALPHABETICAL"))
    #expect(!query.contains("login fix"))
}

@Test func theActivityListIsAskedForAPageAtATime() {
    let repo = GitHubRepoRef(fullName: "acme/app")
    #expect(GitHubRequests.branchActivity(token: "tok", repo).url?.absoluteString == "https://api.github.com/repos/acme/app/activity?per_page=100&page=1")
    #expect(GitHubRequests.branchActivity(token: "tok", repo, page: 3).url?.absoluteString == "https://api.github.com/repos/acme/app/activity?per_page=100&page=3")
}

private func graphQLAnswer(names: [String?]) -> Data {
    let nodes: [Any] = names.map { name in name.map { ["name": $0] as [String: Any] } ?? NSNull() }
    return try! JSONSerialization.data(withJSONObject: ["data": ["repository": ["refs": ["nodes": nodes]]]])
}

@Test func theSearchAnswerBecomesBranchesInTheOrderGitHubGaveThem() throws {
    // The names are what GitHub answered for "triage" on cli/cli.
    let found = try GitHubDecoding.branches(fromGraphQLSearch: graphQLAnswer(names: ["bagtoad/triage-ghmock-skill", "wm/mq-triage-test", "wm/triage-8352", "wm/7978-triage"]))
    #expect(found.map(\.name) == ["bagtoad/triage-ghmock-skill", "wm/mq-triage-test", "wm/triage-8352", "wm/7978-triage"])
    #expect(found.allSatisfy { $0.lastPushed == nil && !$0.isProtected })
    #expect(try GitHubDecoding.branches(fromGraphQLSearch: graphQLAnswer(names: [])).isEmpty)       // nothing matched: an answer, not an error
    #expect(try GitHubDecoding.branches(fromGraphQLSearch: graphQLAnswer(names: ["a", nil, "b"])).map(\.name) == ["a", "b"])
}

@Test func aSearchOfARepositoryThatCannotBeSeenIsNotFoundAndOtherTroubleIsNamed() {
    func answer(_ errors: [[String: String]]) -> Data { try! JSONSerialization.data(withJSONObject: ["data": ["repository": NSNull()], "errors": errors]) }
    #expect(throws: GitHubError.notFound) { try GitHubDecoding.branches(fromGraphQLSearch: answer([["type": "NOT_FOUND", "message": "Could not resolve"]])) }
    #expect(throws: GitHubError.forbidden("blocked")) { try GitHubDecoding.branches(fromGraphQLSearch: answer([["type": "FORBIDDEN", "message": "blocked"]])) }
    #expect(throws: GitHubError.rateLimited(until: nil)) { try GitHubDecoding.branches(fromGraphQLSearch: answer([["type": "RATE_LIMITED", "message": "slow down"]])) }
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.branches(fromGraphQLSearch: answer([])) }
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.branches(fromGraphQLSearch: Data("nope".utf8)) }
}
