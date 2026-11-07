import Testing
import Foundation
@testable import IslandCore

// Trimmed copies of real answers from api.github.com (the octocat/Hello-World repository).
private let realRepo = #"{"id": 1296269, "name": "Hello-World", "full_name": "octocat/Hello-World", "private": false, "description": "My first repository on GitHub!", "archived": false, "disabled": false, "default_branch": "master", "pushed_at": "2024-08-20T23:54:42Z", "has_pull_requests": true, "owner": {"login": "octocat"}, "permissions": {"admin": false, "maintain": false, "push": true, "triage": true, "pull": true}}"#
private let realBranches = #"[{"name":"master","commit":{"sha":"7fd1a60b01f91b314f59955a4e4d4e80d8edf11d","url":"https://api.github.com/repos/octocat/Hello-World/commits/7fd1a60b01f91b314f59955a4e4d4e80d8edf11d"},"protected":false},{"name":"octocat-patch-1","commit":{"sha":"b1b3f9723831141a31a1a7252a213e216ea76e56","url":"x"},"protected":true}]"#
private let realCompare = #"{"status": "ahead", "ahead_by": 1, "behind_by": 0, "total_commits": 1, "commits": [{"sha": "b1b3f9723831141a31a1a7252a213e216ea76e56", "commit": {"message": "sentence case"}}], "files": [{"filename": "README"}]}"#
private let realPull = #"{"number": 11703, "title": "probe fork pr", "state": "closed", "draft": false, "html_url": "https://github.com/octocat/Hello-World/pull/11703", "merged_at": null, "updated_at": "2026-11-06T20:00:23Z", "user": {"login": "escaleraalcielo"}, "head": {"ref": "probe"}, "base": {"ref": "master", "repo": {"full_name": "octocat/Hello-World"}}}"#
private let realSearch = #"{"total_count": 1364, "incomplete_results": false, "items": [{"number": 11702, "title": "Add sync test message to README", "state": "open", "draft": false, "html_url": "https://github.com/octocat/Hello-World/pull/11702", "updated_at": "2026-11-06T15:01:26Z", "repository_url": "https://api.github.com/repos/octocat/Hello-World", "user": {"login": "bobbyacharya"}, "pull_request": {"html_url": "https://github.com/octocat/Hello-World/pull/11702", "merged_at": null}}, {"number": 5, "title": "An issue, not a pull request", "state": "open", "html_url": "https://github.com/octocat/Hello-World/issues/5", "updated_at": "2026-11-06T15:01:26Z", "repository_url": "https://api.github.com/repos/octocat/Hello-World", "user": {"login": "x"}}]}"#

private func data(_ text: String) -> Data { Data(text.utf8) }

// MARK: Reading

@Test func aRepositoryIsReadWithItsPermissions() throws {
    let repo = try GitHubDecoding.repo(from: data(realRepo))
    #expect(repo.fullName == "octocat/Hello-World" && repo.owner == "octocat" && repo.name == "Hello-World")
    #expect(repo.defaultBranch == "master" && !repo.isPrivate && !repo.isArchived)
    #expect(repo.canPush == true && repo.canTakePullRequests)
    #expect(repo.pushedAt == ISO8601DateFormatter().date(from: "2024-08-20T23:54:42Z"))
    #expect(repo.webURL?.absoluteString == "https://github.com/octocat/Hello-World")
}

