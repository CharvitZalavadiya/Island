import Foundation

/// Turns what someone types into the search box into a search of one repository's pull requests.
///
/// - `482`, `#482` or a link to the pull request (`https://github.com/owner/repo/pull/482`) is that pull request.
/// - `@ravi` means the ones ravi opened; `branch:feature/login` the ones from that branch; `base:main` the ones into it.
/// - Anything else is searched for in the title and text of the pull requests.
/// - Nothing at all lists the most recently updated ones.
public enum GitHubSearch {
    public enum Plan: Equatable, Sendable {
        /// A pull request by its number.
        case number(Int)
        /// A search with this query.
        case search(String)
    }

    public static func plan(for text: String, in repo: GitHubRepoRef, openOnly: Bool) -> Plan {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = number(in: trimmed, repo: repo) { return .number(number) }

        var parts = ["repo:\(repo.fullName)", "is:pr"]
        if openOnly { parts.append("is:open") }
        for word in trimmed.split(whereSeparator: \.isWhitespace).map(String.init) {
            if word.hasPrefix("@"), word.count > 1 {
                parts.append("author:\(word.dropFirst())")
            } else if let value = value(of: word, prefixes: ["branch:", "head:"]) {
                parts.append("head:\(value)")
            } else if let value = value(of: word, prefixes: ["base:"]) {
                parts.append("base:\(value)")
            } else {
                parts.append(word)
            }
        }
        parts.append("sort:updated-desc")
        return .search(parts.joined(separator: " "))
    }

    /// The number a text names: "482", "#482", or a pull request link in this repository.
    private static func number(in text: String, repo: GitHubRepoRef) -> Int? {
        let bare = text.hasPrefix("#") ? String(text.dropFirst()) : text
        if !bare.isEmpty, bare.allSatisfy(\.isNumber), let number = Int(bare), number > 0 { return number }
        guard let link = URL(string: text), link.host?.lowercased().hasSuffix("github.com") == true else { return nil }
        let parts = link.path.split(separator: "/").map(String.init)
        guard parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]),
              parts[0].lowercased() == repo.owner.lowercased(), parts[1].lowercased() == repo.name.lowercased()
        else { return nil }
        return number
    }

    private static func value(of word: String, prefixes: [String]) -> String? {
        for prefix in prefixes where word.lowercased().hasPrefix(prefix) && word.count > prefix.count {
            return String(word.dropFirst(prefix.count))
        }
        return nil
    }
}

/// A pull request named by a link or by the short form people type: which repository, and which number.
public struct GitHubPullRequestReference: Equatable, Sendable {
    public var repo: GitHubRepoRef
    public var number: Int

    public init(repo: GitHubRepoRef, number: Int) {
        self.repo = repo
        self.number = number
    }

    /// Reads `https://github.com/owner/repo/pull/123` (also without `https://` or `www.`, with `/files`, `/commits`, a
    /// `?query` or a `#fragment` after it) and the short `owner/repo#123`. Nil for anything else, including a link to
    /// another website and a link to an issue.
    public static func parse(_ text: String) -> GitHubPullRequestReference? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty, !rest.contains(where: \.isWhitespace) else { return nil }
        for prefix in ["https://", "http://"] where rest.lowercased().hasPrefix(prefix) { rest = String(rest.dropFirst(prefix.count)) }
        for host in ["www.github.com/", "github.com/"] where rest.lowercased().hasPrefix(host) { rest = String(rest.dropFirst(host.count)) }

        // owner/repo#123
        if let hash = rest.firstIndex(of: "#") {
            let before = String(rest[..<hash]), after = String(rest[rest.index(after: hash)...])
            let parts = before.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, !after.isEmpty, after.allSatisfy(\.isNumber), let number = Int(after), number > 0,
               let repo = GitHubRepoRef.parse("\(parts[0])/\(parts[1])"), repo.fullName == "\(parts[0])/\(parts[1])" {
                return GitHubPullRequestReference(repo: repo, number: number)
            }
        }

        // owner/repo/pull/123 and what may follow it
        var path = rest
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<cut]) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4, parts[2] == "pull", parts[3].allSatisfy(\.isNumber), let number = Int(parts[3]), number > 0,
              let repo = GitHubRepoRef.parse("\(parts[0])/\(parts[1])")
        else { return nil }
        return GitHubPullRequestReference(repo: repo, number: number)
    }
}
