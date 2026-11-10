import Foundation

/// What the Browser tab's address bar makes of what was typed: a web address, or words to search for.
public enum BrowserAddress {
    public enum Resolved: Equatable {
        /// A web address (a bare "teams.microsoft.com" gets "https://").
        case page(URL)
        /// Words, searched for.
        case search(URL)
        /// Another kind of address (a file, a script, a mail link): the Browser tab does not open those.
        case unsupported
        case empty
    }

    public static func resolve(_ text: String) -> Resolved {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return .empty }
        if typed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return search(typed) }

        // An address that names its kind ("https://…"): only web addresses are opened.
        if matches(typed, #"^[A-Za-z][A-Za-z0-9+.-]*://"#) {
            guard let url = URL(string: typed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
                return .unsupported
            }
            return .page(url)
        }
        // Kinds that are written without "//" (note "localhost:3000" and "example.com:8080" are not one of these).
        if matches(typed, #"^(javascript|data|file|about|mailto|tel|sms|blob|ftp|view-source|vbscript):"#) { return .unsupported }

        if matches(typed, #"^localhost(:\d{1,5})?([/?#].*)?$"#) || matches(typed, #"^\d{1,3}(\.\d{1,3}){3}(:\d{1,5})?([/?#].*)?$"#) {
            return web("http://" + typed) ?? search(typed)   // this Mac, or a machine on the network: usually no certificate
        }
        if matches(typed, #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(:\d{1,5})?([/?#].*)?$"#) {
            return web("https://" + typed) ?? search(typed)
        }
        return search(typed)
    }

    private static func web(_ text: String) -> Resolved? {
        guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
        return .page(url)
    }

    private static func search(_ words: String) -> Resolved {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: words)]
        return .search(components.url!)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The address worth remembering for next time: where the page is, without the query or fragment (those can hold
    /// one-time codes from a sign-in).
    public static func remembered(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string
    }
}

/// What the Browser tab does with a link, a new window or an answer it cannot show. Pure, so it can be tested.
public enum BrowserPolicy {
    public enum Navigation: Equatable {
        case allow
        /// Hand it to the app that handles it (the default browser, or a mail app, …) and do not open it here.
        case openElsewhere
        case cancel
    }

    /// Whether a navigation goes ahead in the Browser tab.
    /// - `isLinkClick`: the person clicked a link, as opposed to a page that redirected or loaded a frame by itself.
    /// - `commandHeld`: Command was down at the click, which always means "in the browser I normally use".
    public static func navigation(to url: URL?, isLinkClick: Bool, commandHeld: Bool, isMainFrame: Bool, wantsDownload: Bool = false) -> Navigation {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        switch scheme {
        case "http", "https":
            if wantsDownload { return .openElsewhere }
            return isLinkClick && commandHeld ? .openElsewhere : .allow
        case "about", "blob", "javascript":
            return .allow
        case "data":
            return isMainFrame ? .cancel : .allow   // a page may use data: inside itself, but not take over the whole view with one
        case "file":
            return .cancel
        default:
            // mailto:, tel:, msteams:, … A click may open the app that handles it; a page doing it by itself may not.
            return isLinkClick ? .openElsewhere : .cancel
        }
    }

    /// Whether an answer is something to hand to the default browser (a download) rather than show here.
    public static func opensElsewhere(canShow: Bool, contentDisposition: String?) -> Bool {
        if !canShow { return true }
        guard let disposition = contentDisposition?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return disposition.hasPrefix("attachment")
    }
}
