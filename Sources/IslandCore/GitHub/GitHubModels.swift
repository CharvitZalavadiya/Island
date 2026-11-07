import Foundation

/// Who the token belongs to.
public struct GitHubAccount: Equatable, Sendable {
    public var login: String
    public var name: String?

    public init(login: String, name: String? = nil) {
        self.login = login
        self.name = name
    }
}

public struct GitHubRepo: Equatable, Identifiable, Sendable {
    public let id: Int
    public var fullName: String
    public var owner: String
    public var name: String
    public var defaultBranch: String
    public var isPrivate: Bool
    public var isArchived: Bool
    public var isDisabled: Bool
    /// Whether the account can push to it; nil when GitHub did not say.
    public var canPush: Bool?
    public var pushedAt: Date?
    public var summary: String?
    public var hasPullRequests: Bool

    public init(
        id: Int, fullName: String, owner: String, name: String, defaultBranch: String = "main", isPrivate: Bool = false,
        isArchived: Bool = false, isDisabled: Bool = false, canPush: Bool? = true, pushedAt: Date? = nil, summary: String? = nil,
        hasPullRequests: Bool = true
    ) {
        self.id = id
        self.fullName = fullName
        self.owner = owner
        self.name = name
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.isArchived = isArchived
        self.isDisabled = isDisabled
        self.canPush = canPush
        self.pushedAt = pushedAt
        self.summary = summary
        self.hasPullRequests = hasPullRequests
    }

    /// A pull request can start from one of its own branches: it is not archived or disabled, takes pull requests, and
    /// the account can push to it (a branch of the repository itself needs that).
    public var canTakePullRequests: Bool { !isArchived && !isDisabled && hasPullRequests && canPush != false }

    public var reference: GitHubRepoRef { GitHubRepoRef(owner: owner, name: name) }
    public var webURL: URL? { URL(string: "https://github.com/\(fullName)") }
}

/// "owner/name": which repository, however the person wrote it.
public struct GitHubRepoRef: Equatable, Hashable, Sendable {
    public var owner: String
    public var name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    public var fullName: String { "\(owner)/\(name)" }

    /// From the `owner/name` GitHub gives for a repository.
    public init(fullName: String) {
        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        self.init(owner: parts.first ?? "", name: parts.count > 1 ? parts[1] : "")
    }

    /// Reads `owner/name`, a repository link (`https://github.com/owner/name`, with or without more after it, such as a
    /// pull request link) or `github.com/owner/name`. Nil for anything else.
    public static func parse(_ text: String) -> GitHubRepoRef? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where trimmed.lowercased().hasPrefix(prefix) { trimmed = String(trimmed.dropFirst(prefix.count)) }
        for host in ["www.github.com/", "github.com/"] where trimmed.lowercased().hasPrefix(host) { trimmed = String(trimmed.dropFirst(host.count)) }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        var name = parts[1]
        if name.lowercased().hasSuffix(".git") { name = String(name.dropLast(4)) }
        // An owner is letters, digits and hyphens (no dots, so "example.com/x/y" is not mistaken for one); a repository
        // name may also have dots and underscores.
        let ownerCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let nameCharacters = ownerCharacters.union(CharacterSet(charactersIn: "_."))
        func isValid(_ part: String, _ allowed: CharacterSet) -> Bool { !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains) }
        guard isValid(parts[0], ownerCharacters), isValid(name, nameCharacters) else { return nil }
        return GitHubRepoRef(owner: parts[0], name: name)
    }
}

public struct GitHubBranch: Equatable, Hashable, Sendable {
    public var name: String
    public var isProtected: Bool

    public init(name: String, isProtected: Bool = false) {
        self.name = name
        self.isProtected = isProtected
    }
}

/// How a pull request's automated checks (tests, builds) are doing.
public enum GitHubCheckState: Equatable, Sendable {
    case passing
    case failing
    case pending
}

/// Where a pull request stands with its reviewers.
public enum GitHubReviewState: Equatable, Sendable {
    case approved
    case changesRequested
    /// A review is needed and nobody has given one yet.
    case required
}

public struct GitHubPullRequest: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        case open
        case closed
        case merged
    }

    public var number: Int
    public var title: String
    public var url: URL
    public var isDraft: Bool
    public var state: State
    public var repoFullName: String
    public var authorLogin: String?
    public var headBranch: String?
    public var baseBranch: String?
    public var updatedAt: Date?
    /// The state of its checks, when it has any (only the lists that ask for it fill this in).
    public var checks: GitHubCheckState?
    public var review: GitHubReviewState?
    /// True when it cannot be merged as it is because it clashes with its base branch.
    public var hasConflicts: Bool

    public var id: String { "\(repoFullName)#\(number)" }

    public init(
        number: Int, title: String, url: URL, isDraft: Bool = false, state: State = .open, repoFullName: String,
        authorLogin: String? = nil, headBranch: String? = nil, baseBranch: String? = nil, updatedAt: Date? = nil,
        checks: GitHubCheckState? = nil, review: GitHubReviewState? = nil, hasConflicts: Bool = false
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.state = state
        self.repoFullName = repoFullName
        self.authorLogin = authorLogin
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.updatedAt = updatedAt
        self.checks = checks
        self.review = review
        self.hasConflicts = hasConflicts
    }

    /// `[owner/repo#12 Title](link)`, ready to paste into a chat or a document.
    public var markdownLink: String {
        "[\(repoFullName)#\(number) \(title)](\(url.absoluteString))"
    }

    /// The title and the link on two lines: what to paste into a chat to send someone the pull request.
    public var titleAndLink: String {
        "\(title)\n\(url.absoluteString)"
    }
}

