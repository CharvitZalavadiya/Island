import Foundation
import Testing
import IslandCore
@testable import IslandUI

// The real GitHub API class, against a network that is only a stub: how it finds the 20 most recently pushed branches (reading the
// activity list a page at a time, filling from the plain branch list when there are too few, and what it does when either fails),
// and how it searches branches by name. No test talks to GitHub.

private struct Reply {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
}

/// Answers the requests of the test's own session. Each test uses an owner name of its own (`t<uuid>`), which is how the answers of
/// tests running side by side are kept apart.
private final class StubGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [String: (URLRequest, Data) -> Reply] = [:]
    nonisolated(unsafe) static var seen: [String: [String]] = [:]
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let url = request.url!
        // The owner is in the path of a REST address, and in the variables of a GraphQL one.
        var owner = url.pathComponents.count > 2 ? url.pathComponents[2] : ""
        if url.path == "/graphql", let sent = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let variables = sent["variables"] as? [String: Any], let named = variables["owner"] as? String
        {
            owner = named
        }
        Self.lock.lock()
        let line = "\(request.httpMethod ?? "GET") \(url.path)" + (url.query.map { "?\($0)" } ?? "")
        Self.seen[owner, default: []].append(line)
        let handler = Self.handlers[owner]
        Self.lock.unlock()
        let reply = handler?(request, body) ?? Reply(status: 500)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct Rig {
    let owner = "t" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let api: URLSessionGitHubAPI

    init(_ handler: @escaping (URLRequest, Data) -> Reply) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubGitHub.self]
        api = URLSessionGitHubAPI(session: URLSession(configuration: configuration))
        StubGitHub.lock.lock()
        StubGitHub.handlers[owner] = handler
        StubGitHub.lock.unlock()
    }

    var repo: GitHubRepoRef { GitHubRepoRef(fullName: "\(owner)/app") }

    /// What was asked of GitHub, in order: "GET /repos/<owner>/app/activity?per_page=100&page=1".
    var requests: [String] {
        StubGitHub.lock.lock()
        defer { StubGitHub.lock.unlock() }
        return (StubGitHub.seen[owner] ?? []).map { $0.replacingOccurrences(of: "/repos/\(owner)/app", with: "") }
    }
}

private func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }

/// An activity entry: a push to `branch`, `hoursAgo` hours before a fixed moment (so a larger number is older).
private func activity(_ branch: String, hoursAgo: Int, type: String = "push") -> [String: Any] {
    let moment = Date(timeIntervalSince1970: 1_794_000_000 - Double(hoursAgo) * 3_600)
    return ["ref": "refs/heads/\(branch)", "timestamp": ISO8601DateFormatter().string(from: moment), "activity_type": type]
}

private func nextLink(_ page: Int) -> [String: String] {
    ["Link": "<https://api.github.com/repositories/1/activity?per_page=100&page=\(page)>; rel=\"next\""]
}

private func page(of request: URLRequest) -> Int {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
}

private func branchList(_ names: [String], protected: Set<String> = []) -> Data {
    json(names.map { ["name": $0, "protected": protected.contains($0)] as [String: Any] })
}

private func names(_ branches: [GitHubBranch]) -> [String] { branches.map(\.name) }

// MARK: The twenty most recent

@Test func theActivityIsReadPageByPageUntilTwentyBranchesAreFoundAndNoFurther() async throws {
    let rig = Rig { request, _ in
        guard request.url!.path.hasSuffix("/activity") else { return Reply(status: 500) }
        let current = page(of: request)
        let first = (current - 1) * 12 + 1
        let entries = (first..<first + 12).map { activity("branch-\($0)", hoursAgo: $0) }
        return Reply(headers: nextLink(current + 1), body: json(entries))
    }
    let branches = try await rig.api.recentBranches(token: "t", rig.repo, limit: 20)
    #expect(names(branches) == (1...20).map { "branch-\($0)" })                          // the newest twenty, newest first
    #expect(branches[0].lastPushed == Date(timeIntervalSince1970: 1_794_000_000 - 3_600))
    #expect(rig.requests == ["GET /activity?per_page=100&page=1", "GET /activity?per_page=100&page=2"])   // two pages were enough; no list read
}

@Test func aBranchDeletedAfterItsPushesIsNotOffered() async throws {
    let rig = Rig { request, _ in
        guard request.url!.path.hasSuffix("/activity") else { return Reply(status: 500) }
        return Reply(body: json([
            activity("kept", hoursAgo: 1), activity("merged-and-deleted", hoursAgo: 2, type: "branch_deletion"),
            activity("merged-and-deleted", hoursAgo: 3), activity("merged-and-deleted", hoursAgo: 4), activity("other", hoursAgo: 5),
        ]))
    }
    let branches = try await rig.api.recentBranches(token: "t", rig.repo, limit: 2)
    #expect(names(branches) == ["kept", "other"])
}

@Test func atMostThreePagesOfActivityAreReadWhateverIsFound() async throws {
    let rig = Rig { request, _ in
        if request.url!.path.hasSuffix("/activity") {
            let current = page(of: request)
            return Reply(headers: nextLink(current + 1), body: json([activity("only-\(current)", hoursAgo: current)]))
        }
        return Reply(body: branchList([]))
    }
    let branches = try await rig.api.recentBranches(token: "t", rig.repo, limit: 20)
    #expect(names(branches) == ["only-1", "only-2", "only-3"])
    #expect(rig.requests.filter { $0.contains("/activity") }.count == 3)
}

// MARK: Too few recent ones

