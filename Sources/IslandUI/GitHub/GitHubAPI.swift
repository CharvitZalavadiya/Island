import Foundation
import IslandCore

/// What Island asks of GitHub. The real one talks to the internet; tests use a stand-in.
protocol GitHubAPI: Sendable {
    func account(token: String) async throws -> GitHubAccount
    /// The repositories the account can reach, most recently pushed first.
    func repos(token: String) async throws -> [GitHubRepo]
    func repo(token: String, _ ref: GitHubRepoRef) async throws -> GitHubRepo
    func branches(token: String, _ repo: GitHubRepoRef) async throws -> [GitHubBranch]
    /// One branch by name (throws `notFound` if there is none), for a branch typed in that the list did not show.
    func branch(token: String, _ repo: GitHubRepoRef, name: String) async throws -> GitHubBranch
    func compare(token: String, _ repo: GitHubRepoRef, base: String, head: String) async throws -> GitHubComparison
    /// The repository's pull request template, or nil if it has none.
    func pullRequestTemplate(token: String, _ repo: GitHubRepoRef) async throws -> String?
    func createPullRequest(
        token: String, _ repo: GitHubRepoRef, title: String, head: String, base: String, body: String, draft: Bool
    ) async throws -> GitHubPullRequest
    /// The open pull request from `head` into `base`, if there already is one.
    func openPullRequest(token: String, _ repo: GitHubRepoRef, head: String, base: String) async throws -> GitHubPullRequest?
    /// The account's open pull requests and the ones waiting on its review, with their review and check status.
    func pullRequestLists(token: String) async throws -> GitHubPullRequestLists
    /// Pull requests found by a search (already worded by `GitHubSearch`), with their review and check status.
    func searchPullRequests(token: String, query: String) async throws -> [GitHubPullRequest]
    /// One pull request by its number, or nil if the repository has none with that number.
    func pullRequest(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequest?
}

/// GitHub over the internet. It uses an ephemeral session, so nothing about a person's repositories is cached on disk.
final class URLSessionGitHubAPI: GitHubAPI, @unchecked Sendable {
    private let session: URLSession
    /// The most pages a list is followed through (100 each): 500 repositories or branches is far more than anyone scrolls.
    private let maxPages = 5

    /// Where GitHub looks for a pull request template.
    static let templatePaths = [
        ".github/pull_request_template.md", ".github/PULL_REQUEST_TEMPLATE.md", "pull_request_template.md",
        "PULL_REQUEST_TEMPLATE.md", "docs/pull_request_template.md",
    ]

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func account(token: String) async throws -> GitHubAccount {
        try GitHubDecoding.account(from: try await send(GitHubRequests.account(token: token)).data)
    }

    func repos(token: String) async throws -> [GitHubRepo] {
        try await allPages { page in
            let (data, next) = try await self.send(GitHubRequests.repos(token: token, page: page))
            return GitHubPage(items: try GitHubDecoding.repos(from: data), nextPage: next)
        }
    }

    func repo(token: String, _ ref: GitHubRepoRef) async throws -> GitHubRepo {
        try GitHubDecoding.repo(from: try await send(GitHubRequests.repo(token: token, ref)).data)
    }

    func branches(token: String, _ repo: GitHubRepoRef) async throws -> [GitHubBranch] {
        try await allPages { page in
            let (data, next) = try await self.send(GitHubRequests.branches(token: token, repo, page: page))
            return GitHubPage(items: try GitHubDecoding.branches(from: data), nextPage: next)
        }
    }

    func branch(token: String, _ repo: GitHubRepoRef, name: String) async throws -> GitHubBranch {
        try GitHubDecoding.branch(from: try await send(GitHubRequests.branch(token: token, repo, name: name)).data)
    }

    func compare(token: String, _ repo: GitHubRepoRef, base: String, head: String) async throws -> GitHubComparison {
        try GitHubDecoding.comparison(from: try await send(GitHubRequests.compare(token: token, repo, base: base, head: head)).data)
    }

    func pullRequestTemplate(token: String, _ repo: GitHubRepoRef) async throws -> String? {
        for path in Self.templatePaths {
            do {
                let data = try await send(GitHubRequests.pullRequestTemplate(token: token, repo, path: path)).data
                if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            } catch GitHubError.notFound {
                continue
            } catch GitHubError.unauthorized {
                throw GitHubError.unauthorized
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return nil   // a template is a nicety: any other trouble just means no template
            }
        }
        return nil
    }

