import Foundation

// A trial: everything Teams lives in `Teams/` folders (core, UI), the tab case, the services line and the width, so it can
// be removed cleanly if Microsoft will not let the app in.

/// Who is signed in to Microsoft Teams.
public struct TeamsAccount: Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var mail: String?

    public init(id: String, displayName: String, mail: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.mail = mail
    }
}

/// What the app keeps (in a file only the user can read) after a sign-in. The client id and tenant travel with it so a refresh needs nothing else.
public struct TeamsSession: Codable, Equatable, Sendable {
    public var clientID: String
    public var tenant: String
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(clientID: String, tenant: String, accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.clientID = clientID
        self.tenant = tenant
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Whether the access token is good for at least another `margin` seconds.
    public func isValid(at now: Date, margin: TimeInterval = 90) -> Bool {
        now.addingTimeInterval(margin) < expiresAt
    }
}

public struct TeamsMember: Equatable, Sendable {
    public var userID: String?
    public var name: String
    public var email: String?

    public init(userID: String?, name: String, email: String? = nil) {
        self.userID = userID
        self.name = name
        self.email = email
    }
}

/// The newest message of a chat, as the chat list shows it.
public struct TeamsPreview: Equatable, Sendable {
    public var text: String
    public var sender: String?
    public var date: Date?
    /// A GitHub pull request is linked in it.
    public var mentionsPullRequest: Bool

    public init(text: String, sender: String?, date: Date?, mentionsPullRequest: Bool = false) {
        self.text = text
        self.sender = sender
        self.date = date
        self.mentionsPullRequest = mentionsPullRequest
    }
}

public struct TeamsChat: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case oneOnOne, group, meeting, other }

    public var id: String
    public var kind: Kind
    public var topic: String?
    public var members: [TeamsMember]
    public var preview: TeamsPreview?
    public var webURL: URL?
    public var lastUpdated: Date?

    public init(
        id: String, kind: Kind, topic: String? = nil, members: [TeamsMember] = [], preview: TeamsPreview? = nil,
        webURL: URL? = nil, lastUpdated: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.topic = topic
        self.members = members
        self.preview = preview
        self.webURL = webURL
        self.lastUpdated = lastUpdated
    }

    /// When the chat last had something: its newest message, else when it last changed.
    public var lastActivity: Date? { preview?.date ?? lastUpdated }

    /// What the chat is called: its topic, else the other person (one to one), else the other people's names.
    public func title(me userID: String?) -> String {
        if let topic = topic?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty { return topic }
        let others = members.filter { member in
            guard let userID, let id = member.userID else { return true }
            return id != userID
        }.map(\.name).filter { !$0.isEmpty }
        switch kind {
        case .oneOnOne:
            return others.first ?? members.first?.name ?? "Chat"
        case .meeting:
            return others.isEmpty ? "Meeting chat" : others.prefix(2).joined(separator: ", ")
        case .group, .other:
            guard !others.isEmpty else { return members.first?.name ?? "Group chat" }
            let shown = others.prefix(3).joined(separator: ", ")
            return others.count > 3 ? "\(shown) +\(others.count - 3)" : shown
        }
    }

    public func matches(_ query: String, me userID: String?) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return title(me: userID).lowercased().contains(needle) || members.contains { $0.name.lowercased().contains(needle) }
    }
}

/// One message in a chat, ready to show.
public struct TeamsMessage: Identifiable, Equatable, Sendable {
    public var id: String
    public var senderName: String?
    public var senderID: String?
    public var date: Date?
    /// The words, in pieces so the links can be clicked.
    public var runs: [TeamsRun]
    /// GitHub pull requests linked in the message or in a card attached to it, each once.
    public var pullRequests: [TeamsPullRequestLink]
    /// Files and cards attached that have no text of their own (named so the message does not look empty).
    public var attachmentNames: [String]

    public init(
        id: String, senderName: String?, senderID: String? = nil, date: Date?, runs: [TeamsRun],
        pullRequests: [TeamsPullRequestLink] = [], attachmentNames: [String] = []
    ) {
        self.id = id
        self.senderName = senderName
        self.senderID = senderID
        self.date = date
        self.runs = runs
        self.pullRequests = pullRequests
        self.attachmentNames = attachmentNames
    }

    public var text: String { runs.map(\.text).joined() }
}

public struct TeamsPullRequestLink: Equatable, Sendable {
    public var url: URL
    public var reference: GitHubPullRequestReference

    public init(url: URL, reference: GitHubPullRequestReference) {
        self.url = url
        self.reference = reference
    }

    /// "owner/repo #123".
    public var label: String { "\(reference.repo.fullName) #\(reference.number)" }
}

/// Why Microsoft (or the network) did not do what was asked.
public enum TeamsError: Error, Equatable, Sendable {
    /// The sign-in is no longer good (the access was withdrawn, or has expired for good): sign in again.
    case unauthorized
    /// The company has to approve the app, or the person is not allowed to use it (the reason in Microsoft's words).
    case needsApproval(String?)
    case forbidden(String?)
    case notFound
    case validation(String)
    case rateLimited(until: Date?)
    case server
    case network(String)
    case unreadable
    /// The sign-in itself did not work; the text says why and what to change.
    case signIn(String)
}
