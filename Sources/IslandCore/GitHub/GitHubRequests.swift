import Foundation

/// The calls Island makes to GitHub, as ready-to-send requests (nothing is sent here, so they can be checked exactly).
///
/// The token travels only in the `Authorization` header, never in an address. GitHub insists on a `User-Agent`.
public enum GitHubRequests {
    public static let base = URL(string: "https://api.github.com")!

    /// Where a person makes a token, with the one permission Island needs ("repo") and a name already filled in.
    public static let newTokenURL = URL(string: "https://github.com/settings/tokens/new?description=Island&scopes=repo")!

    public static func account(token: String) -> URLRequest {
        get("/user", token: token)
    }

    /// The repositories the account can reach (its own, ones it collaborates on, and its organisations'), the most
    /// recently pushed first.
    public static func repos(token: String, page: Int = 1) -> URLRequest {
        get("/user/repos", token: token, query: [
            ("per_page", "100"), ("sort", "pushed"), ("affiliation", "owner,collaborator,organization_member"), ("page", String(page)),
        ])
    }

    public static func repo(token: String, _ repo: GitHubRepoRef) -> URLRequest {
        get("/repos/\(repo.owner)/\(repo.name)", token: token)
    }

    public static func branches(token: String, _ repo: GitHubRepoRef, page: Int = 1) -> URLRequest {
        get("/repos/\(repo.owner)/\(repo.name)/branches", token: token, query: [("per_page", "100"), ("page", String(page))])
    }

    public static func branch(token: String, _ repo: GitHubRepoRef, name: String) -> URLRequest {
        get("/repos/\(repo.owner)/\(repo.name)/branches/\(escaped(name))", token: token)
    }

    /// How `head` stands against `base` (the commits and files a pull request from it would carry).
    public static func compare(token: String, _ repo: GitHubRepoRef, base: String, head: String) -> URLRequest {
        get("/repos/\(repo.owner)/\(repo.name)/compare/\(escaped(base))...\(escaped(head))", token: token)
    }

    /// A repository's pull request template, as plain text, from one of the places GitHub looks for it.
    public static func pullRequestTemplate(token: String, _ repo: GitHubRepoRef, path: String) -> URLRequest {
        var request = get("/repos/\(repo.owner)/\(repo.name)/contents/\(escaped(path))", token: token)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        return request
    }

    public static func createPullRequest(
        token: String, _ repo: GitHubRepoRef, title: String, head: String, base: String, body: String, draft: Bool
    ) -> URLRequest {
        var request = request("/repos/\(repo.owner)/\(repo.name)/pulls", token: token, query: [])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["title": title, "head": head, "base": base, "body": body, "draft": draft]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return request
    }

    /// The open pull requests from `head` (a branch of the repository itself) into `base`.
    public static func openPullRequests(token: String, _ repo: GitHubRepoRef, head: String, base: String) -> URLRequest {
        get("/repos/\(repo.owner)/\(repo.name)/pulls", token: token, query: [
            ("head", "\(repo.owner):\(head)"), ("base", base), ("state", "open"),
        ])
    }

    /// Pull requests found by a search, most recently updated first.
    public static func searchPullRequests(token: String, query: String, limit: Int = 50) -> URLRequest {
        get("/search/issues", token: token, query: [("q", query), ("sort", "updated"), ("order", "desc"), ("per_page", String(limit))])
    }

    /// One GraphQL call that gets both lists with their review and check status. (The same search qualifiers as the
    /// `*Query` strings below, newest first.)
    public static func pullRequestLists(token: String) -> URLRequest {
        graphQL(token: token, query: pullRequestListsQuery, variables: [
            "mine": myOpenPullRequestsQuery + " sort:updated-desc", "review": reviewRequestedQuery + " sort:updated-desc",
        ])
    }

    /// The fields every pull request list asks for. (All the queries below are checked against GitHub's published GraphQL
    /// schema: every field and enum value exists.)
    static let pullRequestFieldsFragment = """
        fragment PullRequestFields on PullRequest {
          number
          title
          url
          state
          isDraft
          updatedAt
          mergeable
          reviewDecision
          headRefName
          baseRefName
          repository { nameWithOwner }
          author { login }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        }
        """