    func createPullRequest(
        token: String, _ repo: GitHubRepoRef, title: String, head: String, base: String, body: String, draft: Bool
    ) async throws -> GitHubPullRequest {
        try GitHubDecoding.pullRequest(
            from: try await send(GitHubRequests.createPullRequest(token: token, repo, title: title, head: head, base: base, body: body, draft: draft)).data)
    }

    func openPullRequest(token: String, _ repo: GitHubRepoRef, head: String, base: String) async throws -> GitHubPullRequest? {
        try GitHubDecoding.pullRequests(from: try await send(GitHubRequests.openPullRequests(token: token, repo, head: head, base: base)).data).first
    }

    /// One GraphQL call gets both lists with their review and check status. If GraphQL cannot be used for a reason that is
    /// not about the person (a schema change, a hiccup on GitHub's side), the plain search gives the same lists without
    /// the status, so the lists never go blank over something the person cannot fix.
    func pullRequestLists(token: String) async throws -> GitHubPullRequestLists {
        do {
            return try GitHubDecoding.pullRequestLists(fromGraphQL: try await send(GitHubRequests.pullRequestLists(token: token)).data)
        } catch let error as GitHubError {
            switch error {
            case .unauthorized, .sso, .rateLimited, .network: throw error
            case .forbidden, .notFound, .validation, .server, .unreadable: return try await searchedPullRequestLists(token: token)
            }
        }
    }

    /// A search with status from GraphQL; if GraphQL cannot be used for a reason that is not about the person, the plain
    /// search finds the same pull requests without the status.
    func searchPullRequests(token: String, query: String) async throws -> [GitHubPullRequest] {
        do {
            return try GitHubDecoding.pullRequests(fromGraphQLSearch: try await send(GitHubRequests.searchPullRequestsWithStatus(token: token, query: query)).data)
        } catch let error as GitHubError {
            switch error {
            case .unauthorized, .sso, .rateLimited, .network: throw error
            case .forbidden, .notFound, .validation, .server, .unreadable:
                return try GitHubDecoding.searchedPullRequests(from: try await send(GitHubRequests.searchPullRequests(token: token, query: query)).data)
            }
        }
    }

    func pullRequest(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequest? {
        do {
            return try GitHubDecoding.pullRequest(fromGraphQLByNumber: try await send(GitHubRequests.pullRequestWithStatus(token: token, repo, number: number)).data)
        } catch let error as GitHubError {
            switch error {
            case .unauthorized, .sso, .rateLimited, .network: throw error
            case .forbidden, .notFound, .validation, .server, .unreadable:
                do {
                    return try GitHubDecoding.pullRequest(from: try await send(GitHubRequests.pullRequest(token: token, repo, number: number)).data)
                } catch GitHubError.notFound {
                    return nil
                }
            }
        }
    }

    private func searchedPullRequestLists(token: String) async throws -> GitHubPullRequestLists {
        async let mine = send(GitHubRequests.searchPullRequests(token: token, query: GitHubRequests.myOpenPullRequestsQuery)).data
        async let review = send(GitHubRequests.searchPullRequests(token: token, query: GitHubRequests.reviewRequestedQuery)).data
        return GitHubPullRequestLists(
            mine: try GitHubDecoding.searchedPullRequests(from: try await mine),
            review: try GitHubDecoding.searchedPullRequests(from: try await review))
    }

    // MARK: Internals

    private func allPages<Element: Sendable>(_ fetch: (Int) async throws -> GitHubPage<Element>) async throws -> [Element] {
        var all: [Element] = []
        var page = 1
        for _ in 0..<maxPages {
            let result = try await fetch(page)
            all += result.items
            guard let next = result.nextPage else { break }
            page = next
        }
        return all
    }

    /// Sends a request; returns what came back and the number of the next page, when the answer says there is one.
    private func send(_ request: URLRequest) async throws -> (data: Data, nextPage: Int?) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GitHubError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.unreadable }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.from(status: http.statusCode, body: data, headers: headers)
        }
        return (data, GitHubDecoding.nextPage(fromLinkHeader: headers["link"]))
    }
}
