import AppKit
import Foundation
import Network
import IslandCore

/// What Island asks of Microsoft Teams (through Microsoft Graph). The real one talks to the internet; tests use a stand-in.
protocol TeamsAPI: Sendable {
    func account(token: String) async throws -> TeamsAccount
    /// The person's chats, the most recently active first.
    func chats(token: String) async throws -> [TeamsChat]
    /// The newest messages of a chat, oldest first.
    func messages(token: String, chatID: String) async throws -> [TeamsMessage]
}

/// Signing in to Microsoft (and keeping the sign-in alive).
protocol TeamsAuthenticating: Sendable {
    /// Opens the sign-in page with `openBrowser`, then waits for the person to finish it there.
    func signIn(clientID: String, tenant: String, openBrowser: @Sendable (URL) -> Void) async throws -> TeamsSession
    /// A fresh access token from the refresh token. Throws `unauthorized` when Microsoft will no longer give one.
    func refresh(_ session: TeamsSession) async throws -> TeamsSession
}

// MARK: Microsoft Graph

/// Microsoft Graph over the internet, on an ephemeral session: nothing from a person's chats is cached on disk.
final class URLSessionTeamsAPI: TeamsAPI, @unchecked Sendable {
    private let session: URLSession
    private let maxPages = 2

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func account(token: String) async throws -> TeamsAccount {
        try TeamsDecoding.account(from: try await send(TeamsRequests.account(token: token)))
    }

    func chats(token: String) async throws -> [TeamsChat] {
        // The fuller question (with each chat's newest message) first; if Microsoft will not answer it, the simpler one.
        do {
            return try await chatPages(first: TeamsRequests.chats(token: token, withLatestMessage: true), token: token)
        } catch let error as TeamsError {
            switch error {
            case .validation, .server, .notFound, .unreadable:
                return try await chatPages(first: TeamsRequests.chats(token: token, withLatestMessage: false), token: token)
            default:
                throw error
            }
        }
    }

    private func chatPages(first: URLRequest, token: String) async throws -> [TeamsChat] {
        var all: [TeamsChat] = []
        var request: URLRequest? = first
        var pages = 0
        while let current = request, pages < maxPages {
            let page = try TeamsDecoding.chats(from: try await send(current))
            all += page.chats
            pages += 1
            request = page.next.flatMap { TeamsRequests.nextPage(token: token, url: $0) }
        }
        // Newest activity first, whatever order they came in.
        return all.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    func messages(token: String, chatID: String) async throws -> [TeamsMessage] {
        try TeamsDecoding.messages(from: try await send(TeamsRequests.messages(token: token, chatID: chatID))).messages
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TeamsError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw TeamsError.unreadable }
        guard (200..<300).contains(http.statusCode) else {
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
            throw TeamsDecoding.graphError(status: http.statusCode, body: data, headers: headers)
        }
        return data
    }
}

// MARK: Signing in

/// The sign-in for a desktop app: the browser opens Microsoft's page, and Microsoft sends it back to a port on this Mac
/// (`http://localhost:…`) with a one-time code, which Island trades for the access. No password and no secret is kept.
final class LoopbackTeamsAuth: TeamsAuthenticating, @unchecked Sendable {
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let waitSeconds: TimeInterval

    init(session: URLSession = URLSession(configuration: .ephemeral), now: @escaping @Sendable () -> Date = { Date() }, waitSeconds: TimeInterval = 300) {
        self.session = session
        self.now = now
        self.waitSeconds = waitSeconds
    }

    func signIn(clientID: String, tenant: String, openBrowser: @Sendable (URL) -> Void) async throws -> TeamsSession {
        let verifier = TeamsPKCE.verifier()
        let state = TeamsPKCE.randomString(bytes: 16)
        let server = LoopbackCallbackServer(expectedState: state)
        let port = try await server.start()
        defer { server.stop() }
        let redirect = "http://localhost:\(port)"
        openBrowser(TeamsRequests.authorizeURL(clientID: clientID, tenant: tenant, redirectURI: redirect, state: state, challenge: TeamsPKCE.challenge(for: verifier)))

        let answer = try await server.callback(timeout: waitSeconds)
        guard let code = answer["code"], !code.isEmpty else {
            throw TeamsDecoding.signInError(code: answer["error"], description: answer["error_description"], subcode: answer["error_subcode"])
        }
        let data = try await token(TeamsRequests.tokenRequest(clientID: clientID, tenant: tenant, code: code, redirectURI: redirect, verifier: verifier), refreshing: false)
        return try TeamsDecoding.session(from: data, clientID: clientID, tenant: tenant, now: now())
    }

