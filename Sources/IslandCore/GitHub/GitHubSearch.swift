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
