import Foundation
import Testing
@testable import IslandCore

// MARK: Signing in

@Test func pkceChallengeMatchesTheSpecificationsOwnExample() {
    // RFC 7636, appendix B.
    #expect(TeamsPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test func aFreshPkceVerifierIsLongEnoughUsesOnlyAllowedCharactersAndIsNeverRepeated() {
    let first = TeamsPKCE.verifier(), second = TeamsPKCE.verifier()
    #expect((43...128).contains(first.count))
    #expect(first.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil)
    #expect(first != second)
}

@Test func theClientIdAndTenantAreCheckedBeforeAnythingOpens() throws {
    let id = "0A1B2C3D-1234-5678-9ABC-DEF012345678"
    // The tenant may be left empty (work accounts), named, or a company domain; the id is tidied.
    let empty = try TeamsRequests.validated(clientID: "  \(id) \n", tenant: "").get()
    #expect(empty.clientID == id.lowercased() && empty.tenant == "organizations")
    #expect(try TeamsRequests.validated(clientID: id, tenant: "Contoso.com").get().tenant == "contoso.com")
    #expect(try TeamsRequests.validated(clientID: id, tenant: "72F988BF-86F1-41AF-91AB-2D7CD011DB47").get().tenant == "72f988bf-86f1-41af-91ab-2d7cd011db47")
    #expect(try TeamsRequests.validated(clientID: id, tenant: "common").get().tenant == "common")

    for bad in ["", "not a guid", "0a1b2c3d", "https://entra.microsoft.com"] {
        if case .failure(.signIn(let why)) = TeamsRequests.validated(clientID: bad, tenant: "") { #expect(why.contains("Application (client) ID")) } else { Issue.record("accepted \(bad)") }
    }
    for bad in ["a b", "evil.com/oauth", "x", "-bad.com", "foo/../bar"] {
        if case .success = TeamsRequests.validated(clientID: id, tenant: bad) { Issue.record("accepted tenant \(bad)") }
    }
}

@Test func theSignInPageAsksForReadingOnlyAndProvesItselfWithPkce() throws {
    let url = TeamsRequests.authorizeURL(clientID: "cid", tenant: "contoso.com", redirectURI: "http://localhost:5555", state: "st", challenge: "ch")
    #expect(url.host == "login.microsoftonline.com")
    #expect(url.path == "/contoso.com/oauth2/v2.0/authorize")
    let items = Dictionary(uniqueKeysWithValues: try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).map { ($0.name, $0.value ?? "") })
    #expect(items["client_id"] == "cid" && items["response_type"] == "code" && items["response_mode"] == "query")
    #expect(items["redirect_uri"] == "http://localhost:5555" && items["state"] == "st")
    #expect(items["code_challenge"] == "ch" && items["code_challenge_method"] == "S256")
    #expect(items["scope"] == "offline_access User.Read Chat.Read")
    #expect(items["client_secret"] == nil)
    // Never asks to send or to see more than the person's own chats.
    #expect(!TeamsRequests.scopes.contains("Send") && !TeamsRequests.scopes.contains("ReadWrite") && !TeamsRequests.scopes.contains(".All"))
}