    func refresh(_ old: TeamsSession) async throws -> TeamsSession {
        guard let refreshToken = old.refreshToken else { throw TeamsError.unauthorized }
        let data = try await token(TeamsRequests.refreshRequest(clientID: old.clientID, tenant: old.tenant, refreshToken: refreshToken), refreshing: true)
        return try TeamsDecoding.session(from: data, clientID: old.clientID, tenant: old.tenant, previousRefreshToken: refreshToken, now: now())
    }

    private func token(_ request: URLRequest, refreshing: Bool) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TeamsError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw TeamsError.unreadable }
        if (200..<300).contains(http.statusCode) { return data }
        let failure = TeamsDecoding.oauthError(from: data)
        // A refresh Microsoft turns down means the access was withdrawn or ran out: sign in again.
        if refreshing, ["invalid_grant", "interaction_required", "consent_required", "login_required"].contains(failure.code ?? "") {
            throw TeamsError.unauthorized
        }
        if http.statusCode >= 500 { throw TeamsError.server }
        throw TeamsDecoding.signInError(code: failure.code, description: failure.description)
    }
}

/// A tiny web server on this Mac's loopback only (nothing else on the network can reach it) that catches the one request
/// Microsoft's sign-in page sends the browser back with, answers it with a "you can close this tab" page, and stops.
final class LoopbackCallbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "island.teams.loopback")
    private let expectedState: String
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var outcome: Result<[String: String], Error>?

    /// Only ever touched on `queue`, one callback at a time.
    private final class Once: @unchecked Sendable { var done = false }

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    /// Starts listening on any free port and returns it.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw TeamsError.signIn("Island couldn't open a local port to finish the sign-in.")
        }
        self.listener = listener
        return try await withCheckedThrowingContinuation { (started: CheckedContinuation<UInt16, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    started.resume(returning: listener.port?.rawValue ?? 0)
                case .failed:
                    once.done = true
                    started.resume(throwing: TeamsError.signIn("Island couldn't open a local port to finish the sign-in."))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    /// Waits for the browser's return trip: the query items Microsoft sent (a `code`, or an `error`).
    func callback(timeout: TimeInterval) async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<[String: String], Error>) in
                queue.async {
                    if let outcome = self.outcome {
                        waiting.resume(with: outcome)
                        return
                    }
                    self.continuation = waiting
                    self.queue.asyncAfter(deadline: .now() + timeout) {
                        self.finish(.failure(TeamsError.signIn("The sign-in wasn't finished in time. Try again.")))
                    }
                }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        guard outcome == nil else { return }
        outcome = result
        continuation?.resume(with: result)
        continuation = nil
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
            guard let self, let data, error == nil, let text = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let line = text.components(separatedBy: "\r\n").first ?? ""
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET", let components = URLComponents(string: "http://localhost" + parts[1]) else {
                self.respond(connection, status: "400 Bad Request", body: "Bad request.")
                return
            }
            var items: [String: String] = [:]
            for item in components.queryItems ?? [] { if let value = item.value { items[item.name] = value } }
            // Anything else the browser asks for (the page's icon, say) is not the sign-in coming back.
            guard items["code"] != nil || items["error"] != nil else {
                self.respond(connection, status: "404 Not Found", body: "Not found.")
                return
            }
            // A return trip that is not for this sign-in is refused and the wait goes on.
            guard items["state"] == self.expectedState else {
                self.respond(connection, status: "400 Bad Request", body: "This isn't the sign-in Island is waiting for.")
                return
            }
            self.respond(connection, status: "200 OK", body: items["code"] != nil
                ? "You're signed in. You can close this tab and go back to Island."
                : "Island didn't get the sign-in. Go back to Island to see why.")
            self.finish(.success(items))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let page = """
        <!doctype html><meta charset="utf-8"><title>Island</title>
        <body style="font:16px -apple-system,sans-serif;background:#000;color:#fff;display:grid;place-items:center;height:100vh;margin:0">
        <p>\(body)</p></body>
        """
        let bytes = Data(page.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }
}
