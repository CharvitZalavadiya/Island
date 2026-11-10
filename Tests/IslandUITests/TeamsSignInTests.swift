import CryptoKit
import Foundation
import Testing
import IslandCore
@testable import IslandUI

/// Answers requests for the test's session so no test ever talks to Microsoft.
private final class StubMicrosoft: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, Data) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [(URL, Data)] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.lock.lock()
        Self.seen.append((request.url!, body))
        let handler = Self.handler
        Self.lock.unlock()
        let (status, data) = handler?(request, body) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// What a browser would do: fetch an address on this Mac's own loopback.
private func browse(_ address: String) async throws -> (status: Int, page: String) {
    let session = URLSession(configuration: .ephemeral)
    let (data, response) = try await session.data(from: URL(string: address)!)
    return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
}

@Test func theSignInListenerHandsOverTheCodeTheBrowserBringsBack() async throws {
    let server = LoopbackCallbackServer(expectedState: "S1")
    let port = try await server.start()
    #expect(port > 0)
    let waiting = Task { try await server.callback(timeout: 10) }

    let page = try await browse("http://127.0.0.1:\(port)/?code=the-code&state=S1&session_state=x")
    #expect(page.status == 200 && page.page.contains("signed in"))
    let answer = try await waiting.value
    #expect(answer["code"] == "the-code")
    server.stop()
}

@Test func theSignInListenerIgnoresEverythingThatIsNotTheSignInComingBack() async throws {
    let server = LoopbackCallbackServer(expectedState: "RIGHT")
    let port = try await server.start()
    let waiting = Task { try await server.callback(timeout: 10) }

    #expect(try await browse("http://127.0.0.1:\(port)/favicon.ico").status == 404)                 // the page icon is no sign-in
    #expect(try await browse("http://127.0.0.1:\(port)/?code=stolen&state=WRONG").status == 400)     // not this sign-in
    #expect(try await browse("http://127.0.0.1:\(port)/?code=nostate").status == 400)
    let ok = try await browse("http://127.0.0.1:\(port)/?code=real&state=RIGHT")                      // the wait went on through all that
    #expect(ok.status == 200)
    #expect(try await waiting.value["code"] == "real")
    server.stop()
}

@Test func aRefusedSignInComesBackAsAnErrorNotACode() async throws {
    let server = LoopbackCallbackServer(expectedState: "S")
    let port = try await server.start()
    let waiting = Task { try await server.callback(timeout: 10) }
    let page = try await browse("http://127.0.0.1:\(port)/?error=access_denied&error_description=AADSTS65001%3A%20not%20consented&state=S")
    #expect(page.status == 200 && !page.page.contains("AADSTS"))   // the page never repeats what the address said
    let answer = try await waiting.value
    #expect(answer["code"] == nil && answer["error"] == "access_denied")
    if case .needsApproval = TeamsDecoding.signInError(code: answer["error"], description: answer["error_description"]) {} else { Issue.record("should need approval") }
    server.stop()
}

@Test func leavingMicrosoftsPageWithoutAllowingAccessComesBackWithTheSubcode() async throws {
    // Exactly the address a real browser was sent back to (seen in a screenshot): an error, a subcode and the state, no description.
    let server = LoopbackCallbackServer(expectedState: "nSl4Ddfb46GbxpLjiHvB0A")
    let port = try await server.start()
    let waiting = Task { try await server.callback(timeout: 10) }
    let page = try await browse("http://127.0.0.1:\(port)/?error=access_denied&error_subcode=cancel&state=nSl4Ddfb46GbxpLjiHvB0A")
    #expect(page.status == 200)
    let answer = try await waiting.value
    #expect(answer["error"] == "access_denied" && answer["error_subcode"] == "cancel" && answer["code"] == nil)
    if case .signIn(let why) = TeamsDecoding.signInError(code: answer["error"], description: answer["error_description"], subcode: answer["error_subcode"]) {
        #expect(why.contains("Need admin approval"))
    } else { Issue.record("should explain") }
    server.stop()
}

@Test func aSignInThatIsNeverFinishedTimesOutAndOneThatIsCancelledStops() async throws {
    let slow = LoopbackCallbackServer(expectedState: "S")
    _ = try await slow.start()
    do {
        _ = try await slow.callback(timeout: 0.2)
        Issue.record("should have timed out")
    } catch let error as TeamsError {
        if case .signIn(let why) = error { #expect(why.contains("in time")) } else { Issue.record("wrong error \(error)") }
    }

    let cancelled = LoopbackCallbackServer(expectedState: "S")
    _ = try await cancelled.start()
    let task = Task { try await cancelled.callback(timeout: 30) }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("should have been cancelled")
    } catch is CancellationError {}
}

/// The tests that answer for Microsoft share one stand-in, so they run one at a time.
@Suite(.serialized) struct TeamsStubbedMicrosoftTests {
    private final class Box: @unchecked Sendable { var challenge = ""; var redirect = "" }