@Test func repositoriesThatCannotTakeAPullRequestAreRecognised() throws {
    func repo(_ extra: String) throws -> GitHubRepo {
        try GitHubDecoding.repos(from: data("[{\"id\": 1, \"name\": \"r\", \"full_name\": \"o/r\", \"owner\": {\"login\": \"o\"}\(extra)}]"))[0]
    }
    #expect(try repo(#", "permissions": {"push": true}"#).canTakePullRequests)
    #expect(try repo(#", "permissions": {"admin": true}"#).canTakePullRequests)
    #expect(try repo(#", "permissions": {"pull": true, "push": false}"#).canTakePullRequests == false)   // read-only
    #expect(try repo(#", "archived": true, "permissions": {"push": true}"#).canTakePullRequests == false)
    #expect(try repo(#", "disabled": true, "permissions": {"push": true}"#).canTakePullRequests == false)
    #expect(try repo(#", "has_pull_requests": false, "permissions": {"push": true}"#).canTakePullRequests == false)
    #expect(try repo("").canPush == nil && repo("").canTakePullRequests)                                 // GitHub did not say: allowed
}

@Test func branchesAreRead() throws {
    let branches = try GitHubDecoding.branches(from: data(realBranches))
    #expect(branches == [GitHubBranch(name: "master"), GitHubBranch(name: "octocat-patch-1", isProtected: true)])
    #expect(try GitHubDecoding.branch(from: data(#"{"name": "feature/x", "protected": false}"#)).name == "feature/x")
}

