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


// MARK: Merged and closed

@Test func theStateOfAPullRequestIsRead() throws {
    func state(_ value: String) throws -> GitHubPullRequest.State {
        let json = #"{"data": {"results": {"nodes": [{"number": 1, "title": "t", "url": "https://github.com/o/r/pull/1", "state": "\#(value)", "repository": {"nameWithOwner": "o/r"}}]}}}"#
        return try GitHubDecoding.pullRequests(fromGraphQLSearch: data(json))[0].state
    }
    #expect(try state("OPEN") == .open && state("MERGED") == .merged && state("CLOSED") == .closed)
    #expect(try state("SOMETHING_NEW") == .open)
}

// MARK: Searching a repository

@Test func aSearchAnswerIsReadWithStatusAndSkipsWhatCannotBeSeen() throws {
    let found = try GitHubDecoding.pullRequests(fromGraphQLSearch: data("""
    {"data": {"results": {"nodes": [
      {"number": 482, "title": "Add login page", "url": "https://github.com/shipmnts/app/pull/482", "state": "OPEN", "isDraft": false,
       "updatedAt": "2026-11-07T10:00:00Z", "mergeable": "MERGEABLE", "reviewDecision": "APPROVED", "headRefName": "feature/login",
       "baseRefName": "main", "repository": {"nameWithOwner": "shipmnts/app"}, "author": {"login": "ravi-k"},
       "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]}},
      null,
      {"number": 300, "title": "Old work", "url": "https://github.com/shipmnts/app/pull/300", "state": "MERGED", "repository": {"nameWithOwner": "shipmnts/app"}}
    ]}}}
    """))
    #expect(found.map(\.number) == [482, 300])
    #expect(found[0].authorLogin == "ravi-k" && found[0].checks == .passing && found[0].review == .approved && found[0].state == .open)
    #expect(found[1].state == .merged)
    #expect(try GitHubDecoding.pullRequests(fromGraphQLSearch: data(#"{"data": {"results": {"nodes": []}}}"#)).isEmpty)
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.pullRequests(fromGraphQLSearch: data("<html>x</html>")) }
    #expect(throws: GitHubError.forbidden("SAML")) {
        try GitHubDecoding.pullRequests(fromGraphQLSearch: data(#"{"data": null, "errors": [{"type": "FORBIDDEN", "message": "SAML"}]}"#))
    }
}