    private func makeAuth(now: @escaping @Sendable () -> Date = { Date() }, wait: TimeInterval = 10) -> LoopbackTeamsAuth {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubMicrosoft.self]
        return LoopbackTeamsAuth(session: URLSession(configuration: configuration), now: now, waitSeconds: wait)
    }

    private func answer(_ handler: @escaping (URLRequest, Data) -> (Int, Data)) {
        StubMicrosoft.lock.lock()
        StubMicrosoft.seen = []
        StubMicrosoft.handler = handler
        StubMicrosoft.lock.unlock()
    }

    private func formFields(_ body: Data) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            fields[parts[0]] = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
        }
        return fields
    }

    @Test func theWholeSignInWorksAgainstAStandInForMicrosoftAndTheProofMatches() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        answer { _, _ in (200, Data(#"{"token_type":"Bearer","expires_in":3599,"access_token":"ACCESS","refresh_token":"REFRESH"}"#.utf8)) }
        let promised = Box()

        // The "browser": read the sign-in address, and come back to the redirect address with a code, as Microsoft would.
        let session = try await makeAuth(now: { now }).signIn(clientID: "cid", tenant: "contoso.com") { signInURL in
            let items = Dictionary(uniqueKeysWithValues: URLComponents(url: signInURL, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            promised.challenge = items["code_challenge"] ?? ""
            promised.redirect = items["redirect_uri"] ?? ""
            let local = promised.redirect.replacingOccurrences(of: "localhost", with: "127.0.0.1")
            Task { _ = try? await browse("\(local)/?code=CODE123&state=\(items["state"]!)") }
        }
        #expect(session.accessToken == "ACCESS" && session.refreshToken == "REFRESH")
        #expect(session.clientID == "cid" && session.tenant == "contoso.com" && session.expiresAt == now.addingTimeInterval(3599))

        StubMicrosoft.lock.lock()
        let seen = StubMicrosoft.seen
        StubMicrosoft.lock.unlock()
        let exchange = try #require(seen.first { $0.0.path.hasSuffix("/token") })
        #expect(exchange.0.host == "login.microsoftonline.com" && exchange.0.path == "/contoso.com/oauth2/v2.0/token")
        let body = formFields(exchange.1)
        #expect(body["code"] == "CODE123" && body["grant_type"] == "authorization_code" && body["client_id"] == "cid")
        #expect(body["redirect_uri"] == promised.redirect && promised.redirect.hasPrefix("http://localhost:"))
        #expect(body["client_secret"] == nil)
        // The proof sent now must be the one the sign-in page was promised.
        let verifier = try #require(body["code_verifier"])
        #expect((43...128).contains(verifier.count))
        #expect(!promised.challenge.isEmpty && TeamsPKCE.challenge(for: verifier) == promised.challenge)
    }

    @Test func aRefusedRefreshMeansSignInAgainButATemporaryFailureDoesNot() async throws {
        let auth = makeAuth()
        let old = TeamsSession(clientID: "cid", tenant: "t", accessToken: "old", refreshToken: "RT", expiresAt: .distantPast)

        answer { _, _ in (400, Data(#"{"error":"invalid_grant","error_description":"AADSTS70008: The refresh token has expired."}"#.utf8)) }
        await #expect(throws: TeamsError.unauthorized) { try await auth.refresh(old) }

        answer { _, _ in (503, Data()) }
        await #expect(throws: TeamsError.server) { try await auth.refresh(old) }

        answer { _, _ in (200, Data(#"{"access_token":"new","expires_in":3600}"#.utf8)) }
        let fresh = try await auth.refresh(old)
        #expect(fresh.accessToken == "new" && fresh.refreshToken == "RT")   // the refresh token that was not replaced stays

        await #expect(throws: TeamsError.unauthorized) { try await auth.refresh(TeamsSession(clientID: "c", tenant: "t", accessToken: "a", refreshToken: nil, expiresAt: .distantPast)) }
    }

    @Test func aTokenExchangeMicrosoftRejectsExplainsWhatToChange() async throws {
        let auth = makeAuth()
        answer { _, _ in (401, Data(#"{"error":"invalid_client","error_description":"AADSTS7000218: The request body must contain the following parameter: 'client_assertion' or 'client_secret'."}"#.utf8)) }
        do {
            _ = try await auth.signIn(clientID: "cid", tenant: "organizations") { signInURL in
                let items = Dictionary(uniqueKeysWithValues: URLComponents(url: signInURL, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
                let local = items["redirect_uri"]!.replacingOccurrences(of: "localhost", with: "127.0.0.1")
                Task { _ = try? await browse("\(local)/?code=C&state=\(items["state"]!)") }
            }
            Issue.record("should have failed")
        } catch TeamsError.signIn(let why) {
            #expect(why.contains("Mobile and desktop applications"))
        }
    }
}