@Test func aComparisonSaysWhatThePullRequestWouldCarry() throws {
    let comparison = try GitHubDecoding.comparison(from: data(realCompare))
    #expect(comparison == GitHubComparison(status: "ahead", aheadBy: 1, behindBy: 0, totalCommits: 1, filesChanged: 1, firstCommitMessage: "sentence case", commitTitles: ["sentence case"]))
    #expect(comparison.hasChanges)
    let same = try GitHubDecoding.comparison(from: data(#"{"status": "identical", "ahead_by": 0, "behind_by": 0, "total_commits": 0, "commits": [], "files": []}"#))
    #expect(!same.hasChanges && same.firstCommitMessage == nil)
}

@Test func aPullRequestIsReadFromTheCreateAnswerAndFromSearch() throws {
    let pull = try GitHubDecoding.pullRequest(from: data(realPull))
    #expect(pull.number == 11703 && pull.title == "probe fork pr" && pull.state == .closed && !pull.isDraft)
    #expect(pull.repoFullName == "octocat/Hello-World" && pull.headBranch == "probe" && pull.baseBranch == "master")
    #expect(pull.url.absoluteString == "https://github.com/octocat/Hello-World/pull/11703" && pull.authorLogin == "escaleraalcielo")
    #expect(pull.id == "octocat/Hello-World#11703")
    #expect(pull.markdownLink == "[octocat/Hello-World#11703 probe fork pr](https://github.com/octocat/Hello-World/pull/11703)")

    // Search results carry the repository as a link, and the pull requests among them are told apart from issues.
    let found = try GitHubDecoding.searchedPullRequests(from: data(realSearch))
    #expect(found.count == 1 && found[0].number == 11702 && found[0].repoFullName == "octocat/Hello-World" && found[0].state == .open)
}

@Test func mergedAndDraftPullRequestsAreTold() throws {
    let merged = try GitHubDecoding.pullRequest(from: data(#"{"number": 1, "title": "t", "state": "closed", "html_url": "https://github.com/o/r/pull/1", "merged_at": "2026-01-01T00:00:00Z", "base": {"ref": "main", "repo": {"full_name": "o/r"}}}"#))
    #expect(merged.state == .merged)
    let draft = try GitHubDecoding.pullRequest(from: data(#"{"number": 2, "title": "t", "state": "open", "draft": true, "html_url": "https://github.com/o/r/pull/2", "base": {"ref": "main", "repo": {"full_name": "o/r"}}}"#))
    #expect(draft.isDraft && draft.state == .open)
}

@Test func theAccountIsRead() throws {
    #expect(try GitHubDecoding.account(from: data(#"{"login": "octocat", "name": "The Octocat", "id": 1}"#)) == GitHubAccount(login: "octocat", name: "The Octocat"))
    #expect(try GitHubDecoding.account(from: data(#"{"login": "octocat", "name": null}"#)).name == nil)
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.account(from: data(#"{"message": "Bad credentials"}"#)) }
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.repos(from: data("<html>Bad gateway</html>")) }
}

@Test func theNextPageComesFromTheLinkHeader() {
    // The header GitHub really sent for the branches of octocat/Hello-World.
    let header = #"<https://api.github.com/repositories/1296269/branches?per_page=2&page=2>; rel="next", <https://api.github.com/repositories/1296269/branches?per_page=2&page=5>; rel="last""#
    #expect(GitHubDecoding.nextPage(fromLinkHeader: header) == 2)
    #expect(GitHubDecoding.nextPage(fromLinkHeader: #"<https://api.github.com/x?page=1>; rel="prev", <https://api.github.com/x?page=3>; rel="next""#) == 3)
    #expect(GitHubDecoding.nextPage(fromLinkHeader: #"<https://api.github.com/x?page=1>; rel="prev""#) == nil)   // the last page
    #expect(GitHubDecoding.nextPage(fromLinkHeader: nil) == nil)
}

// MARK: Errors

@Test func errorAnswersAreMappedToSomethingActionable() {
    let body = data(#"{"message": "Validation Failed", "errors": [{"resource": "PullRequest", "code": "custom", "message": "A pull request already exists for octocat:feature."}]}"#)
    #expect(GitHubError.from(status: 401, body: data(#"{"message": "Bad credentials"}"#), headers: [:]) == .unauthorized)
    #expect(GitHubError.from(status: 404, body: nil, headers: [:]) == .notFound)
    #expect(GitHubError.from(status: 422, body: body, headers: [:]) == .validation("A pull request already exists for octocat:feature."))
    #expect(GitHubError.from(status: 422, body: data(#"{"message": "Validation Failed", "errors": [{"resource": "PullRequest", "field": "head", "code": "invalid"}]}"#), headers: [:]) == .validation("head is invalid"))
    #expect(GitHubError.from(status: 422, body: nil, headers: [:]) == .validation("GitHub refused the request."))
    #expect(GitHubError.from(status: 502, body: nil, headers: [:]) == .server(502))
    #expect(GitHubError.from(status: 403, body: data(#"{"message": "Resource not accessible by personal access token"}"#), headers: [:])
        == .forbidden("Resource not accessible by personal access token"))
}

@Test func singleSignOnAndRateLimitsAreToldApart() {
    let sso = GitHubError.from(status: 403, body: nil, headers: ["x-github-sso": "required; url=https://github.com/orgs/acme/sso?authorization_request=ABC"])
    #expect(sso == .sso(URL(string: "https://github.com/orgs/acme/sso?authorization_request=ABC")))
    let limited = GitHubError.from(status: 403, body: data(#"{"message": "API rate limit exceeded for user"}"#), headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1794051524"])
    #expect(limited == .rateLimited(until: Date(timeIntervalSince1970: 1_794_051_524)))
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(GitHubError.from(status: 429, body: nil, headers: ["retry-after": "60"], now: now) == .rateLimited(until: now.addingTimeInterval(60)))
    #expect(GitHubError.from(status: 403, body: data(#"{"message": "You have exceeded a secondary rate limit."}"#), headers: [:]) == .rateLimited(until: nil))
}

// MARK: Requests

@Test func githubReadRequestsAreExactAndKeepTheTokenOutOfTheAddress() {
    let request = GitHubRequests.account(token: "ghp_secret")
    #expect(request.url?.absoluteString == "https://api.github.com/user")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_secret")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "Island")        // GitHub refuses requests without one
    #expect(request.url?.absoluteString.contains("ghp_secret") == false)

    #expect(GitHubRequests.repos(token: "t", page: 2).url?.absoluteString
        == "https://api.github.com/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member&page=2")
    let repo = GitHubRepoRef(owner: "octocat", name: "Hello-World")
    #expect(GitHubRequests.repo(token: "t", repo).url?.path == "/repos/octocat/Hello-World")
    #expect(GitHubRequests.branches(token: "t", repo, page: 3).url?.absoluteString == "https://api.github.com/repos/octocat/Hello-World/branches?per_page=100&page=3")
}

@Test func branchNamesWithSlashesAndOddCharactersSurviveInAddresses() {
    let repo = GitHubRepoRef(owner: "o", name: "r")
    // Both forms work on GitHub (checked against the real API); slashes stay, anything unsafe is escaped.
    #expect(GitHubRequests.compare(token: "t", repo, base: "main", head: "feature/login").url?.absoluteString
        == "https://api.github.com/repos/o/r/compare/main...feature/login")
    #expect(GitHubRequests.branch(token: "t", repo, name: "fix/a#1?b+c%d").url?.absoluteString
        == "https://api.github.com/repos/o/r/branches/fix/a%231%3Fb%2Bc%25d")
    let template = GitHubRequests.pullRequestTemplate(token: "t", repo, path: ".github/pull_request_template.md")
    #expect(template.url?.path == "/repos/o/r/contents/.github/pull_request_template.md")
    #expect(template.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
}

@Test func creatingAPullRequestSendsExactlyWhatWasChosen() throws {
    let request = GitHubRequests.createPullRequest(
        token: "t", GitHubRepoRef(owner: "acme", name: "app"), title: "Add login", head: "feature/login", base: "main",
        body: "Closes #4\nSecond line", draft: true)
    #expect(request.httpMethod == "POST" && request.url?.absoluteString == "https://api.github.com/repos/acme/app/pulls")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let sent = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    #expect(sent["title"] as? String == "Add login" && sent["head"] as? String == "feature/login" && sent["base"] as? String == "main")
    #expect(sent["body"] as? String == "Closes #4\nSecond line" && sent["draft"] as? Bool == true)
    #expect(sent.count == 5)

    let existing = GitHubRequests.openPullRequests(token: "t", GitHubRepoRef(owner: "acme", name: "app"), head: "feature/login", base: "main")
    let items = URLComponents(url: existing.url!, resolvingAgainstBaseURL: false)?.queryItems
    #expect(items?.first { $0.name == "head" }?.value == "acme:feature/login" && items?.first { $0.name == "state" }?.value == "open")
}

@Test func searchesForMyPullRequestsAreExact() {
    let mine = GitHubRequests.searchPullRequests(token: "t", query: GitHubRequests.myOpenPullRequestsQuery)
    let items = URLComponents(url: mine.url!, resolvingAgainstBaseURL: false)?.queryItems
    #expect(mine.url?.path == "/search/issues")
    #expect(items?.first { $0.name == "q" }?.value == "is:pr is:open author:@me archived:false")
    #expect(items?.first { $0.name == "sort" }?.value == "updated" && items?.first { $0.name == "per_page" }?.value == "50")
    #expect(GitHubRequests.reviewRequestedQuery == "is:pr is:open review-requested:@me archived:false")
    #expect(GitHubRequests.newTokenURL.absoluteString == "https://github.com/settings/tokens/new?description=Island&scopes=repo")
}

// MARK: Wording

@Test func aRepositoryCanBeTypedPastedOrLinked() {
    let expected = GitHubRepoRef(owner: "octocat", name: "Hello-World")
    for text in [
        "octocat/Hello-World", "  octocat/Hello-World  ", "https://github.com/octocat/Hello-World", "github.com/octocat/Hello-World",
        "https://github.com/octocat/Hello-World/pull/11703", "https://github.com/octocat/Hello-World.git", "http://www.github.com/octocat/Hello-World/",
    ] {
        #expect(GitHubRepoRef.parse(text) == expected, "\(text)")
    }
    for text in ["", "octocat", "octocat/", "/Hello-World", "octo cat/Hello", "https://example.com/octocat/Hello-World", "gitlab.com/octocat/Hello-World"] {
        #expect(GitHubRepoRef.parse(text) == nil, "\(text)")
    }
}

@Test func aBranchNameBecomesAReadableTitle() {
    #expect(GitHubText.title(fromBranch: "feature/add-login_page") == "Add login page")
    #expect(GitHubText.title(fromBranch: "charvit/fix-crash-on-start") == "Fix crash on start")
    #expect(GitHubText.title(fromBranch: "hotfix") == "Hotfix")
    #expect(GitHubText.title(fromBranch: "JIRA-123-dark-mode") == "JIRA 123 dark mode")
    #expect(GitHubText.title(fromBranch: "feature/") == "Feature")
    #expect(GitHubText.firstLine(of: "Fix the thing\n\nLonger explanation") == "Fix the thing")
    #expect(GitHubText.firstLine(of: "") == "")
}

// MARK: Status on the lists (GraphQL)

// Hand-written to the shape of GitHub's published schema (the query is validated against it; these are its answers).
private let graphQLAnswer = """
{"data": {
  "mine": {"nodes": [
    {"number": 482, "title": "Add login page", "url": "https://github.com/shipmnts/app/pull/482", "isDraft": false,
     "updatedAt": "2026-11-07T10:00:00Z", "mergeable": "MERGEABLE", "reviewDecision": "APPROVED",
     "headRefName": "feature/login", "baseRefName": "main", "repository": {"nameWithOwner": "shipmnts/app"},
     "author": {"login": "jane"}, "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]}},
    null,
    {"number": 91, "title": "Fix rounding", "url": "https://github.com/shipmnts/api/pull/91", "isDraft": true,
     "updatedAt": "2026-11-05T09:00:00Z", "mergeable": "CONFLICTING", "reviewDecision": null,
     "headRefName": "fix/round", "baseRefName": "master", "repository": {"nameWithOwner": "shipmnts/api"},
     "author": null, "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]}},
    {"number": 7, "title": "No checks yet", "url": "https://github.com/o/r/pull/7", "isDraft": false, "updatedAt": null,
     "mergeable": "UNKNOWN", "reviewDecision": "REVIEW_REQUIRED", "headRefName": "x", "baseRefName": "main",
     "repository": {"nameWithOwner": "o/r"}, "author": {"login": "jane"}, "commits": {"nodes": [{"commit": {"statusCheckRollup": null}}]}}
  ]},
  "review": {"nodes": [
    {"number": 77, "title": "Bump deps", "url": "https://github.com/shipmnts/app/pull/77", "isDraft": false,
     "updatedAt": "2026-11-07T08:00:00Z", "mergeable": "MERGEABLE", "reviewDecision": "CHANGES_REQUESTED",
     "headRefName": "deps", "baseRefName": "main", "repository": {"nameWithOwner": "shipmnts/app"}, "author": {"login": "bot"},
     "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "PENDING"}}}]}}
  ]}
}}
"""

@Test func theListsCarryReviewChecksAndConflictStatus() throws {
    let lists = try GitHubDecoding.pullRequestLists(fromGraphQL: data(graphQLAnswer))
    #expect(lists.mine.map(\.number) == [482, 91, 7])                     // the null entry (one the account cannot see) is skipped
    #expect(lists.review.map(\.number) == [77])

    let approved = lists.mine[0]
    #expect(approved.checks == .passing && approved.review == .approved && !approved.hasConflicts && !approved.isDraft)
    #expect(approved.headBranch == "feature/login" && approved.baseBranch == "main" && approved.repoFullName == "shipmnts/app")
    #expect(approved.updatedAt == ISO8601DateFormatter().date(from: "2026-11-07T10:00:00Z") && approved.authorLogin == "jane")

    let broken = lists.mine[1]
    #expect(broken.checks == .failing && broken.review == nil && broken.hasConflicts && broken.isDraft && broken.authorLogin == nil)

    let waiting = lists.mine[2]
    #expect(waiting.checks == nil && waiting.review == .required && !waiting.hasConflicts && waiting.updatedAt == nil)

    let toReview = lists.review[0]
    #expect(toReview.checks == .pending && toReview.review == .changesRequested)
}

@Test func everyCheckStateIsMapped() throws {
    func checks(_ state: String) throws -> GitHubCheckState? {
        let json = #"{"data": {"mine": {"nodes": [{"number": 1, "title": "t", "url": "https://github.com/o/r/pull/1", "repository": {"nameWithOwner": "o/r"}, "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "\#(state)"}}}]}}]}}}"#
        return try GitHubDecoding.pullRequestLists(fromGraphQL: data(json)).mine[0].checks
    }
    #expect(try checks("SUCCESS") == .passing)
    #expect(try checks("FAILURE") == .failing && checks("ERROR") == .failing)
    #expect(try checks("PENDING") == .pending && checks("EXPECTED") == .pending)
    #expect(try checks("SOMETHING_NEW") == nil)                             // a state GitHub adds later is just "no status"
}

@Test func aGraphQLAnswerWithoutDataIsExplained() {
    #expect(throws: GitHubError.forbidden("Resource protected by organization SAML enforcement.")) {
        try GitHubDecoding.pullRequestLists(fromGraphQL: data(#"{"data": null, "errors": [{"type": "FORBIDDEN", "message": "Resource protected by organization SAML enforcement."}]}"#))
    }
    #expect(throws: GitHubError.rateLimited(until: nil)) {
        try GitHubDecoding.pullRequestLists(fromGraphQL: data(#"{"errors": [{"type": "RATE_LIMITED", "message": "API rate limit exceeded"}]}"#))
    }
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.pullRequestLists(fromGraphQL: data("<html>Bad gateway</html>")) }
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.pullRequestLists(fromGraphQL: data(#"{"errors": [{"type": "WEIRD"}]}"#)) }
    // Part of the answer missing because of an error elsewhere in it still gives what did come back.
    let partial = #"{"data": {"mine": {"nodes": [{"number": 1, "title": "t", "url": "https://github.com/o/r/pull/1", "repository": {"nameWithOwner": "o/r"}}]}, "review": null}, "errors": [{"type": "FORBIDDEN", "message": "x"}]}"#
    #expect((try? GitHubDecoding.pullRequestLists(fromGraphQL: data(partial)))?.mine.count == 1)
}

@Test func theGraphQLRequestIsExact() throws {
    let request = GitHubRequests.pullRequestLists(token: "ghp_secret")
    #expect(request.httpMethod == "POST" && request.url?.absoluteString == "https://api.github.com/graphql")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_secret")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let sent = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    #expect((sent["query"] as? String)?.contains("statusCheckRollup") == true && (sent["query"] as? String)?.contains("reviewDecision") == true)
    let variables = try #require(sent["variables"] as? [String: String])
    #expect(variables["mine"] == "is:pr is:open author:@me archived:false sort:updated-desc")
    #expect(variables["review"] == "is:pr is:open review-requested:@me archived:false sort:updated-desc")
    #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("ghp_secret") == false)
}

// MARK: Recent pushes

// Trimmed copies of real events from api.github.com (a public account), plus the delete event shape GitHub really sends.
private let realEvents = """
[
 {"type": "PushEvent", "repo": {"name": "sindresorhus/type-fest"}, "payload": {"ref": "refs/heads/main", "head": "2e1d2cd0", "before": "aaaa"}, "created_at": "2026-11-06T07:57:00Z"},
 {"type": "PushEvent", "repo": {"name": "acme/app"}, "payload": {"ref": "refs/heads/feature/login", "head": "1"}, "created_at": "2026-11-06T07:00:00Z"},
 {"type": "DeleteEvent", "repo": {"name": "acme/app"}, "payload": {"ref": "old-branch", "ref_type": "branch", "full_ref": "refs/heads/old-branch", "pusher_type": "user"}, "created_at": "2026-11-05T12:00:00Z"},
 {"type": "PushEvent", "repo": {"name": "acme/app"}, "payload": {"ref": "refs/heads/old-branch", "head": "2"}, "created_at": "2026-11-05T09:00:00Z"},
 {"type": "PushEvent", "repo": {"name": "acme/app"}, "payload": {"ref": "refs/heads/feature/login", "head": "3"}, "created_at": "2026-11-04T09:00:00Z"},
 {"type": "PushEvent", "repo": {"name": "acme/app"}, "payload": {"ref": "refs/tags/v1.0", "head": "4"}, "created_at": "2026-11-03T09:00:00Z"},
 {"type": "IssuesEvent", "repo": {"name": "acme/app"}, "payload": {"action": "opened"}, "created_at": "2026-11-03T08:00:00Z"},
 {"type": "PushEvent", "repo": {"name": "acme/app"}, "payload": {"ref": "refs/heads/revived"}, "created_at": "2026-11-02T09:00:00Z"},
 {"type": "DeleteEvent", "repo": {"name": "acme/app"}, "payload": {"ref": "revived", "ref_type": "branch"}, "created_at": "2026-11-01T09:00:00Z"}
]
"""

@Test func recentPushesAreTheBranchesPushedMostRecentlyOnePerBranch() throws {
    let pushes = try GitHubDecoding.recentPushes(from: data(realEvents))
    // old-branch was deleted after its push, so it is gone; the older push to feature/login is a duplicate; the tag and the
    // issue event are not branches; "revived" was deleted BEFORE it was pushed again, so it counts.
    #expect(pushes.map(\.id) == ["sindresorhus/type-fest@main", "acme/app@feature/login", "acme/app@revived"])
    #expect(pushes[1].pushedAt == ISO8601DateFormatter().date(from: "2026-11-06T07:00:00Z"))
    #expect(pushes[1].repoFullName == "acme/app" && pushes[1].branch == "feature/login")     // a slash in the branch survives
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.recentPushes(from: data(#"{"message": "Not Found"}"#)) }
    #expect(try GitHubDecoding.recentPushes(from: data("[]")).isEmpty)
}

@Test func theEventsRequestIsExact() {
    let request = GitHubRequests.userEvents(token: "t", login: "jane-dev")
    #expect(request.url?.absoluteString == "https://api.github.com/users/jane-dev/events?per_page=100")
}

// MARK: The comparison's commits

@Test func aComparisonListsItsCommitsFirstLines() throws {
    let comparison = try GitHubDecoding.comparison(from: data("""
    {"status": "ahead", "ahead_by": 3, "behind_by": 12, "total_commits": 3, "files": [{}, {}],
     "commits": [{"commit": {"message": "Add the form\\n\\nWith a longer explanation"}}, {"commit": {"message": "Fix typo"}}, {"commit": {"message": ""}}]}
    """))
    #expect(comparison.commitTitles == ["Add the form", "Fix typo"])         // first lines only, empty ones skipped
    #expect(comparison.behindBy == 12 && comparison.filesChanged == 2 && comparison.totalCommits == 3)
    // A long branch lists only the first few.
    let many = (1...60).map { #"{"commit": {"message": "Commit \#($0)"}}"# }.joined(separator: ",")
    let long = try GitHubDecoding.comparison(from: data(#"{"status": "ahead", "ahead_by": 60, "total_commits": 60, "commits": [\#(many)]}"#))
    #expect(long.commitTitles.count == GitHubComparison.maxCommitTitles && long.totalCommits == 60)
}

@Test func titleAndLinkAreReadyToPasteIntoAChat() {
    let pull = GitHubPullRequest(number: 5, title: "Add login", url: URL(string: "https://github.com/o/r/pull/5")!, repoFullName: "o/r")
    #expect(pull.titleAndLink == "Add login\nhttps://github.com/o/r/pull/5")
}
