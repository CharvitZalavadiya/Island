import Foundation

/// One entry of a repository's activity list that is about a branch: it was pushed to (or created, or merged into), or deleted.
public struct GitHubBranchActivity: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case pushed, deleted }

    public var branch: String
    public var kind: Kind
    public var date: Date

    public init(branch: String, kind: Kind, date: Date) {
        self.branch = branch
        self.kind = kind
        self.date = date
    }
}

/// Picks "the N branches pushed to most recently, that still exist" out of a repository's activity list, which comes newest
/// first, a page at a time. The first entry seen for a branch is its newest, and decides: a branch whose newest entry is its
/// deletion is gone, however much was pushed to it before.
public struct GitHubRecentBranches: Sendable {
    public let limit: Int
    /// Newest push first.
    public private(set) var branches: [GitHubBranch] = []
    private var settled: Set<String> = []

    public init(limit: Int) { self.limit = limit }

    /// Enough have been found: the older pages of the activity list are not needed.
    public var isFull: Bool { branches.count >= limit }

    public mutating func add(_ entries: [GitHubBranchActivity]) {
        for entry in entries where !isFull {
            guard settled.insert(entry.branch).inserted else { continue }      // an older entry of a branch already decided
            if entry.kind == .pushed { branches.append(GitHubBranch(name: entry.branch, lastPushed: entry.date)) }
        }
    }
}