@Test func theTokenRequestsAreFormPostsWithTheProofAndNoSecret() throws {
    let exchange = TeamsRequests.tokenRequest(clientID: "cid", tenant: "organizations", code: "a.b-c_d", redirectURI: "http://localhost:5555", verifier: "ver")
    #expect(exchange.httpMethod == "POST")
    #expect(exchange.url?.absoluteString == "https://login.microsoftonline.com/organizations/oauth2/v2.0/token")
    #expect(exchange.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let body = String(decoding: try #require(exchange.httpBody), as: UTF8.self)
    #expect(body.contains("grant_type=authorization_code") && body.contains("code_verifier=ver") && body.contains("code=a.b-c_d"))
    #expect(body.contains("redirect_uri=http%3A%2F%2Flocalhost%3A5555"))
    #expect(body.contains("scope=offline_access%20User.Read%20Chat.Read"))
    #expect(!body.contains("client_secret"))

    let refresh = TeamsRequests.refreshRequest(clientID: "cid", tenant: "organizations", refreshToken: "r/t+k")
    let refreshBody = String(decoding: try #require(refresh.httpBody), as: UTF8.self)
    #expect(refreshBody.contains("grant_type=refresh_token") && refreshBody.contains("refresh_token=r%2Ft%2Bk"))
}

@Test func aTokenAnswerBecomesASessionAndARefreshKeepsTheEarlierRefreshToken() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let full = Data(#"{"token_type":"Bearer","scope":"Chat.Read","expires_in":3599,"access_token":"AT","refresh_token":"RT"}"#.utf8)
    let session = try TeamsDecoding.session(from: full, clientID: "cid", tenant: "t", now: now)
    #expect(session.accessToken == "AT" && session.refreshToken == "RT" && session.expiresAt == now.addingTimeInterval(3599))
    #expect(session.isValid(at: now) && !session.isValid(at: now.addingTimeInterval(3550)))   // not within the last 90 s

    let noRefresh = Data(#"{"access_token":"AT2","expires_in":"1800"}"#.utf8)   // some answers send the lifetime as text
    let again = try TeamsDecoding.session(from: noRefresh, clientID: "cid", tenant: "t", previousRefreshToken: "RT", now: now)
    #expect(again.refreshToken == "RT" && again.expiresAt == now.addingTimeInterval(1800))
    #expect(throws: TeamsError.unreadable) { try TeamsDecoding.session(from: Data(#"{"error":"x"}"#.utf8), clientID: "c", tenant: "t", now: now) }
}

@Test func signInFailuresAreExplainedWithWhatToChange() {
    func explain(_ code: String, _ text: String) -> TeamsError { TeamsDecoding.signInError(code: code, description: "AADSTS\(text)\r\nTrace ID: abc\r\nCorrelation ID: def") }

    if case .needsApproval(let detail) = explain("access_denied", "65001: The user or administrator has not consented to use the application.") {
        #expect(detail?.contains("not consented") == true && detail?.contains("Trace ID") == false)
    } else { Issue.record("65001 should need approval") }
    if case .needsApproval = explain("invalid_grant", "90094: The grant requires admin permission.") {} else { Issue.record("90094 should need approval") }

    if case .signIn(let why) = explain("invalid_client", "7000218: The request body must contain the following parameter: 'client_assertion' or 'client_secret'.") {
        #expect(why.contains("Mobile and desktop applications") && why.contains("public client"))
    } else { Issue.record("7000218") }
    if case .signIn(let why) = explain("invalid_request", "50011: The redirect URI 'http://localhost:1' does not match.") { #expect(why.contains("http://localhost")) } else { Issue.record("50011") }
    if case .signIn(let why) = explain("unauthorized_client", "700016: Application with identifier 'x' was not found in the directory.") { #expect(why.contains("Application (client) ID")) } else { Issue.record("700016") }
    if case .signIn(let why) = explain("interaction_required", "53003: Access has been blocked by Conditional Access policies.") { #expect(why.contains("Conditional Access")) } else { Issue.record("53003") }
    #expect(TeamsDecoding.signInError(code: "access_denied", description: "The user cancelled") == .signIn("The sign-in was cancelled."))
    // What a real browser brought back when the person left Microsoft's page: no description, only a subcode.
    if case .signIn(let why) = TeamsDecoding.signInError(code: "access_denied", description: nil, subcode: "cancel") {
        #expect(why.contains("Need admin approval") && why.contains("pressed Cancel"))
    } else { Issue.record("cancel subcode") }
    // Microsoft's real text, all on one line: the trace and correlation ids are not for the person.
    let real = "AADSTS9002313: Invalid request. Request is malformed or invalid. Trace ID: 2f6d42d6-42c4 Correlation ID: 2a23db4e-b22c Timestamp: 2026-11-08 04:52:32Z"
    #expect(TeamsDecoding.signInError(code: "invalid_grant", description: real) == .signIn("AADSTS9002313: Invalid request. Request is malformed or invalid."))
    if case .needsApproval(let detail) = TeamsDecoding.signInError(code: "access_denied", description: "AADSTS65001: The user or administrator has not consented to use the application with ID 'x'. Trace ID: 1 Correlation ID: 2 Timestamp: 3") {
        #expect(detail == "AADSTS65001: The user or administrator has not consented to use the application with ID 'x'.")
    } else { Issue.record("65001 on one line") }
    if case .signIn(let why) = TeamsDecoding.signInError(code: nil, description: nil) { #expect(!why.isEmpty) } else { Issue.record("empty") }
}

@Test func graphFailuresMapToSpecificErrors() {
    func error(_ status: Int, _ body: String = "", _ headers: [String: String] = [:]) -> TeamsError {
        TeamsDecoding.graphError(status: status, body: Data(body.utf8), headers: headers, now: Date(timeIntervalSince1970: 100))
    }
    #expect(error(401) == .unauthorized)
    #expect(error(403, #"{"error":{"code":"Forbidden","message":"Insufficient privileges."}}"#) == .forbidden("Insufficient privileges."))
    #expect(error(404) == .notFound)
    #expect(error(400, #"{"error":{"code":"BadRequest","message":"Invalid $orderby."}}"#) == .validation("Invalid $orderby."))
    #expect(error(429, "", ["retry-after": "12"]) == .rateLimited(until: Date(timeIntervalSince1970: 112)))
    #expect(error(500) == .server)
}

// MARK: Asking Microsoft Graph

@Test func graphRequestsCarryTheTokenAndNothingThatWrites() throws {
    let me = TeamsRequests.account(token: "TOK")
    #expect(me.httpMethod == nil || me.httpMethod == "GET")
    #expect(me.value(forHTTPHeaderField: "Authorization") == "Bearer TOK")
    #expect(me.url?.absoluteString.hasPrefix("https://graph.microsoft.com/v1.0/me?") == true)

    let rich = try #require(TeamsRequests.chats(token: "T", withLatestMessage: true).url?.absoluteString)
    #expect(rich.contains("$expand=members,lastMessagePreview") && rich.contains("$orderby=lastMessagePreview/createdDateTime%20desc") && rich.contains("$top=50"))
    let plain = try #require(TeamsRequests.chats(token: "T", withLatestMessage: false).url?.absoluteString)
    #expect(plain.contains("$expand=members") && !plain.contains("lastMessagePreview"))

    let messages = try #require(TeamsRequests.messages(token: "T", chatID: "19:abc@unq.gbl.spaces").url?.absoluteString)
    #expect(messages == "https://graph.microsoft.com/v1.0/me/chats/19:abc@unq.gbl.spaces/messages?$top=40")

    // A "next page" address is only followed when it is Microsoft Graph's own.
    #expect(TeamsRequests.nextPage(token: "T", url: URL(string: "https://graph.microsoft.com/v1.0/me/chats?$skiptoken=x")!) != nil)
    #expect(TeamsRequests.nextPage(token: "T", url: URL(string: "https://evil.example/steal")!) == nil)
    #expect(TeamsRequests.nextPage(token: "T", url: URL(string: "http://graph.microsoft.com/v1.0/me/chats")!) == nil)
}

private let chatsFixture = Data(#"""
{
  "@odata.context": "https://graph.microsoft.com/v1.0/$metadata#chats(members(),lastMessagePreview())",
  "@odata.nextLink": "https://graph.microsoft.com/v1.0/me/chats?$skiptoken=abc",
  "value": [
    {
      "id": "19:ravi_me@unq.gbl.spaces", "topic": null, "chatType": "oneOnOne",
      "lastUpdatedDateTime": "2026-11-01T08:00:00.000Z",
      "webUrl": "https://teams.microsoft.com/l/chat/19%3Aravi_me%40unq.gbl.spaces/0?tenantId=t",
      "members": [
        {"@odata.type": "#microsoft.graph.aadUserConversationMember", "displayName": "Charvit Z", "userId": "me-id", "email": "charvit@x.com"},
        {"@odata.type": "#microsoft.graph.aadUserConversationMember", "displayName": "Ravi Shah", "userId": "ravi-id", "email": "ravi@x.com"}
      ],
      "lastMessagePreview": {
        "id": "1", "createdDateTime": "2026-11-07T10:15:30.1234567Z", "isDeleted": false, "messageType": "message",
        "from": {"user": {"id": "ravi-id", "displayName": "Ravi Shah", "userIdentityType": "aadUser"}},
        "body": {"contentType": "html", "content": "<p>Can you look at <a href=\"https://github.com/acme/finance/pull/757\">https://github.com/acme/finance/pull/757</a> please?</p>"}
      }
    },
    {
      "id": "19:team@thread.v2", "topic": "Finance squad", "chatType": "group", "lastUpdatedDateTime": "2026-10-30T08:00:00Z", "webUrl": null,
      "members": [{"displayName": "Charvit Z", "userId": "me-id"}, {"displayName": "Ana", "userId": "a"}, {"displayName": "Raj", "userId": "r"}],
      "lastMessagePreview": {"id": "2", "createdDateTime": "2026-11-06T09:00:00Z", "messageType": "systemEventMessage", "body": {"contentType": "html", "content": "<systemEventMessage/>"}}
    },
    {
      "id": "19:nameless@thread.v2", "topic": "", "chatType": "group",
      "members": [{"displayName": "Charvit Z", "userId": "me-id"}, {"displayName": "Ana", "userId": "a"}, {"displayName": "Raj", "userId": "r"}, {"displayName": "Sam", "userId": "s"}, {"displayName": "Kim", "userId": "k"}]
    },
    {"id": "19:meeting_x@thread.v2", "topic": "Sprint planning", "chatType": "meeting", "members": []},
    {"topic": "no id at all"}
  ]
}
"""#.utf8)

@Test func chatsAreReadWithWhoIsInThemAndTheirNewestMessage() throws {
    let (chats, next) = try TeamsDecoding.chats(from: chatsFixture)
    #expect(chats.map(\.id) == ["19:ravi_me@unq.gbl.spaces", "19:team@thread.v2", "19:nameless@thread.v2", "19:meeting_x@thread.v2"])   // one with no id is dropped
    #expect(next?.absoluteString == "https://graph.microsoft.com/v1.0/me/chats?$skiptoken=abc")

    let ravi = chats[0]
    #expect(ravi.kind == .oneOnOne && ravi.members.count == 2)
    #expect(ravi.title(me: "me-id") == "Ravi Shah")                     // the other person, not "me"
    #expect(ravi.webURL?.host == "teams.microsoft.com")
    let preview = try #require(ravi.preview)
    #expect(preview.sender == "Ravi Shah" && preview.mentionsPullRequest)
    #expect(preview.text == "Can you look at https://github.com/acme/finance/pull/757 please?")
    let expected = Date(timeIntervalSince1970: 1_762_510_530 + 365 * 86400 + 0.123)
    #expect(abs(try #require(preview.date).timeIntervalSince(expected)) < 0.01)   // seven fraction digits are read
    #expect(ravi.lastActivity == preview.date)

    #expect(chats[1].title(me: "me-id") == "Finance squad")             // a topic wins
    #expect(chats[1].preview == nil)                                    // a notice ("Ana was added") is no preview
    #expect(chats[1].lastActivity == TeamsDecoding.date("2026-10-30T08:00:00Z"))
    #expect(chats[2].title(me: "me-id") == "Ana, Raj, Sam +1")          // no topic: the others, a few of them
    #expect(chats[3].kind == .meeting && chats[3].title(me: "me-id") == "Sprint planning")
}

@Test func theChatListCanBeFilteredByNameOrMember() throws {
    let chats = try TeamsDecoding.chats(from: chatsFixture).chats
    #expect(chats.filter { $0.matches("ravi", me: "me-id") }.map(\.id) == ["19:ravi_me@unq.gbl.spaces"])
    #expect(chats.filter { $0.matches("  SQUAD ", me: "me-id") }.map(\.id) == ["19:team@thread.v2"])
    #expect(chats.filter { $0.matches("kim", me: "me-id") }.map(\.id) == ["19:nameless@thread.v2"])   // a member, not in the title
    #expect(chats.filter { $0.matches("", me: "me-id") }.count == 4)
}

private let messagesFixture = Data(#"""
{
  "value": [
    {"id": "m3", "messageType": "message", "createdDateTime": "2026-11-07T10:20:00Z", "deletedDateTime": null,
     "from": {"user": {"id": "me-id", "displayName": "Charvit Z"}},
     "body": {"contentType": "text", "content": "on it, see https://github.com/acme/finance/pull/757/files"}},
    {"id": "m1", "messageType": "message", "createdDateTime": "2026-11-07T10:15:30.12Z", "deletedDateTime": null,
     "from": {"user": {"id": "ravi-id", "displayName": "Ravi Shah"}},
     "body": {"contentType": "html", "content": "<p><at id=\"0\">Charvit</at> review please &amp; thanks<br>PR: <a href=\"https://nam.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Facme%2Ffinance%2Fpull%2F757&amp;data=x\">link</a></p>"},
     "attachments": []},
    {"id": "m2", "messageType": "message", "createdDateTime": "2026-11-07T10:16:00Z",
     "from": {"application": {"id": "gh", "displayName": "GitHub"}},
     "body": {"contentType": "html", "content": "<attachment id=\"c1\"></attachment>"},
     "attachments": [{"id": "c1", "contentType": "application/vnd.microsoft.card.adaptive", "contentUrl": null, "name": null,
                      "content": "{\"body\":[{\"type\":\"TextBlock\",\"text\":\"New PR\"}],\"actions\":[{\"type\":\"Action.OpenUrl\",\"url\":\"https:\\/\\/github.com\\/acme\\/api\\/pull\\/12\"}]}"}]},
    {"id": "sys", "messageType": "systemEventMessage", "createdDateTime": "2026-11-07T10:00:00Z", "body": {"contentType": "html", "content": "<systemEventMessage/>"}},
    {"id": "gone", "messageType": "message", "createdDateTime": "2026-11-07T10:01:00Z", "deletedDateTime": "2026-11-07T10:02:00Z", "body": {"contentType": "html", "content": "<p>oops</p>"}},
    {"id": "empty", "messageType": "message", "createdDateTime": "2026-11-07T10:03:00Z", "body": {"contentType": "html", "content": "<p></p>"}},
    {"id": "file", "messageType": "message", "createdDateTime": "2026-11-07T10:04:00Z", "body": {"contentType": "html", "content": "<attachment id=\"f\"></attachment>"},
     "attachments": [{"id": "f", "contentType": "reference", "contentUrl": "https://x.sharepoint.com/a.pdf", "name": "report.pdf"}]}
  ]
}
"""#.utf8)

@Test func messagesAreReadOldestFirstWithNoticesAndDeletedOnesLeftOut() throws {
    let messages = try TeamsDecoding.messages(from: messagesFixture).messages
    #expect(messages.map(\.id) == ["file", "m1", "m2", "m3"])

    let m1 = try #require(messages.first { $0.id == "m1" })
    #expect(m1.senderName == "Ravi Shah" && m1.senderID == "ravi-id")
    #expect(m1.text == "@Charvit review please & thanks\nPR: link")
    #expect(m1.runs.last?.url?.absoluteString == "https://github.com/acme/finance/pull/757")   // the mail filter's wrapper is removed
    #expect(m1.pullRequests.map(\.label) == ["acme/finance #757"])

    // GitHub's own Teams app posts a card (no link in the words): the pull request is found inside it.
    let card = try #require(messages.first { $0.id == "m2" })
    #expect(card.senderName == "GitHub" && card.senderID == nil && card.runs.isEmpty)
    #expect(card.pullRequests.map(\.label) == ["acme/api #12"])
    #expect(card.pullRequests.first?.url.absoluteString == "https://github.com/acme/api/pull/12")

    let plain = try #require(messages.first { $0.id == "m3" })
    #expect(plain.runs.compactMap(\.url).map(\.absoluteString) == ["https://github.com/acme/finance/pull/757/files"])   // a bare address becomes a link
    #expect(plain.pullRequests.map(\.label) == ["acme/finance #757"])

    let file = try #require(messages.first { $0.id == "file" })
    #expect(file.runs.isEmpty && file.attachmentNames == ["report.pdf"])
}

@Test func timesWithAnyNumberOfFractionDigitsOrNoneAreRead() {
    let expected = Date(timeIntervalSince1970: 1_762_510_530)
    #expect(TeamsDecoding.date("2025-11-07T10:15:30Z") != nil)
    #expect(TeamsDecoding.date("2026-11-07T10:15:30Z") == expected.addingTimeInterval(365 * 86400))
    #expect(TeamsDecoding.date("2026-11-07T10:15:30.5Z") == expected.addingTimeInterval(365 * 86400 + 0.5))
    #expect(TeamsDecoding.date("2026-11-07T10:15:30.1234567Z") != nil)
    #expect(TeamsDecoding.date("yesterday") == nil)
}

@Test func theAccountIsReadAndAMissingNameFallsBackToTheAddress() throws {
    let named = try TeamsDecoding.account(from: Data(#"{"id":"u1","displayName":"Charvit Z","mail":"c@x.com","userPrincipalName":"c@x.onmicrosoft.com"}"#.utf8))
    #expect(named == TeamsAccount(id: "u1", displayName: "Charvit Z", mail: "c@x.com"))
    let bare = try TeamsDecoding.account(from: Data(#"{"id":"u1","displayName":" ","userPrincipalName":"c@x.onmicrosoft.com"}"#.utf8))
    #expect(bare.displayName == "c@x.onmicrosoft.com")
    #expect(throws: TeamsError.unreadable) { try TeamsDecoding.account(from: Data("{}".utf8)) }
}

// MARK: Words and links

@Test func htmlMessagesBecomePlainWordsWithTheirLinksKept() {
    func text(_ html: String) -> String { TeamsRichText.runs(html: html).map(\.text).joined() }
    #expect(text("<p>one</p><p>two</p>") == "one\ntwo")
    #expect(text("a<br>b<br/>c") == "a\nb\nc")
    #expect(text("<p>Hi <at id=\"0\">Ana Lee</at>!</p>") == "Hi @Ana Lee!")
    #expect(text("<emoji id=\"smile\" alt=\"😀\" title=\"Smile\"></emoji> ok") == "😀 ok")
    #expect(text("a &lt;b&gt; &amp; &quot;c&quot; &#39;d&#39; &#x41;&nbsp;e") == "a <b> & \"c\" 'd' A e")
    #expect(text("<ul><li>x</li><li>y</li></ul>") == "• x\n• y")
    #expect(text("<img src=\"x.png\">") == "[image]")
    #expect(text("1 < 2 and 3 > 2") == "1 < 2 and 3 > 2")                    // a stray "<" is only text
    #expect(text("<p>a</p><p></p><p></p><p></p><p>b</p>") == "a\n\nb")        // never a run of blank lines
    #expect(text("a\n  b") == "a b")                                         // a line break inside HTML text is a space
}

@Test func onlyWebAddressesAreEverMadeClickable() {
    let runs = TeamsRichText.runs(html: #"<a href="javascript:alert(1)">x</a> <a href="file:///etc/passwd">y</a> <a href="https://example.com/a?b=1&amp;c=2">z</a> <a href="mailto:a@b.c">m</a>"#)
    #expect(runs.compactMap(\.url).map(\.absoluteString) == ["https://example.com/a?b=1&c=2"])

    let plain = TeamsRichText.runs(plain: "see https://github.com/a/b/pull/1 and mail a@b.com or www.example.org today")
    #expect(plain.compactMap(\.url).map(\.absoluteString).contains("https://github.com/a/b/pull/1"))
    #expect(plain.compactMap(\.url).allSatisfy { $0.scheme == "https" || $0.scheme == "http" })       // the mail address is not a link
    #expect(plain.map(\.text).joined() == "see https://github.com/a/b/pull/1 and mail a@b.com or www.example.org today")
}

@Test func aMailFilterWrapperAroundAnAddressIsRemoved() throws {
    let wrapped = try #require(URL(string: "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Fo%2Fr%2Fpull%2F5%3Ffiles%3D1&data=05%7C01"))
    #expect(TeamsRichText.unwrapped(wrapped).absoluteString == "https://github.com/o/r/pull/5?files=1")
    let normal = try #require(URL(string: "https://github.com/o/r/pull/5"))
    #expect(TeamsRichText.unwrapped(normal) == normal)
    let notAWebAddress = try #require(URL(string: "https://x.safelinks.protection.outlook.com/?url=javascript%3Aalert(1)"))
    #expect(TeamsRichText.unwrapped(notAWebAddress) == notAWebAddress)   // a wrapper around something that is not a web address is left alone
}

@Test func pullRequestsAreFoundOnceEachAndOnlyRealOnes() {
    let runs = TeamsRichText.runs(html: """
        <a href="https://github.com/Acme/Api/pull/12">one</a> <a href="https://github.com/acme/api/pull/12/files">same again</a>
        <a href="https://github.com/acme/api/issues/9">an issue</a> <a href="https://github.com/acme/api">the repo</a>
        <a href="https://gitlab.com/acme/api/pull/3">elsewhere</a> <a href="https://github.com/acme/api/pull/13">two</a>
        """)
    let found = TeamsRichText.pullRequestLinks(runs: runs, attachmentTexts: ["https:\\/\\/github.com\\/acme\\/api\\/pull\\/13", "{\"u\":\"https://github.com/z/y/pull/1\"}"])
    #expect(found.map(\.label) == ["Acme/Api #12", "acme/api #13", "z/y #1"])
    #expect(found.first?.url.absoluteString == "https://github.com/Acme/Api/pull/12")
}

@Test func messageTimesReadNaturally() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US_POSIX")
    func at(_ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9, minute: 5))! }
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 15))!   // a Saturday
    // macOS writes a narrow no-break space before AM/PM; the text below uses a normal space.
    func label(_ date: Date, time: Bool = false) -> String {
        TeamsTime.label(date, now: now, withTime: time, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ")
    }
    #expect(label(at(11, 7)) == "9:05 AM")                    // today: the time
    #expect(label(at(11, 6)) == "Yesterday")
    #expect(label(at(11, 6), time: true) == "Yesterday 9:05 AM")
    #expect(label(at(11, 3)) == "Tue")                        // this week: the weekday
    #expect(label(at(11, 1)) == "Sun")
    #expect(label(at(10, 20)) == "Oct 20")                    // older: the date
    #expect(label(at(10, 20), time: true) == "Oct 20 9:05 AM")
}
