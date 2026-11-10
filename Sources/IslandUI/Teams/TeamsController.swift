import AppKit
import Foundation
import Observation
import IslandCore

/// The Teams tab (a trial): signs in to Microsoft, lists the person's chats (one to one and group), shows a chat's newest
/// messages, and lets a GitHub pull request in a message open in the GitHub tab to review it. Read only.
///
/// - Signing in needs an app the person registered in their own Microsoft Entra (its Application ID is pasted once). The
///   sign-in and refresh tokens are kept in the Keychain; nothing is read from it until the tab is first opened.
/// - A link in a message: a click opens a GitHub pull request in the GitHub tab (anything else in the browser); a
///   Command-click always opens the address in the app that handles it, such as the browser.
@Observable
@MainActor
final class TeamsController {
    enum Connection: Equatable {
        case disconnected
        /// The browser is open on Microsoft's sign-in page (or the answer is being checked).
        case connecting
        case connected
    }

    struct Message: Equatable {
        var text: String
        var isError: Bool
        var action: Action?

        struct Action: Equatable {
            var title: String
            var url: URL
        }
    }

    private struct Config: Codable { var clientID: String; var tenant: String }

    private(set) var isReady = false
    private(set) var connection: Connection = .disconnected
    /// What the connect screen's boxes hold (kept after a failed attempt, and between launches).
    var clientID = ""
    var tenant = ""
    private(set) var account: TeamsAccount?
    private(set) var chats: [TeamsChat] = []
    private(set) var chatsLoaded = false
    private(set) var chatsLoading = false
    /// Filters the chat list by name.
    var filter = ""
    private(set) var openChat: TeamsChat?
    private(set) var messages: [TeamsMessage] = []
    private(set) var messagesLoaded = false
    private(set) var messagesLoading = false
    var message: Message?

    /// Opens a GitHub pull request link for review in the GitHub tab. Set by the island (the tab switch lives there).
    @ObservationIgnored var openPullRequest: (String) -> Void = { _ in }

    @ObservationIgnored private let api: TeamsAPI
    @ObservationIgnored private let auth: TeamsAuthenticating
    @ObservationIgnored private let sessions: TokenStoring
    @ObservationIgnored private let config: TokenStoring
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let openBrowser: @Sendable (URL) -> Void
    @ObservationIgnored private let openExternally: (URL) -> Void
    @ObservationIgnored private let chatInterval: TimeInterval
    @ObservationIgnored private let messageInterval: TimeInterval
    @ObservationIgnored private var session: TeamsSession?
    @ObservationIgnored private var loaded = false
    /// The tab is on screen. Chats are only asked about then, even if a sign-in finishes while the island is closed.
    @ObservationIgnored private var onScreen = false
    @ObservationIgnored private var chatTimer: Timer?
    @ObservationIgnored private var messageTimer: Timer?
    @ObservationIgnored private var pausedUntil = Date.distantPast
    @ObservationIgnored private var refreshTask: Task<TeamsSession, Error>?
    @ObservationIgnored private var signInTask: Task<TeamsSession, Error>?
    @ObservationIgnored private var chatGeneration = 0
    @ObservationIgnored private var messageGeneration = 0

    init(
        api: TeamsAPI = URLSessionTeamsAPI(), auth: TeamsAuthenticating = LoopbackTeamsAuth(),
        sessions: TokenStoring = KeychainTokenStore(forService: "teams"),
        config: TokenStoring = KeychainTokenStore(forService: "teams-app"),
        now: @escaping () -> Date = { Date() }, chatInterval: TimeInterval = 60, messageInterval: TimeInterval = 15,
        openBrowser: @escaping @Sendable (URL) -> Void = { url in DispatchQueue.main.async { _ = NSWorkspace.shared.open(url) } },
        openExternally: @escaping (URL) -> Void = { url in _ = NSWorkspace.shared.open(url) }
    ) {
        self.api = api
        self.auth = auth
        self.sessions = sessions
        self.config = config
        self.now = now
        self.chatInterval = chatInterval
        self.messageInterval = messageInterval
        self.openBrowser = openBrowser
        self.openExternally = openExternally
    }

    // MARK: What the tab shows

    var visibleChats: [TeamsChat] { chats.filter { $0.matches(filter, me: account?.id) } }

    func title(of chat: TeamsChat) -> String { chat.title(me: account?.id) }

    func isMine(_ message: TeamsMessage) -> Bool {
        guard let mine = account?.id, let sender = message.senderID else { return false }
        return mine == sender
    }

    // MARK: Opening and closing the tab

    /// The tab is on screen: look for a saved sign-in, check who it is, and load the chats.
    func start() async {
        onScreen = true
        loadIfNeeded()
        guard connection == .connected else { return }
        scheduleTimers()
        if account == nil { await refreshAccount() }
        guard connection == .connected else { return }
        await refreshChats()
        if openChat != nil { await refreshMessages() }
    }

