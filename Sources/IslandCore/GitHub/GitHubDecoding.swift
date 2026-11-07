import Foundation

/// Reads what GitHub's API sends back. Lenient on purpose: a field that is missing or new never stops a list loading.
public enum GitHubDecoding {
    // MARK: What the wire looks like

    private struct WireOwner: Decodable { var login: String? }
    private struct WirePermissions: Decodable { var push: Bool?; var admin: Bool?; var maintain: Bool? }

    private struct WireRepo: Decodable {
        var id: Int?
        var name: String?
        var fullName: String?
        var owner: WireOwner?
        var defaultBranch: String?
        var isPrivate: Bool?
        var archived: Bool?
        var disabled: Bool?
        var permissions: WirePermissions?
        var pushedAt: String?
        var description: String?
        var hasPullRequests: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name, owner, archived, disabled, permissions, description
            case fullName = "full_name", defaultBranch = "default_branch", isPrivate = "private"
            case pushedAt = "pushed_at", hasPullRequests = "has_pull_requests"
        }
    }

    private struct WireBranch: Decodable {
        var name: String?
        var isProtected: Bool?
        enum CodingKeys: String, CodingKey { case name, isProtected = "protected" }
    }

    private struct WireRef: Decodable {
        var ref: String?
        var repo: WireRepoName?
    }
    private struct WireRepoName: Decodable {
        var fullName: String?
        enum CodingKeys: String, CodingKey { case fullName = "full_name" }
    }
    private struct WirePullLinks: Decodable {
        var htmlUrl: String?
        var mergedAt: String?
        enum CodingKeys: String, CodingKey { case htmlUrl = "html_url", mergedAt = "merged_at" }
    }

    /// A pull request, from the pull request calls (head and base) or from search (a repository link instead).
    private struct WirePull: Decodable {
        var number: Int?
        var title: String?
        var htmlUrl: String?
        var state: String?
        var draft: Bool?
        var mergedAt: String?
        var updatedAt: String?
        var user: WireOwner?
        var head: WireRef?
        var base: WireRef?
        var repositoryUrl: String?
        var pullRequest: WirePullLinks?
        // Only a single pull request (not a list of them) carries these.
        var body: String?
        var commits: Int?
        var additions: Int?
        var deletions: Int?
        var changedFiles: Int?
        var mergeable: Bool?

        enum CodingKeys: String, CodingKey {
            case number, title, state, draft, user, head, base, body, commits, additions, deletions, mergeable
            case htmlUrl = "html_url", mergedAt = "merged_at", updatedAt = "updated_at"
            case repositoryUrl = "repository_url", pullRequest = "pull_request", changedFiles = "changed_files"
        }
    }

    private struct WireReview: Decodable {
        var id: Int?
        var user: WireOwner?
        var state: String?
        var submittedAt: String?
        enum CodingKeys: String, CodingKey { case id, user, state, submittedAt = "submitted_at" }
    }

    private struct WireSearch: Decodable { var items: [WirePull]? }

    private struct WireCommit: Decodable {
        var commit: Inner?
        struct Inner: Decodable { var message: String? }
    }
    private struct WireFile: Decodable {}
    private struct WireComparison: Decodable {
        var status: String?
        var aheadBy: Int?
        var behindBy: Int?
        var totalCommits: Int?
        var commits: [WireCommit]?
        var files: [WireFile]?
        enum CodingKeys: String, CodingKey {
            case status, commits, files
            case aheadBy = "ahead_by", behindBy = "behind_by", totalCommits = "total_commits"
        }
    }

    private struct WireAccount: Decodable { var login: String?; var name: String? }

    // MARK: Public

    public static func account(from data: Data) throws -> GitHubAccount {
        guard let wire = try? JSONDecoder().decode(WireAccount.self, from: data), let login = wire.login, !login.isEmpty else {
            throw GitHubError.unreadable
        }
        let name = wire.name?.trimmingCharacters(in: .whitespaces)
        return GitHubAccount(login: login, name: name?.isEmpty == false ? name : nil)
    }

    public static func repos(from data: Data) throws -> [GitHubRepo] {
        guard let wires = try? JSONDecoder().decode([WireRepo].self, from: data) else { throw GitHubError.unreadable }
        return wires.compactMap(repo(from:))
    }

    public static func repo(from data: Data) throws -> GitHubRepo {
        guard let wire = try? JSONDecoder().decode(WireRepo.self, from: data), let repo = repo(from: wire) else {
            throw GitHubError.unreadable
        }
        return repo
    }

    public static func branches(from data: Data) throws -> [GitHubBranch] {
        guard let wires = try? JSONDecoder().decode([WireBranch].self, from: data) else { throw GitHubError.unreadable }
        return wires.compactMap { wire in wire.name.map { GitHubBranch(name: $0, isProtected: wire.isProtected ?? false) } }
    }

    /// The branch from the single-branch call.
    public static func branch(from data: Data) throws -> GitHubBranch {
        guard let wire = try? JSONDecoder().decode(WireBranch.self, from: data), let name = wire.name else { throw GitHubError.unreadable }
        return GitHubBranch(name: name, isProtected: wire.isProtected ?? false)
    }

    /// A pull request, as the create and get calls answer.
    public static func pullRequest(from data: Data) throws -> GitHubPullRequest {
        guard let wire = try? JSONDecoder().decode(WirePull.self, from: data), let pull = pull(from: wire) else {
            throw GitHubError.unreadable
        }
        return pull
    }

    /// One pull request with the numbers and description the review panel shows, and its reviews.
    public static func pullRequestDetails(pull: Data, reviews: Data) throws -> GitHubPullRequestDetails {
        guard let wire = try? JSONDecoder().decode(WirePull.self, from: pull), let basic = Self.pull(from: wire) else {
            throw GitHubError.unreadable
        }
        return GitHubPullRequestDetails(
            pullRequest: basic, body: wire.body ?? "", commits: wire.commits ?? 0, changedFiles: wire.changedFiles ?? 0,
            additions: wire.additions ?? 0, deletions: wire.deletions ?? 0, hasConflicts: wire.mergeable == false,
            reviews: try self.reviews(from: reviews))
    }

    public static func reviews(from data: Data) throws -> [GitHubReview] {
        guard let wires = try? JSONDecoder().decode([WireReview].self, from: data) else { throw GitHubError.unreadable }
        return wires.compactMap(review(from:))
    }

    /// The review GitHub answers with after one is sent.
    public static func review(from data: Data) throws -> GitHubReview {
        guard let wire = try? JSONDecoder().decode(WireReview.self, from: data), let review = review(from: wire) else {
            throw GitHubError.unreadable
        }
        return review
    }

    private static func review(from wire: WireReview) -> GitHubReview? {
        guard let id = wire.id, let login = wire.user?.login else { return nil }
        let verdict: GitHubReview.Verdict = switch wire.state?.uppercased() {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "DISMISSED": .dismissed
        case "PENDING": .pending
        default: .commented
        }
        return GitHubReview(id: id, authorLogin: login, verdict: verdict, submittedAt: wire.submittedAt.flatMap(date))
    }

    public static func pullRequests(from data: Data) throws -> [GitHubPullRequest] {
        guard let wires = try? JSONDecoder().decode([WirePull].self, from: data) else { throw GitHubError.unreadable }
        return wires.compactMap(pull(from:))
    }

    /// The pull requests in a search answer (issues that carry a `pull_request` entry).
    public static func searchedPullRequests(from data: Data) throws -> [GitHubPullRequest] {
        guard let search = try? JSONDecoder().decode(WireSearch.self, from: data) else { throw GitHubError.unreadable }
        return (search.items ?? []).filter { $0.pullRequest != nil }.compactMap(pull(from:))
    }

    public static func comparison(from data: Data) throws -> GitHubComparison {
        guard let wire = try? JSONDecoder().decode(WireComparison.self, from: data), let status = wire.status else {
            throw GitHubError.unreadable
        }
        let titles = (wire.commits ?? []).prefix(GitHubComparison.maxCommitTitles)
            .compactMap { $0.commit?.message.map(GitHubText.firstLine(of:)) }.filter { !$0.isEmpty }
        return GitHubComparison(
            status: status, aheadBy: wire.aheadBy ?? 0, behindBy: wire.behindBy ?? 0,
            totalCommits: wire.totalCommits ?? wire.commits?.count ?? 0, filesChanged: wire.files?.count ?? 0,
            firstCommitMessage: wire.commits?.first?.commit?.message, commitTitles: titles)
    }

    // MARK: Lists with their status (GraphQL)

    private struct GQLRepository: Decodable { var nameWithOwner: String? }
    private struct GQLAuthor: Decodable { var login: String? }
    private struct GQLRollup: Decodable { var state: String? }
    private struct GQLCommit: Decodable { var statusCheckRollup: GQLRollup? }
    private struct GQLCommitNode: Decodable { var commit: GQLCommit? }
    private struct GQLCommits: Decodable { var nodes: [GQLCommitNode?]? }
    private struct GQLPull: Decodable {
        var number: Int?
        var title: String?
        var url: String?
        var state: String?
        var isDraft: Bool?
        var updatedAt: String?
        var mergeable: String?
        var reviewDecision: String?
        var headRefName: String?
        var baseRefName: String?
        var repository: GQLRepository?
        var author: GQLAuthor?
        var commits: GQLCommits?
    }
    private struct GQLNodes: Decodable { var nodes: [GQLPull?]? }
    private struct GQLData: Decodable { var mine: GQLNodes?; var review: GQLNodes? }
    private struct GQLError: Decodable { var type: String?; var message: String? }
    private struct GQLResponse: Decodable { var data: GQLData?; var errors: [GQLError]? }

    /// The two lists from the GraphQL answer. Entries the account cannot see (they come back as null) are skipped, and a
    /// partial answer (some of an organisation's pull requests hidden behind single sign-on) still gives the rest.
    public static func pullRequestLists(fromGraphQL data: Data) throws -> GitHubPullRequestLists {
        guard let response = try? JSONDecoder().decode(GQLResponse.self, from: data) else { throw GitHubError.unreadable }
        guard let body = response.data, body.mine != nil || body.review != nil else { throw graphQLError(response.errors) }
        return GitHubPullRequestLists(
            mine: (body.mine?.nodes ?? []).compactMap { $0.flatMap(graphQLPull) },
            review: (body.review?.nodes ?? []).compactMap { $0.flatMap(graphQLPull) })
    }

    private struct GQLSearchData: Decodable { var results: GQLNodes? }
    private struct GQLSearchResponse: Decodable { var data: GQLSearchData?; var errors: [GQLError]? }
    private struct GQLRepositoryData: Decodable { var repository: GQLRepositoryPull? }
    private struct GQLRepositoryPull: Decodable { var pullRequest: GQLPull? }
    private struct GQLByNumberResponse: Decodable { var data: GQLRepositoryData?; var errors: [GQLError]? }

    /// The pull requests a GraphQL search found (the answer to the `PullRequestSearch` query).
    public static func pullRequests(fromGraphQLSearch data: Data) throws -> [GitHubPullRequest] {
        guard let response = try? JSONDecoder().decode(GQLSearchResponse.self, from: data) else { throw GitHubError.unreadable }
        guard let nodes = response.data?.results?.nodes else { throw graphQLError(response.errors) }
        return nodes.compactMap { $0.flatMap(graphQLPull) }
    }

    /// One pull request by its number (the answer to `PullRequestByNumber`); nil when the repository has no such number.
    public static func pullRequest(fromGraphQLByNumber data: Data) throws -> GitHubPullRequest? {
        guard let response = try? JSONDecoder().decode(GQLByNumberResponse.self, from: data) else { throw GitHubError.unreadable }
        guard let repository = response.data?.repository else {
            // A repository that does not exist (or cannot be seen) comes back as an error and no data.
            if response.errors?.contains(where: { $0.type == "NOT_FOUND" }) == true { return nil }
            throw graphQLError(response.errors)
        }
        return repository.pullRequest.flatMap(graphQLPull)   // null: no such pull request
    }

    /// What a GraphQL answer with no usable data means.
    private static func graphQLError(_ errors: [GQLError]?) -> GitHubError {
        if let first = errors?.first {
            if first.type == "FORBIDDEN" || first.type == "INSUFFICIENT_SCOPES" { return .forbidden(first.message) }
            if first.type == "RATE_LIMITED" || first.type == "MAX_NODE_LIMIT_EXCEEDED" { return .rateLimited(until: nil) }
        }
        return .unreadable
    }

    private static func graphQLPull(_ wire: GQLPull) -> GitHubPullRequest? {
        guard let number = wire.number, let title = wire.title, let urlText = wire.url, let url = URL(string: urlText),
              let repo = wire.repository?.nameWithOwner
        else { return nil }
        let rollup = wire.commits?.nodes?.compactMap { $0 }.last?.commit?.statusCheckRollup?.state
        let checks: GitHubCheckState? = switch rollup {
        case "SUCCESS": .passing
        case "FAILURE", "ERROR": .failing
        case "PENDING", "EXPECTED": .pending
        default: nil
        }
        let review: GitHubReviewState? = switch wire.reviewDecision {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .required
        default: nil
        }
        let state: GitHubPullRequest.State = switch wire.state {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: .open
        }
        return GitHubPullRequest(
            number: number, title: title, url: url, isDraft: wire.isDraft ?? false, state: state, repoFullName: repo,
            authorLogin: wire.author?.login, headBranch: wire.headRefName, baseBranch: wire.baseRefName,
            updatedAt: wire.updatedAt.flatMap(date), checks: checks, review: review, hasConflicts: wire.mergeable == "CONFLICTING")
    }

    // MARK: Errors and paging

    /// What an error answer says: its message plus the details of each thing wrong, in one sentence.
    public static func errorMessage(from data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var details: [String] = []
        for entry in (object["errors"] as? [Any]) ?? [] {
            if let text = entry as? String { details.append(text) }
            else if let item = entry as? [String: Any] {
                if let text = item["message"] as? String { details.append(text) }
                else if let field = item["field"] as? String, let code = item["code"] as? String {
                    details.append("\(field) is \(code.replacingOccurrences(of: "_", with: " "))")
                }
            }
        }
        if !details.isEmpty { return details.joined(separator: " ") }
        return (object["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The number of the next page, from the `Link` header ("<…?page=2>; rel=\"next\", <…?page=9>; rel=\"last\"").
    public static func nextPage(fromLinkHeader header: String?) -> Int? {
        guard let header else { return nil }
        for entry in header.split(separator: ",") where entry.contains("rel=\"next\"") {
            guard let start = entry.firstIndex(of: "<"), let end = entry.firstIndex(of: ">"), start < end,
                  let components = URLComponents(string: String(entry[entry.index(after: start)..<end])),
                  let page = components.queryItems?.first(where: { $0.name == "page" })?.value
            else { continue }
            return Int(page)
        }
        return nil
    }

    // MARK: Internals

    private static func repo(from wire: WireRepo) -> GitHubRepo? {
        guard let id = wire.id, let fullName = wire.fullName, let name = wire.name else { return nil }
        let owner = wire.owner?.login ?? String(fullName.split(separator: "/").first ?? "")
        let pushable = wire.permissions.map { ($0.push ?? false) || ($0.admin ?? false) || ($0.maintain ?? false) }
        return GitHubRepo(
            id: id, fullName: fullName, owner: owner, name: name, defaultBranch: wire.defaultBranch ?? "main",
            isPrivate: wire.isPrivate ?? false, isArchived: wire.archived ?? false, isDisabled: wire.disabled ?? false,
            canPush: pushable, pushedAt: wire.pushedAt.flatMap(date), summary: wire.description,
            hasPullRequests: wire.hasPullRequests ?? true)
    }

    private static func pull(from wire: WirePull) -> GitHubPullRequest? {
        guard let number = wire.number, let title = wire.title, let urlText = wire.htmlUrl ?? wire.pullRequest?.htmlUrl,
              let url = URL(string: urlText)
        else { return nil }
        // Pull requests name their repository in `base`; search results only give a link to it.
        let repoFromLink = wire.repositoryUrl.flatMap { text in text.range(of: "/repos/").map { String(text[$0.upperBound...]) } }
        guard let repo = wire.base?.repo?.fullName ?? repoFromLink else { return nil }
        let merged = (wire.mergedAt ?? wire.pullRequest?.mergedAt) != nil
        return GitHubPullRequest(
            number: number, title: title, url: url, isDraft: wire.draft ?? false,
            state: merged ? .merged : (wire.state == "closed" ? .closed : .open), repoFullName: repo,
            authorLogin: wire.user?.login, headBranch: wire.head?.ref, baseBranch: wire.base?.ref,
            updatedAt: wire.updatedAt.flatMap(date))
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

public enum GitHubText {
    /// A title for a pull request from the name of its branch: "feature/add-login_page" becomes "Add login page". Anything
    /// before the last slash (a "feature/" or a person's name) is dropped.
    public static func title(fromBranch branch: String) -> String {
        let last = branch.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? branch
        let words = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard let first = words.first else { return branch }
        return first.uppercased() + words.dropFirst()
    }

    /// The first line of a commit message: what makes a good title.
    public static func firstLine(of message: String) -> String {
        message.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
