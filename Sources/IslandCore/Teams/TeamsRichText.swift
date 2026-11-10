import Foundation

/// A stretch of a message's words; with a `url` it is a link.
public struct TeamsRun: Equatable, Sendable {
    public var text: String
    public var url: URL?

    public init(text: String, url: URL? = nil) {
        self.text = text
        self.url = url
    }
}

/// Turns what Teams sends as a message (mostly small HTML pages) into plain words with the links kept, and finds the
/// GitHub pull requests in a message.
public enum TeamsRichText {
    // MARK: Reading a message

    /// The words of an HTML message: paragraphs and line breaks become new lines, mentions get an "@", emoji become the
    /// emoji, every other tag is dropped, and each link keeps its address.
    public static func runs(html: String) -> [TeamsRun] {
        var runs: [TeamsRun] = []
        var link: URL?

        func add(_ text: String) {
            guard !text.isEmpty else { return }
            if let last = runs.last, last.url == link {
                runs[runs.count - 1].text += text
            } else {
                runs.append(TeamsRun(text: text, url: link))
            }
        }

        func handle(tag: String) {
            let closing = tag.hasPrefix("/")
            let body = closing ? String(tag.dropFirst()) : tag
            let name = body.prefix { !$0.isWhitespace && $0 != "/" }.lowercased()
            switch name {
            case "br":
                add("\n")
            case "p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "tr":
                if closing { add("\n") } else if name == "li" { add("• ") }
            case "a":
                link = closing ? nil : attribute("href", in: body).flatMap(webURL)
            case "at":
                if !closing { add("@") }
            case "emoji":
                if !closing, let alt = attribute("alt", in: body) { add(alt) }
            case "img":
                if let alt = attribute("alt", in: body), !alt.isEmpty { add(decodeEntities(alt)) } else { add("[image]") }
            default:
                break   // attachment markers, formatting, anything new: nothing to show
            }
        }

        /// HTML shows any run of spaces and line breaks in text as one space.
        func spaced(_ text: String) -> String { text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }

        var index = html.startIndex
        while index < html.endIndex {
            // A tag starts with "<" and a letter or "/"; a "<" followed by anything else (a space, a digit) is only text.
            let tagStart = html[index] == "<" && html.index(after: index) < html.endIndex
                && (html[html.index(after: index)].isLetter || html[html.index(after: index)] == "/")
            if tagStart, let close = html[index...].firstIndex(of: ">") {
                handle(tag: String(html[html.index(after: index)..<close]))
                index = html.index(after: close)
            } else {
                var next = html.index(after: index)
                while next < html.endIndex, html[next] != "<" { next = html.index(after: next) }
                add(decodeEntities(spaced(String(html[index..<next]))))
                index = next
            }
        }
        return linked(tidy(runs))
    }

    /// The words of a plain-text message (bare web addresses become links).
    public static func runs(plain: String) -> [TeamsRun] {
        linked(tidy([TeamsRun(text: plain)]))
    }

    /// The message on one line, as the chat list shows it.
    public static func oneLine(_ runs: [TeamsRun]) -> String {
        runs.map(\.text).joined()
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    // MARK: Links

    /// An address Teams or the company's mail filter has wrapped ("Safe Links") is unwrapped to the real one.
    public static func unwrapped(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(), host.hasSuffix("safelinks.protection.outlook.com"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
              let inner = webURL(target)
        else { return url }
        return inner
    }

    /// The GitHub pull requests a message points at: links in its words, and any in the cards attached to it
    /// (GitHub's own Teams app posts a card, not a link). Each pull request appears once, in the order found.
    public static func pullRequestLinks(runs: [TeamsRun], attachmentTexts: [String] = []) -> [TeamsPullRequestLink] {
        var candidates = runs.compactMap(\.url)
        for text in attachmentTexts {
            // A card is JSON: a "/" inside it may be written "\/".
            let plain = text.replacingOccurrences(of: "\\/", with: "/")
            let range = NSRange(plain.startIndex..., in: plain)
            for match in pullRequestPattern.matches(in: plain, range: range) {
                if let r = Range(match.range, in: plain), let url = URL(string: String(plain[r])) { candidates.append(url) }
            }
        }
        var seen = Set<String>()
        var found: [TeamsPullRequestLink] = []
        for candidate in candidates {
            let url = unwrapped(candidate)
            guard let reference = GitHubPullRequestReference.parse(url.absoluteString) else { continue }
            let key = "\(reference.repo.fullName.lowercased())#\(reference.number)"
            if seen.insert(key).inserted { found.append(TeamsPullRequestLink(url: url, reference: reference)) }
        }
        return found
    }

    // MARK: Internals

    private static let pullRequestPattern = try! NSRegularExpression(
        pattern: #"https?://(?:www\.)?github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+"#, options: [.caseInsensitive])

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Only web addresses are ever made clickable.
    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return unwrapped(url)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        for group in 1...2 {
            if let range = Range(match.range(at: group), in: tag) { return decodeEntities(String(tag[range])) }
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        let regex = try! NSRegularExpression(pattern: "&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);")
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let inner = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[inner])
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = named[name.lowercased()]
            }
            if let replacement { result.replaceSubrange(whole, with: replacement) }
        }
        return result
    }

    /// No blank lines at either end, and never more than one blank line between paragraphs.
    private static func tidy(_ runs: [TeamsRun]) -> [TeamsRun] {
        var result = runs.filter { !$0.text.isEmpty }
        while let first = result.first, first.url == nil, first.text.allSatisfy({ $0.isWhitespace }) { result.removeFirst() }
        while let last = result.last, last.url == nil, last.text.allSatisfy({ $0.isWhitespace }) { result.removeLast() }
        if !result.isEmpty {
            if result[0].url == nil { result[0].text = String(result[0].text.drop(while: { $0.isWhitespace })) }
            let last = result.count - 1
            if result[last].url == nil {
                while let c = result[last].text.last, c.isWhitespace { result[last].text.removeLast() }
            }
        }
        for i in result.indices {
            while result[i].text.contains("\n\n\n") { result[i].text = result[i].text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        }
        return result
    }

    /// Makes the web addresses in unlinked stretches clickable.
    private static func linked(_ runs: [TeamsRun]) -> [TeamsRun] {
        guard let detector = linkDetector else { return runs }
        var result: [TeamsRun] = []
        for run in runs {
            guard run.url == nil else { result.append(run); continue }
            let text = run.text
            var cursor = text.startIndex
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text), let url = match.url,
                      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
                else { continue }
                if range.lowerBound > cursor { result.append(TeamsRun(text: String(text[cursor..<range.lowerBound]))) }
                result.append(TeamsRun(text: String(text[range]), url: unwrapped(url)))
                cursor = range.upperBound
            }
            if cursor < text.endIndex { result.append(TeamsRun(text: String(text[cursor...]))) }
        }
        return result
    }
}