@Test func aQuietRepositoryIsFilledFromTheFirstPageOfTheBranchListWithoutRepeatsAndProtectedMarked() async throws {
    let all = (1...30).map { "z-\(String(format: "%02d", $0))" } + ["main", "release"]
    let rig = Rig { request, _ in
        if request.url!.path.hasSuffix("/activity") {
            return Reply(body: json([activity("release", hoursAgo: 1), activity("z-05", hoursAgo: 2), activity("brand-new", hoursAgo: 3)]))
        }
        return Reply(body: branchList(all.sorted(), protected: ["main", "release"]))
    }
    let branches = try await rig.api.recentBranches(token: "t", rig.repo, limit: 20)
    #expect(branches.count == 20)
    #expect(names(branches).prefix(3) == ["release", "z-05", "brand-new"])                // the recent ones first, in their order
    #expect(Set(names(branches)).count == 20)                                              // none twice
    #expect(branches[0].isProtected && !branches[1].isProtected)                           // the list's "protected" flag is applied
    #expect(branches[0].lastPushed != nil && branches.last?.lastPushed == nil)             // the filling ones have no push time
    #expect(names(branches).dropFirst(3).first == "main")                                  // then alphabetical: "main" before "z-01"
    #expect(rig.requests.last == "GET /branches?per_page=100&page=1")
}

@Test func whenTheActivityCannotBeUsedTheBranchListAloneGivesTheFirstTwenty() async throws {
    for status in [403, 404, 422, 500] {
        let rig = Rig { request, _ in
            if request.url!.path.hasSuffix("/activity") { return Reply(status: status, body: json(["message": "nope"])) }
            return Reply(body: branchList((1...50).map { "b-\(String(format: "%02d", $0))" }))
        }
        let branches = try await rig.api.recentBranches(token: "t", rig.repo, limit: 20)
        #expect(names(branches) == (1...20).map { "b-\(String(format: "%02d", $0))" }, "activity answered \(status)")
    }
}

@Test func aBranchListThatFailsLosesNoneOfTheRecentBranchesButNothingAtAllIsAFailure() async throws {
    let some = Rig { request, _ in
        request.url!.path.hasSuffix("/activity") ? Reply(body: json([activity("a", hoursAgo: 1), activity("b", hoursAgo: 2)])) : Reply(status: 500)
    }
    #expect(names(try await some.api.recentBranches(token: "t", some.repo, limit: 20)) == ["a", "b"])

    let none = Rig { request, _ in request.url!.path.hasSuffix("/activity") ? Reply(body: json([])) : Reply(status: 500) }
    await #expect(throws: GitHubError.self) { try await none.api.recentBranches(token: "t", none.repo, limit: 20) }
}

// MARK: Trouble that is about the person

@Test func aTokenGitHubRefusesOrALimitReachedIsNotHiddenBehindTheFallback() async {
    let refused = Rig { _, _ in Reply(status: 401, body: json(["message": "Bad credentials"])) }
    await #expect(throws: GitHubError.unauthorized) { try await refused.api.recentBranches(token: "t", refused.repo, limit: 20) }
    #expect(refused.requests.count == 1)                                                  // it did not go on to the list

    let limited = Rig { _, _ in Reply(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1794003600"], body: json(["message": "API rate limit exceeded"])) }
    await #expect(throws: GitHubError.rateLimited(until: Date(timeIntervalSince1970: 1_794_003_600))) {
        try await limited.api.recentBranches(token: "t", limited.repo, limit: 20)
    }
}

@Test func anOrganisationThatNeedsSingleSignOnIsSaidNotSkipped() async {
    let rig = Rig { _, _ in Reply(status: 403, headers: ["x-github-sso": "required; url=https://github.com/orgs/acme/sso?authorization_request=ABC"], body: json(["message": "SAML"])) }
    do {
        _ = try await rig.api.recentBranches(token: "t", rig.repo, limit: 20)
        Issue.record("expected the single sign-on error")
    } catch let error as GitHubError {
        guard case .sso(let url) = error else { Issue.record("expected sso, got \(error)"); return }
        #expect(url?.absoluteString.contains("authorization_request=ABC") == true)
    } catch {
        Issue.record("unexpected error \(error)")
    }
}

// MARK: Searching by name

@Test func theBranchSearchSendsTheTextAsAVariableAndReadsTheNames() async throws {
    let rig = Rig { _, body in
        let sent = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let variables = sent["variables"] as? [String: Any] ?? [:]
        #expect(variables["query"] as? String == "login fix" && variables["first"] as? Int == 30)
        let nodes: [[String: Any]] = [["name": "fix/login-bug"], ["name": "hotfix/Login"]]
        return Reply(body: json(["data": ["repository": ["refs": ["nodes": nodes]]]]))
    }
    let found = try await rig.api.searchBranches(token: "tok", rig.repo, matching: "login fix")
    #expect(names(found) == ["fix/login-bug", "hotfix/Login"])
    #expect(rig.requests == ["POST /graphql"])
}

@Test func aBranchSearchThatGitHubRefusesOrCannotFindTheRepositoryForIsAnError() async {
    let refused = Rig { _, _ in Reply(status: 401, body: json(["message": "Bad credentials"])) }
    await #expect(throws: GitHubError.unauthorized) { try await refused.api.searchBranches(token: "t", refused.repo, matching: "x") }

    let missing = Rig { _, _ in
        Reply(body: json(["data": ["repository": NSNull()], "errors": [["type": "NOT_FOUND", "message": "Could not resolve to a Repository"]]]))
    }
    await #expect(throws: GitHubError.notFound) { try await missing.api.searchBranches(token: "t", missing.repo, matching: "x") }
}