@Test func aPullRequestByNumberIsFoundOrIsNot() throws {
    let found = try GitHubDecoding.pullRequest(fromGraphQLByNumber: data(#"{"data": {"repository": {"pullRequest": {"number": 482, "title": "Add login", "url": "https://github.com/o/r/pull/482", "state": "CLOSED", "repository": {"nameWithOwner": "o/r"}, "author": {"login": "ravi-k"}}}}}"#))
    #expect(found?.number == 482 && found?.state == .closed && found?.authorLogin == "ravi-k")
    // The repository exists but has no such number.
    #expect(try GitHubDecoding.pullRequest(fromGraphQLByNumber: data(#"{"data": {"repository": {"pullRequest": null}}, "errors": [{"type": "NOT_FOUND"}]}"#)) == nil)
    // The repository itself cannot be found.
    #expect(try GitHubDecoding.pullRequest(fromGraphQLByNumber: data(#"{"data": {"repository": null}, "errors": [{"type": "NOT_FOUND", "message": "Could not resolve to a Repository"}]}"#)) == nil)
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.pullRequest(fromGraphQLByNumber: data("nonsense")) }
    #expect(throws: GitHubError.forbidden("scope")) {
        try GitHubDecoding.pullRequest(fromGraphQLByNumber: data(#"{"data": null, "errors": [{"type": "INSUFFICIENT_SCOPES", "message": "scope"}]}"#))
    }
}

@Test func theSearchRequestsAreExact() throws {
    let repo = GitHubRepoRef(owner: "shipmnts", name: "finance")
    let search = GitHubRequests.searchPullRequestsWithStatus(token: "ghp_secret", query: "repo:shipmnts/finance is:pr login")
    #expect(search.httpMethod == "POST" && search.url?.absoluteString == "https://api.github.com/graphql")
    var sent = try #require(try JSONSerialization.jsonObject(with: search.httpBody ?? Data()) as? [String: Any])
    #expect((sent["variables"] as? [String: String])?["query"] == "repo:shipmnts/finance is:pr login")
    #expect((sent["query"] as? String)?.contains("query PullRequestSearch") == true)
    #expect(String(data: search.httpBody ?? Data(), encoding: .utf8)?.contains("ghp_secret") == false)

    let byNumber = GitHubRequests.pullRequestWithStatus(token: "t", repo, number: 482)
    sent = try #require(try JSONSerialization.jsonObject(with: byNumber.httpBody ?? Data()) as? [String: Any])
    let variables = try #require(sent["variables"] as? [String: Any])
    #expect(variables["owner"] as? String == "shipmnts" && variables["name"] as? String == "finance" && variables["number"] as? Int == 482)

    let rest = GitHubRequests.pullRequest(token: "t", repo, number: 482)
    #expect(rest.url?.absoluteString == "https://api.github.com/repos/shipmnts/finance/pulls/482")
}

@Test func whatIsTypedIntoTheSearchBecomesTheRightSearch() {
    let repo = GitHubRepoRef(owner: "shipmnts", name: "finance")
    func plan(_ text: String, open: Bool = true) -> GitHubSearch.Plan { GitHubSearch.plan(for: text, in: repo, openOnly: open) }

    // Nothing typed: the latest.
    #expect(plan("") == .search("repo:shipmnts/finance is:pr is:open sort:updated-desc"))
    #expect(plan("   ", open: false) == .search("repo:shipmnts/finance is:pr sort:updated-desc"))
    // Words are searched for.
    #expect(plan("login form") == .search("repo:shipmnts/finance is:pr is:open login form sort:updated-desc"))
    // @name is an author, branch: a head branch, base: a base branch.
    #expect(plan("@ravi-k") == .search("repo:shipmnts/finance is:pr is:open author:ravi-k sort:updated-desc"))
    #expect(plan("branch:feat/OPS-19583-keda @ravi", open: false) == .search("repo:shipmnts/finance is:pr head:feat/OPS-19583-keda author:ravi sort:updated-desc"))
    #expect(plan("base:staging") == .search("repo:shipmnts/finance is:pr is:open base:staging sort:updated-desc"))
    #expect(plan("keda @ravi") == .search("repo:shipmnts/finance is:pr is:open keda author:ravi sort:updated-desc"))
    // A lone "@" or an empty value is just text.
    #expect(plan("@") == .search("repo:shipmnts/finance is:pr is:open @ sort:updated-desc"))
}

@Test func aNumberOrALinkNamesOnePullRequest() {
    let repo = GitHubRepoRef(owner: "shipmnts", name: "finance")
    func plan(_ text: String) -> GitHubSearch.Plan { GitHubSearch.plan(for: text, in: repo, openOnly: true) }
    #expect(plan("482") == .number(482) && plan("#482") == .number(482) && plan("  #482 ") == .number(482))
    #expect(plan("https://github.com/shipmnts/finance/pull/482") == .number(482))
    #expect(plan("https://github.com/Shipmnts/Finance/pull/482/files") == .number(482))       // any capitals, a deeper link
    // A link to a different repository is not this repository's pull request: it is just searched as text.
    if case .number = plan("https://github.com/other/repo/pull/9") { Issue.record("a link to another repository was taken as ours") }
    #expect(plan("0") != .number(0))                                                         // not a pull request number
    if case .number = plan("OPS-19583") { Issue.record("a ticket id was taken as a number") }
}

// MARK: Reviewing a pull request

// Trimmed copies of a real pull request and its reviews from api.github.com (swiftlang/swift#77261).
private let realDetailedPull = #"{"number": 77261, "title": "Cherrypick fixes for issue 74866 to release/6.0", "state": "closed", "draft": false, "html_url": "https://github.com/swiftlang/swift/pull/77261", "merged_at": "2024-12-02T21:33:22Z", "updated_at": "2024-12-02T21:33:22Z", "body": "  - **Explanation**: This PR cherrypicks the fixes for the Bridged C++ class", "commits": 4, "additions": 299, "deletions": 34, "changed_files": 16, "mergeable": null, "mergeable_state": "unknown", "merged": true, "user": {"login": "hjyamauchi"}, "head": {"ref": "release/6.0"}, "base": {"ref": "release/6.0", "repo": {"full_name": "swiftlang/swift"}}}"#
private let realReviews = #"[{"id": 2436955794, "user": {"login": "airspeedswift"}, "state": "APPROVED", "submitted_at": "2024-11-14T18:52:35Z", "body": ""}, {"id": 2473983521, "user": {"login": "DougGregor"}, "state": "APPROVED", "submitted_at": "2024-12-02T21:33:14Z", "body": ""}]"#

@Test func aPullRequestIsReadWithItsNumbersDescriptionAndReviews() throws {
    let details = try GitHubDecoding.pullRequestDetails(pull: data(realDetailedPull), reviews: data(realReviews))
    #expect(details.pullRequest.number == 77261 && details.pullRequest.state == .merged && details.pullRequest.authorLogin == "hjyamauchi")
    #expect(details.pullRequest.headBranch == "release/6.0" && details.pullRequest.repoFullName == "swiftlang/swift")
    #expect(details.commits == 4 && details.changedFiles == 16 && details.additions == 299 && details.deletions == 34)
    #expect(details.body.hasPrefix("  - **Explanation**") && !details.hasConflicts)               // mergeable null = not known to clash
    #expect(details.reviews.map(\.authorLogin) == ["airspeedswift", "DougGregor"] && details.reviews.allSatisfy { $0.verdict == .approved })
    #expect(details.reviews[0].submittedAt == ISO8601DateFormatter().date(from: "2024-11-14T18:52:35Z"))
    #expect(details.approvers == ["airspeedswift", "DougGregor"] && details.changeRequesters.isEmpty)
}

@Test func aPullRequestKnownToClashIsToldSo() throws {
    let clashing = realDetailedPull.replacingOccurrences(of: #""mergeable": null"#, with: #""mergeable": false"#)
    #expect(try GitHubDecoding.pullRequestDetails(pull: data(clashing), reviews: data("[]")).hasConflicts)
    let fine = realDetailedPull.replacingOccurrences(of: #""mergeable": null"#, with: #""mergeable": true"#)
    #expect(try GitHubDecoding.pullRequestDetails(pull: data(fine), reviews: data("[]")).hasConflicts == false)
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.pullRequestDetails(pull: data("<html>"), reviews: data("[]")) }
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.pullRequestDetails(pull: data(realDetailedPull), reviews: data(#"{"message": "x"}"#)) }
}

@Test func everyKindOfReviewIsRead() throws {
    func verdict(_ state: String) throws -> GitHubReview.Verdict {
        try GitHubDecoding.review(from: data(#"{"id": 1, "user": {"login": "a"}, "state": "\#(state)", "submitted_at": "2026-11-07T10:00:00Z"}"#)).verdict
    }
    #expect(try verdict("APPROVED") == .approved && verdict("CHANGES_REQUESTED") == .changesRequested)
    #expect(try verdict("COMMENTED") == .commented && verdict("DISMISSED") == .dismissed && verdict("PENDING") == .pending)
    #expect(try verdict("SOMETHING_NEW") == .commented)                                           // an unknown kind is only a comment
    #expect(throws: GitHubError.unreadable) { try GitHubDecoding.review(from: data(#"{"message": "Not Found"}"#)) }
}

@Test func whereAReviewerStandsIsTheirLatestWordNotTheirLatestComment() {
    let pull = GitHubPullRequest(number: 1, title: "t", url: URL(string: "https://github.com/o/r/pull/1")!, repoFullName: "o/r")
    func at(_ day: Int) -> Date { Date(timeIntervalSince1970: Double(day) * 86_400) }
    let details = GitHubPullRequestDetails(pullRequest: pull, reviews: [
        GitHubReview(id: 1, authorLogin: "Ravi", verdict: .changesRequested, submittedAt: at(1)),
        GitHubReview(id: 2, authorLogin: "ravi", verdict: .approved, submittedAt: at(3)),            // changed their mind (any capitals)
        GitHubReview(id: 3, authorLogin: "ravi", verdict: .commented, submittedAt: at(4)),           // a later comment changes nothing
        GitHubReview(id: 4, authorLogin: "priya", verdict: .approved, submittedAt: at(2)),
        GitHubReview(id: 5, authorLogin: "priya", verdict: .dismissed, submittedAt: at(5)),          // her approval was withdrawn
        GitHubReview(id: 6, authorLogin: "meera", verdict: .changesRequested, submittedAt: at(2)),
        GitHubReview(id: 7, authorLogin: "sam", verdict: .commented, submittedAt: at(2)),
        GitHubReview(id: 8, authorLogin: "pat", verdict: .pending, submittedAt: nil),
    ])
    #expect(details.standing(of: "RAVI")?.verdict == .approved)
    #expect(details.standing(of: "priya")?.verdict == .dismissed)
    #expect(details.standing(of: "sam") == nil && details.standing(of: "pat") == nil && details.standing(of: "nobody") == nil)
    #expect(details.approvers.map { $0.lowercased() } == ["ravi"])        // logins are not case-sensitive
    #expect(details.changeRequesters == ["meera"])
}

@Test func theReviewRequestsAreExact() throws {
    let repo = GitHubRepoRef(owner: "shipmnts", name: "finance")
    let list = GitHubRequests.reviews(token: "t", repo, number: 1204)
    #expect(list.url?.absoluteString == "https://api.github.com/repos/shipmnts/finance/pulls/1204/reviews?per_page=100")

    func sent(_ request: URLRequest) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    }
    let approve = GitHubRequests.submitReview(token: "ghp_secret", repo, number: 1204, event: .approve, body: "   ")
    #expect(approve.httpMethod == "POST" && approve.url?.absoluteString == "https://api.github.com/repos/shipmnts/finance/pulls/1204/reviews")
    #expect(try sent(approve).count == 1 && (try sent(approve))["event"] as? String == "APPROVE")        // no empty body sent
    #expect(String(data: approve.httpBody ?? Data(), encoding: .utf8)?.contains("ghp_secret") == false)

    let changes = GitHubRequests.submitReview(token: "t", repo, number: 1204, event: .requestChanges, body: "  Please add a test.\n")
    #expect(try sent(changes)["event"] as? String == "REQUEST_CHANGES" && (try sent(changes))["body"] as? String == "Please add a test.")
    #expect(try sent(GitHubRequests.submitReview(token: "t", repo, number: 1, event: .comment, body: "Looks odd"))["event"] as? String == "COMMENT")
    #expect(GitHubReviewEvent.approve.needsComment == false && GitHubReviewEvent.requestChanges.needsComment && GitHubReviewEvent.comment.needsComment)
}