    public static let pullRequestListsQuery = pullRequestFieldsFragment + """


        query PullRequestLists($mine: String!, $review: String!) {
          mine: search(query: $mine, type: ISSUE, first: 50) { nodes { ...PullRequestFields } }
          review: search(query: $review, type: ISSUE, first: 50) { nodes { ...PullRequestFields } }
        }
        """

    public static let pullRequestSearchQuery = pullRequestFieldsFragment + """


        query PullRequestSearch($query: String!) {
          results: search(query: $query, type: ISSUE, first: 30) { nodes { ...PullRequestFields } }
        }
        """

    public static let pullRequestByNumberQuery = pullRequestFieldsFragment + """


        query PullRequestByNumber($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) { pullRequest(number: $number) { ...PullRequestFields } }
        }
        """

    /// Pull requests matching a search (already worded by `GitHubSearch`), with their review and check status.
    public static func searchPullRequestsWithStatus(token: String, query: String) -> URLRequest {
        graphQL(token: token, query: pullRequestSearchQuery, variables: ["query": query])
    }

    /// One pull request by its number, with its review and check status.
    public static func pullRequestWithStatus(token: String, _ repo: GitHubRepoRef, number: Int) -> URLRequest {
        graphQL(token: token, query: pullRequestByNumberQuery, variables: ["owner": repo.owner, "name": repo.name, "number": number])
    }

    /// One pull request by its number, without the status (what to use if GraphQL cannot be).
    public static func pullRequest(token: String, _ repo: GitHubRepoRef, number: Int) -> URLRequest {
        get("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)", token: token)
    }

    private static func graphQL(token: String, query: String, variables: [String: Any]) -> URLRequest {
        var request = request("/graphql", token: token, query: [])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables], options: [.sortedKeys])
        return request
    }

    /// What to search for to find the pull requests the account opened that are still open.
    public static let myOpenPullRequestsQuery = "is:pr is:open author:@me archived:false"
    /// And the ones other people are waiting on the account to review.
    public static let reviewRequestedQuery = "is:pr is:open review-requested:@me archived:false"

    // MARK: Internals

    /// A branch name or file path as one piece of an address: slashes stay, anything unsafe is escaped.
    private static func escaped(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#%+"))) ?? text
    }

    private static func request(_ path: String, token: String, query: [(String, String)]) -> URLRequest {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
            // URLComponents leaves "+" as it is, and a server reads that as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Island", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func get(_ path: String, token: String, query: [(String, String)] = []) -> URLRequest {
        request(path, token: token, query: query)
    }
}

extension GitHubError {
    /// The error for an HTTP answer that was not a success. `headers` have lower-case names.
    public static func from(status: Int, body: Data?, headers: [String: String], now: Date = Date()) -> GitHubError {
        let message = body.flatMap(GitHubDecoding.errorMessage(from:))
        switch status {
        case 401:
            return .unauthorized
        case 403, 429:
            if let sso = headers["x-github-sso"] { return .sso(ssoURL(in: sso)) }
            let lowered = message?.lowercased() ?? ""
            if status == 429 || headers["x-ratelimit-remaining"] == "0" || lowered.contains("rate limit") {
                if let reset = headers["x-ratelimit-reset"].flatMap(TimeInterval.init) { return .rateLimited(until: Date(timeIntervalSince1970: reset)) }
                if let wait = headers["retry-after"].flatMap(TimeInterval.init) { return .rateLimited(until: now.addingTimeInterval(wait)) }
                return .rateLimited(until: nil)
            }
            return .forbidden(message)
        case 404:
            return .notFound
        case 422:
            return .validation(message ?? "GitHub refused the request.")
        default:
            return .server(status)
        }
    }

    /// "required; url=https://github.com/orgs/acme/sso?authorization_request=…" → the address.
    private static func ssoURL(in header: String) -> URL? {
        guard let range = header.range(of: "url=") else { return nil }
        return URL(string: String(header[range.upperBound...]).trimmingCharacters(in: .whitespaces))
    }
}