    func stop() {
        onScreen = false
        chatTimer?.invalidate()
        chatTimer = nil
        messageTimer?.invalidate()
        messageTimer = nil
    }

    // MARK: Signing in

    /// Opens Microsoft's sign-in in the browser and waits for the person to finish there.
    func signIn() async {
        guard connection != .connecting else { return }
        loadIfNeeded()
        message = nil
        let checked: (clientID: String, tenant: String)
        switch TeamsRequests.validated(clientID: clientID, tenant: tenant) {
        case .failure(let error):
            message = signInMessage(for: error)
            return
        case .success(let ok):
            checked = ok
        }
        saveConfig(clientID: checked.clientID, tenant: checked.tenant)
        connection = .connecting
        let auth = self.auth, opener = openBrowser
        let task = Task { try await auth.signIn(clientID: checked.clientID, tenant: checked.tenant, openBrowser: opener) }
        signInTask = task
        do {
            let fresh = try await task.value
            signInTask = nil
            guard persist(fresh) else {
                connection = .disconnected
                message = Message(text: "Island couldn't save the sign-in in your Keychain, so it didn't connect.", isError: true)
                return
            }
            session = fresh
            account = try await api.account(token: fresh.accessToken)
            connection = .connected
            scheduleTimers()
            await refreshChats()
        } catch is CancellationError {
            signInTask = nil
            connection = .disconnected
        } catch {
            signInTask = nil
            connection = .disconnected
            sessions.delete()
            session = nil
            message = signInMessage(for: error)
        }
    }

    /// Gives up on a sign-in that is waiting for the browser.
    func cancelSignIn() { signInTask?.cancel() }

    /// Forgets the sign-in and everything loaded with it. The Application ID stays, so signing in again is one press.
    func disconnect() {
        cancelSignIn()
        stop()
        sessions.delete()
        session = nil
        resetLoaded()
        connection = .disconnected
    }

    func dismissMessage() { message = nil }

    // MARK: Chats and messages

    func refreshChats() async {
        guard connection == .connected, now() >= pausedUntil else { return }
        chatGeneration += 1
        let generation = chatGeneration
        chatsLoading = true
        do {
            let loadedChats = try await withToken { token in try await self.api.chats(token: token) }
            guard generation == chatGeneration else { return }
            chats = loadedChats
            chatsLoaded = true
            chatsLoading = false
        } catch is CancellationError {
            if generation == chatGeneration { chatsLoading = false }
        } catch {
            guard generation == chatGeneration else { return }
            chatsLoading = false
            handle(error, doing: "load your chats")
        }
    }

    func open(_ chat: TeamsChat) async {
        openChat = chat
        messages = []
        messagesLoaded = false
        message = nil
        scheduleMessageTimer()
        await refreshMessages()
    }

    func closeChat() {
        messageGeneration += 1
        openChat = nil
        messages = []
        messagesLoaded = false
        messagesLoading = false
        messageTimer?.invalidate()
        messageTimer = nil
    }

    func refreshMessages() async {
        guard connection == .connected, let chat = openChat, now() >= pausedUntil else { return }
        messageGeneration += 1
        let generation = messageGeneration
        messagesLoading = true
        do {
            let loadedMessages = try await withToken { token in try await self.api.messages(token: token, chatID: chat.id) }
            guard generation == messageGeneration else { return }   // another chat was opened (or this one closed) since
            messages = loadedMessages
            messagesLoaded = true
            messagesLoading = false
        } catch is CancellationError {
            if generation == messageGeneration { messagesLoading = false }
        } catch {
            guard generation == messageGeneration else { return }
            messagesLoading = false
            handle(error, doing: "load that chat")
        }
    }

    // MARK: Links

    /// A link in a message was clicked. A GitHub pull request opens in the GitHub tab to review it there; anything else, and
    /// anything clicked with Command held, opens in the app that handles it (the browser, usually).
    func activate(_ url: URL, commandHeld: Bool) {
        if !commandHeld, GitHubPullRequestReference.parse(url.absoluteString) != nil {
            openPullRequest(url.absoluteString)
            return
        }
        openExternally(url)
    }

    func openInTeams(_ chat: TeamsChat) {
        if let url = chat.webURL { openExternally(url) }
    }