/// What a review says. The raw values are what GitHub's API calls them.
public enum GitHubReviewEvent: String, Equatable, Sendable {
    case approve = "APPROVE"
    /// GitHub's name for rejecting: the author is asked to change something before it can be merged.
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"

    /// GitHub refuses a request for changes, or a plain comment, that says nothing.
    public var needsComment: Bool { self != .approve }
}

/// One review someone left on a pull request.
public struct GitHubReview: Equatable, Identifiable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case approved
        case changesRequested
        case commented
        /// An earlier review that was withdrawn by someone with the right to.
        case dismissed
        /// Started but not sent yet.
        case pending
    }

    public var id: Int
    public var authorLogin: String
    public var verdict: Verdict
    public var submittedAt: Date?

    public init(id: Int, authorLogin: String, verdict: Verdict, submittedAt: Date? = nil) {
        self.id = id
        self.authorLogin = authorLogin
        self.verdict = verdict
        self.submittedAt = submittedAt
    }
}

/// Everything the review panel shows about one pull request.
public struct GitHubPullRequestDetails: Equatable, Sendable {
    public var pullRequest: GitHubPullRequest
    /// Its description, as written (Markdown).
    public var body: String
    public var commits: Int
    public var changedFiles: Int
    public var additions: Int
    public var deletions: Int
    /// Known to clash with its base branch (GitHub says so only once it has worked it out).
    public var hasConflicts: Bool
    public var reviews: [GitHubReview]

    public init(
        pullRequest: GitHubPullRequest, body: String = "", commits: Int = 0, changedFiles: Int = 0, additions: Int = 0, deletions: Int = 0,
        hasConflicts: Bool = false, reviews: [GitHubReview] = []
    ) {
        self.pullRequest = pullRequest
        self.body = body
        self.commits = commits
        self.changedFiles = changedFiles
        self.additions = additions
        self.deletions = deletions
        self.hasConflicts = hasConflicts
        self.reviews = reviews
    }

    /// Where `login` stands: their latest approval, request for changes or dismissal. A plain comment does not change
    /// where someone stands, and a review not yet sent does not count.
    public func standing(of login: String) -> GitHubReview? {
        reviews
            .filter { $0.authorLogin.lowercased() == login.lowercased() && ($0.verdict == .approved || $0.verdict == .changesRequested || $0.verdict == .dismissed) }
            .max { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }
    }

    /// The reviewers whose latest word is an approval, and the ones whose latest word asks for changes.
    public var approvers: [String] { latestVerdicts(.approved) }
    public var changeRequesters: [String] { latestVerdicts(.changesRequested) }

    private func latestVerdicts(_ wanted: GitHubReview.Verdict) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for review in reviews where seen.insert(review.authorLogin.lowercased()).inserted {
            if standing(of: review.authorLogin)?.verdict == wanted { names.append(review.authorLogin) }
        }
        return names
    }
}

/// The person's open pull requests and the ones waiting on their review.
public struct GitHubPullRequestLists: Equatable, Sendable {
    public var mine: [GitHubPullRequest]
    public var review: [GitHubPullRequest]

    public init(mine: [GitHubPullRequest], review: [GitHubPullRequest]) {
        self.mine = mine
        self.review = review
    }
}

/// How one branch stands against another.
public struct GitHubComparison: Equatable, Sendable {
    /// "ahead", "behind", "identical" or "diverged".
    public var status: String
    public var aheadBy: Int
    public var behindBy: Int
    public var totalCommits: Int
    public var filesChanged: Int
    /// The message of the first commit on the branch (its first line is a good title for the pull request).
    public var firstCommitMessage: String?
    /// The first line of each commit's message, oldest first (up to `maxCommitTitles` of them).
    public var commitTitles: [String]

    public static let maxCommitTitles = 20

    public init(
        status: String, aheadBy: Int, behindBy: Int = 0, totalCommits: Int, filesChanged: Int = 0, firstCommitMessage: String? = nil,
        commitTitles: [String] = []
    ) {
        self.status = status
        self.aheadBy = aheadBy
        self.behindBy = behindBy
        self.totalCommits = totalCommits
        self.filesChanged = filesChanged
        self.firstCommitMessage = firstCommitMessage
        self.commitTitles = commitTitles
    }

    /// A pull request needs something new on the branch.
    public var hasChanges: Bool { aheadBy > 0 }
}

/// One page of a list GitHub hands out in pieces, and the number of the next page (nil on the last).
public struct GitHubPage<Element: Sendable>: Sendable {
    public var items: [Element]
    public var nextPage: Int?

    public init(items: [Element], nextPage: Int? = nil) {
        self.items = items
        self.nextPage = nextPage
    }
}

/// Why a call to GitHub did not work, in terms the person can act on.
public enum GitHubError: Error, Equatable, Sendable {
    /// The token was refused (wrong, expired or revoked).
    case unauthorized
    /// The organisation wants the token authorised for single sign-on; this is the page to do it on, when GitHub gives it.
    case sso(URL?)
    /// Too many requests; the time the allowance comes back, when GitHub says.
    case rateLimited(until: Date?)
    /// Not allowed (the token lacks a permission, or the repository is not open to it).
    case forbidden(String?)
    /// There is no such thing, or this token cannot see it (GitHub answers the same for both).
    case notFound
    /// GitHub understood the request and refused it, saying why ("A pull request already exists for …").
    case validation(String)
    case server(Int)
    /// GitHub could not be reached at all.
    case network(String)
    /// GitHub answered, but not in a form Island understands.
    case unreadable
}
