import Foundation

/// Reads what Microsoft sends back. Lenient on purpose: a field that is missing or new never stops a chat showing.
public enum TeamsDecoding {
    // MARK: What the wire looks like

    private struct WireList<Item: Decodable>: Decodable {
        var value: [Item]?
        var nextLink: String?
        enum CodingKeys: String, CodingKey { case value, nextLink = "@odata.nextLink" }
    }

    private struct WireIdentity: Decodable { var id: String?; var displayName: String? }
    private struct WireFrom: Decodable { var user: WireIdentity?; var application: WireIdentity? }
    private struct WireBody: Decodable { var contentType: String?; var content: String? }
    private struct WireAttachment: Decodable {
        var contentType: String?
        var contentUrl: String?
        var content: String?
        var name: String?
    }

    private struct WireMessage: Decodable {
        var id: String?
        var messageType: String?
        var createdDateTime: String?
        var deletedDateTime: String?
        var from: WireFrom?
        var body: WireBody?
        var attachments: [WireAttachment]?
    }

    private struct WireMember: Decodable { var userId: String?; var displayName: String?; var email: String? }

    private struct WireChat: Decodable {
        var id: String?
        var chatType: String?
        var topic: String?
        var webUrl: String?
        var lastUpdatedDateTime: String?
        var members: [WireMember]?
        var lastMessagePreview: WireMessage?
    }

    private struct WireMe: Decodable { var id: String?; var displayName: String?; var mail: String?; var userPrincipalName: String? }

    private struct WireToken: Decodable {
        var accessToken: String?
        var refreshToken: String?
        var expiresIn: Int?

        enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
            refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
            // Usually a number; some answers send it as text.
            if let number = try? c.decodeIfPresent(Int.self, forKey: .expiresIn) {
                expiresIn = number
            } else if let text = try? c.decodeIfPresent(String.self, forKey: .expiresIn) {
                expiresIn = Int(text)
            }
        }
    }

    private struct WireOAuthError: Decodable {
        var error: String?
        var errorDescription: String?
        enum CodingKeys: String, CodingKey { case error, errorDescription = "error_description" }
    }

    private struct WireGraphError: Decodable {
        struct Detail: Decodable { var code: String?; var message: String? }
        var error: Detail?
    }

    // MARK: Who and what

    public static func account(from data: Data) throws -> TeamsAccount {
        guard let me = try? JSONDecoder().decode(WireMe.self, from: data), let id = me.id else { throw TeamsError.unreadable }
        let name = me.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TeamsAccount(id: id, displayName: (name?.isEmpty == false ? name : nil) ?? me.userPrincipalName ?? "You", mail: me.mail ?? me.userPrincipalName)
    }

    public static func chats(from data: Data) throws -> (chats: [TeamsChat], next: URL?) {
        guard let list = try? JSONDecoder().decode(WireList<WireChat>.self, from: data) else { throw TeamsError.unreadable }
        let chats = (list.value ?? []).compactMap(chat(from:))
        return (chats, list.nextLink.flatMap(URL.init(string:)))
    }

    /// The messages of a chat, oldest first. Notices ("Ana was added"), deleted messages and empty ones are left out.
    public static func messages(from data: Data) throws -> (messages: [TeamsMessage], next: URL?) {
        guard let list = try? JSONDecoder().decode(WireList<WireMessage>.self, from: data) else { throw TeamsError.unreadable }
        let messages = (list.value ?? []).compactMap(message(from:)).sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        return (messages, list.nextLink.flatMap(URL.init(string:)))
    }

    // MARK: Signing in

    /// What a token answer holds, as a session. A refresh answer may leave out the refresh token: the earlier one stays good.
    public static func session(from data: Data, clientID: String, tenant: String, previousRefreshToken: String? = nil, now: Date) throws -> TeamsSession {
        guard let wire = try? JSONDecoder().decode(WireToken.self, from: data), let access = wire.accessToken, !access.isEmpty else {
            throw TeamsError.unreadable
        }
        return TeamsSession(
            clientID: clientID, tenant: tenant, accessToken: access, refreshToken: wire.refreshToken ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(wire.expiresIn ?? 3000)))
    }

    /// What Microsoft's sign-in error says (`error` and `error_description`).
    public static func oauthError(from data: Data) -> (code: String?, description: String?) {
        guard let wire = try? JSONDecoder().decode(WireOAuthError.self, from: data) else { return (nil, nil) }
        return (wire.error, wire.errorDescription)
    }

    // MARK: Internals

    private static func chat(from wire: WireChat) -> TeamsChat? {
        guard let id = wire.id, !id.isEmpty else { return nil }
        let members = (wire.members ?? []).compactMap { member -> TeamsMember? in
            let name = member.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty || member.userId != nil else { return nil }
            return TeamsMember(userID: member.userId, name: name, email: member.email)
        }
        let topic = wire.topic?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TeamsChat(
            id: id, kind: TeamsChat.Kind(rawValue: wire.chatType ?? "") ?? .other, topic: (topic?.isEmpty == false) ? topic : nil,
            members: members, preview: wire.lastMessagePreview.flatMap(preview(from:)),
            webURL: wire.webUrl.flatMap(URL.init(string:)), lastUpdated: wire.lastUpdatedDateTime.flatMap(date))
    }

    private static func preview(from wire: WireMessage) -> TeamsPreview? {
        guard wire.messageType == nil || wire.messageType == "message", wire.deletedDateTime == nil, let shown = shownMessage(from: wire) else { return nil }
        var text = TeamsRichText.oneLine(shown.runs)
        if text.isEmpty { text = shown.attachmentNames.first ?? (shown.pullRequests.first?.label ?? "Attachment") }
        return TeamsPreview(text: text, sender: shown.senderName, date: shown.date, mentionsPullRequest: !shown.pullRequests.isEmpty)
    }

    private static func message(from wire: WireMessage) -> TeamsMessage? {
        guard wire.messageType == nil || wire.messageType == "message", wire.deletedDateTime == nil else { return nil }
        return shownMessage(from: wire)
    }

    private static func shownMessage(from wire: WireMessage) -> TeamsMessage? {
        let content = wire.body?.content ?? ""
        let runs = wire.body?.contentType?.lowercased() == "html" ? TeamsRichText.runs(html: content) : TeamsRichText.runs(plain: content)
        let attachments = wire.attachments ?? []
        let texts = attachments.flatMap { [$0.content, $0.contentUrl, $0.name].compactMap { $0 } }
        let pulls = TeamsRichText.pullRequestLinks(runs: runs, attachmentTexts: texts)
        var names = attachments.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if runs.isEmpty, names.isEmpty, pulls.isEmpty, !attachments.isEmpty { names = ["Card"] }
        guard !runs.isEmpty || !names.isEmpty || !pulls.isEmpty else { return nil }
        let sender = wire.from?.user ?? wire.from?.application
        return TeamsMessage(
            id: wire.id ?? UUID().uuidString, senderName: sender?.displayName, senderID: wire.from?.user?.id,
            date: wire.createdDateTime.flatMap(date), runs: runs, pullRequests: pulls, attachmentNames: names)
    }

    /// Microsoft's times have a variable number of fraction digits ("…:31.5Z", "…:31.5070000Z") or none.
    static func date(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: text) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let parsed = plain.date(from: text) { return parsed }
        // Last resort: drop the fraction and try again.
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return trimmed == text ? nil : plain.date(from: trimmed)
    }

    // MARK: Errors

    /// What went wrong, from an answer from Microsoft Graph that was not a success.
    public static func graphError(status: Int, body: Data, headers: [String: String], now: Date = Date()) -> TeamsError {
        let detail = (try? JSONDecoder().decode(WireGraphError.self, from: body))?.error
        let message = detail?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return .notFound
        case 400: return .validation(message ?? "Microsoft didn't accept that request.")
        case 429, 503:
            let seconds = headers["retry-after"].flatMap(TimeInterval.init) ?? 30
            return .rateLimited(until: now.addingTimeInterval(seconds))
        default: return .server
        }
    }

    /// What a failed sign-in means, in plain words, from Microsoft's error code and description. Microsoft's own codes
    /// ("AADSTS…") are kept in the text so they can be looked up.
    public static func signInError(code: String?, description: String?, subcode: String? = nil) -> TeamsError {
        let text = description ?? ""
        // Microsoft ends its text with "Trace ID: … Correlation ID: … Timestamp: …" (on new lines, or all on one): only the sentence before it is for the person.
        var headline = text
        if let trace = headline.range(of: "Trace ID:") { headline = String(headline[..<trace.lowerBound]) }
        headline = headline.components(separatedBy: CharacterSet.newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        func has(_ codes: String...) -> Bool { codes.contains { text.contains("AADSTS\($0)") } }
        if has("65001", "90094", "90095") { return .needsApproval(headline.isEmpty ? nil : headline) }
        if has("65004") { return .signIn("You didn't accept the permissions. Sign in again and choose Accept.") }
        if has("700016") {
            return .signIn("Microsoft doesn't know an app with that Application (client) ID. Check the ID, and the tenant if your company has its own. (\(headline))")
        }
        if has("7000218", "7000215") {
            return .signIn("The app registration isn't set up as a desktop app. In Entra open Authentication, add the platform “Mobile and desktop applications” with the address http://localhost, and set “Allow public client flows” to Yes.")
        }
        if has("50011") {
            return .signIn("The return address isn't registered. In Entra open Authentication, choose “Mobile and desktop applications” and add http://localhost.")
        }
        if has("53003", "53000", "530032") { return .signIn("Your company's access rules (Conditional Access) blocked this sign-in. (\(headline))") }
        if code == "access_denied", !text.contains("AADSTS") {
            // Microsoft sends this (with the subcode "cancel") both when the person presses Cancel and when they leave the
            // "Need admin approval" page without asking: the address cannot tell which, so the message covers both.
            if subcode == "cancel" {
                return .signIn("Microsoft's page ended without letting Island in. If it said “Need admin approval”, your company has to approve this app first (Chat.Read). If you pressed Cancel, just sign in again.")
            }
            return .signIn("The sign-in was cancelled.")
        }
        if headline.isEmpty { return .signIn("Microsoft didn't complete the sign-in\(code.map { " (\($0))" } ?? "").") }
        return .signIn(headline)
    }
}