    // MARK: Internals

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        isReady = true
        if let raw = config.load(), let saved = try? JSONDecoder().decode(Config.self, from: Data(raw.utf8)) {
            if clientID.isEmpty { clientID = saved.clientID }
            if tenant.isEmpty { tenant = saved.tenant == "organizations" ? "" : saved.tenant }
        }
        if let raw = sessions.load(), let saved = try? JSONDecoder().decode(TeamsSession.self, from: Data(raw.utf8)) {
            session = saved
            connection = .connected
        }
    }

    private func saveConfig(clientID: String, tenant: String) {
        if let data = try? JSONEncoder().encode(Config(clientID: clientID, tenant: tenant)), let text = String(data: data, encoding: .utf8) {
            _ = config.save(text)
        }
    }

    private func persist(_ session: TeamsSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session), let text = String(data: data, encoding: .utf8) else { return false }
        return sessions.save(text)
    }

    private func refreshAccount() async {
        do {
            account = try await withToken { token in try await self.api.account(token: token) }
        } catch is CancellationError {
        } catch {
            handle(error, doing: nil)
        }
    }

    /// An access token that is good now: the saved one, or a fresh one (several callers at once share one refresh).
    private func accessToken() async throws -> String {
        guard let current = session else { throw TeamsError.unauthorized }
        if current.isValid(at: now()) { return current.accessToken }
        return try await refreshedSession(from: current).accessToken
    }

    private func refreshedSession(from current: TeamsSession) async throws -> TeamsSession {
        if let running = refreshTask { return try await running.value }
        let auth = self.auth
        let task = Task { try await auth.refresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        let fresh = try await task.value
        session = fresh
        _ = persist(fresh)
        return fresh
    }

    /// Runs `call` with a good token. If Microsoft turns the token down anyway, one refresh is tried before giving up.
    private func withToken<T>(_ call: (String) async throws -> T) async throws -> T {
        let token = try await accessToken()
        do {
            return try await call(token)
        } catch TeamsError.unauthorized {
            guard let current = session else { throw TeamsError.unauthorized }
            let fresh = try await refreshedSession(from: current)
            return try await call(fresh.accessToken)
        }
    }

    private func scheduleTimers() {
        guard onScreen else { return }
        if chatTimer == nil, chatInterval > 0 {
            chatTimer = Timer.scheduledTimer(withTimeInterval: chatInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.openChat == nil else { return }
                    await self.refreshChats()
                }
            }
        }
        if openChat != nil { scheduleMessageTimer() }
    }

    private func scheduleMessageTimer() {
        guard onScreen, messageTimer == nil, messageInterval > 0, connection == .connected else { return }
        messageTimer = Timer.scheduledTimer(withTimeInterval: messageInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshMessages() }
        }
    }

    private func resetLoaded() {
        account = nil
        message = nil
        chats = []
        chatsLoaded = false
        chatsLoading = false
        filter = ""
        chatGeneration += 1
        closeChat()
    }

    private func handle(_ error: Error, doing action: String?) {
        switch error as? TeamsError {
        case .unauthorized:
            stop()
            sessions.delete()
            session = nil
            resetLoaded()
            connection = .disconnected
            message = Message(text: "Microsoft no longer accepts this sign-in (it may have expired or been withdrawn). Sign in again.", isError: true)
        case .needsApproval(let detail):
            message = Message(text: approvalText(detail), isError: true)
        case .forbidden(let detail):
            let more = detail.map { " (\($0))" } ?? ""
            message = Message(text: "Microsoft says this app isn't allowed to read that.\(more) In Entra, check the app has the Microsoft Graph permissions Chat.Read and User.Read.", isError: true)
        case .notFound:
            message = Message(text: "Microsoft can't find that chat any more.", isError: true)
        case .validation(let reason):
            message = Message(text: reason, isError: true)
        case .rateLimited(let until):
            pausedUntil = until ?? now().addingTimeInterval(60)
            message = Message(text: "Microsoft asked Island to slow down. It will try again in a moment.", isError: true)
        case .network:
            message = Message(text: action.map { "Couldn't reach Microsoft, so Island couldn't \($0)." } ?? "Couldn't reach Microsoft.", isError: true)
        case .signIn(let text):
            message = Message(text: text, isError: true)
        default:
            message = Message(text: action.map { "Microsoft wouldn't let Island \($0). Try again." } ?? "Microsoft had a problem. Try again in a moment.", isError: true)
        }
    }

    private func signInMessage(for error: Error) -> Message {
        switch error as? TeamsError {
        case .needsApproval(let detail):
            return Message(text: approvalText(detail), isError: true)
        case .signIn(let text):
            return Message(text: text, isError: true)
        case .network:
            return Message(text: "Couldn't reach Microsoft. Check your internet connection and try again.", isError: true)
        case .forbidden, .unauthorized:
            return Message(text: "Microsoft signed you in but won't let Island read your chats. In Entra, check the app has the Microsoft Graph permissions Chat.Read and User.Read.", isError: true)
        default:
            return Message(text: "Microsoft had a problem. Try again in a moment.", isError: true)
        }
    }

    private func approvalText(_ detail: String?) -> String {
        "Your company needs to approve this app before it can read your chats. Ask your IT admin to grant consent for it (Chat.Read, User.Read)." + (detail.map { " Microsoft says: \($0)" } ?? "")
    }
}
