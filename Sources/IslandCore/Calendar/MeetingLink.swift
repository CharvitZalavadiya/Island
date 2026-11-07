import Foundation

/// The link that joins an online meeting, found in an event.
public struct MeetingLink: Equatable, Sendable {
    /// "Google Meet", "Zoom", "Microsoft Teams" … or "Meeting" for a link Island does not know by name.
    public let provider: String
    public let url: URL

    public init(provider: String, url: URL) {
        self.provider = provider
        self.url = url
    }

    /// Looks for a meeting link in an event, in the places calendars put them: the event's own link, its location, and
    /// its notes. A link to a known service (Meet, Zoom, Teams, Webex and others) wins wherever it is. Failing that,
    /// the event's own link, or a link in the location that looks like a call, counts as a meeting too.
    public static func find(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        let ownLink = url.flatMap(webLink)
        let locationLinks = links(in: location)
        let noteLinks = links(in: notes)

        for candidate in ([ownLink].compactMap { $0 } + locationLinks + noteLinks) {
            if let provider = knownProvider(of: candidate) { return MeetingLink(provider: provider, url: candidate) }
        }
        if let ownLink { return MeetingLink(provider: "Meeting", url: ownLink) }
        if let guess = locationLinks.first(where: looksLikeACall) { return MeetingLink(provider: "Meeting", url: guess) }
        return nil
    }

    // MARK: Internals

    /// Every web link in a piece of text, with the wrappers mail systems put around them taken off.
    static func links(in text: String?) -> [URL] {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url }.compactMap(webLink)
    }

    /// An http(s) link, unwrapped if it is one of the "safe link" redirects Outlook and Google add.
    static func webLink(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let wrapped = host.hasSuffix("safelinks.protection.outlook.com") || (host.hasSuffix("google.com") && url.path == "/url")
        if wrapped,
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let target = items.first(where: { ["url", "q"].contains($0.name) })?.value,
           let inner = URL(string: target), inner != url {
            return webLink(inner)
        }
        return url
    }

    /// The name of the meeting service a link belongs to, nil when it is not one Island knows.
    static func knownProvider(of url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        func isHost(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if host == "meet.google.com" || (host == "g.co" && path.hasPrefix("/meet")) { return "Google Meet" }
        if isHost("zoom.us") || isHost("zoomgov.com") || isHost("zoom.com") {
            return ["/j/", "/my/", "/s/", "/wc/", "/meeting"].contains(where: path.hasPrefix) ? "Zoom" : nil
        }
        if isHost("teams.microsoft.com") || isHost("teams.microsoft.us") {
            return ["/l/meetup-join", "/meet/", "/l/meeting", "/meetup-join"].contains(where: path.hasPrefix) ? "Microsoft Teams" : nil
        }
        if host == "teams.live.com" { return path.hasPrefix("/meet") ? "Microsoft Teams" : nil }
        if isHost("webex.com") {
            return ["/meet", "/join", "/j.php", "/wbxmjs", "/webappng"].contains(where: path.contains) ? "Webex" : nil
        }
        if isHost("whereby.com") { return path.count > 1 ? "Whereby" : nil }
        if host == "meet.jit.si" || isHost("jitsi.net") { return path.count > 1 ? "Jitsi" : nil }
        if isHost("gotomeet.me") || isHost("gotomeeting.com") || (isHost("goto.com") && path.hasPrefix("/meeting")) {
            return "GoTo Meeting"
        }
        if isHost("bluejeans.com") { return path.count > 1 ? "BlueJeans" : nil }
        if host == "join.skype.com" { return "Skype" }
        if isHost("chime.aws") { return "Amazon Chime" }
        if host == "meeting.zoho.com" || host == "meet.zoho.com" { return "Zoho Meeting" }
        if isHost("ringcentral.com") && (host.hasPrefix("meetings.") || host == "v.ringcentral.com") { return "RingCentral" }
        if host == "meetings.dialpad.com" { return "Dialpad" }
        if isHost("8x8.vc") { return "8x8" }
        if host == "facetime.apple.com" && path.hasPrefix("/join") { return "FaceTime" }
        if isHost("slack.com") && path.contains("huddle") { return "Slack Huddle" }
        if isHost("around.co") { return path.count > 1 ? "Around" : nil }
        if isHost("livestorm.co") || isHost("airmeet.com") || isHost("gather.town") { return "Meeting" }
        return nil
    }

    /// A link whose address talks of a call, for a service Island has not heard of.
    static func looksLikeACall(_ url: URL) -> Bool {
        let address = ((url.host ?? "") + url.path).lowercased()
        return ["meet", "join", "call", "conference", "huddle", "webinar", "video"].contains { address.contains($0) }
    }
}
