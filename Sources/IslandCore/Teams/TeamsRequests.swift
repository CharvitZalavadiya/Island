import CryptoKit
import Foundation
import Security

/// The requests Island sends to Microsoft: signing in (the browser, then the token exchange) and reading chats.
/// Reading only: the app asks for `Chat.Read`, never for permission to send.
public enum TeamsRequests {
    /// What Island asks to be allowed. `Chat.Read` (read the person's own chats) and `User.Read` (who they are) are ones a
    /// person can usually approve for themselves; `offline_access` keeps the sign-in alive without signing in again.
    public static let scopes = "offline_access User.Read Chat.Read"
    static let graph = "https://graph.microsoft.com/v1.0"

    /// The place to register the app, for the connect screen.
    public static let registrationURL = URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade/quickStartType~/null/sourceType/Microsoft_AAD_IAM")!

    // MARK: What the person typed

    /// A checked client id and tenant, or what is wrong with them.
    public static func validated(clientID: String, tenant: String) -> Result<(clientID: String, tenant: String), TeamsError> {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: id) != nil else {
            return .failure(.signIn("That doesn't look like an Application (client) ID. It is 36 characters like 0a1b2c3d-1234-5678-9abc-def012345678, shown on the app's Overview page in Entra."))
        }
        let rawTenant = tenant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = rawTenant.isEmpty ? "organizations" : rawTenant
        let wellKnown = ["organizations", "common", "consumers"]
        let looksLikeDomain = name.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$"#, options: .regularExpression) != nil
        guard wellKnown.contains(name) || UUID(uuidString: name) != nil || looksLikeDomain else {
            return .failure(.signIn("That doesn't look like a tenant. Leave it empty, or use the Directory (tenant) ID or your company's domain, like example.com."))
        }
        return .success((id.lowercased(), name))
    }

    // MARK: Signing in (OAuth with PKCE, the way desktop apps do it)

    private static func authority(_ tenant: String) -> String { "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0" }

    /// The page the browser opens to sign in. Microsoft sends the browser back to `redirectURI` (a port on this Mac) with a code.
    public static func authorizeURL(clientID: String, tenant: String, redirectURI: String, state: String, challenge: String) -> URL {
        var components = URLComponents(string: authority(tenant) + "/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    public static func tokenRequest(clientID: String, tenant: String, code: String, redirectURI: String, verifier: String) -> URLRequest {
        form(authority(tenant) + "/token", [
            ("client_id", clientID), ("scope", scopes), ("code", code), ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"), ("code_verifier", verifier),
        ])
    }

    public static func refreshRequest(clientID: String, tenant: String, refreshToken: String) -> URLRequest {
        form(authority(tenant) + "/token", [
            ("client_id", clientID), ("scope", scopes), ("refresh_token", refreshToken), ("grant_type", "refresh_token"),
        ])
    }

    private static func form(_ address: String, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&").data(using: .utf8)
        request.timeoutInterval = 30
        return request
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? text
    }

    // MARK: Reading chats (Microsoft Graph)

    public static func account(token: String) -> URLRequest {
        graphRequest("/me?$select=id,displayName,mail,userPrincipalName", token: token)
    }

    /// The person's chats. The fuller question asks for each chat's newest message and orders by it; if Microsoft will not
    /// answer that one the simpler one still gives the chats and who is in them.
    public static func chats(token: String, withLatestMessage: Bool) -> URLRequest {
        if withLatestMessage {
            return graphRequest("/me/chats?$expand=members,lastMessagePreview&$orderby=lastMessagePreview/createdDateTime%20desc&$top=50", token: token)
        }
        return graphRequest("/me/chats?$expand=members&$top=50", token: token)
    }

    /// A later page of a list, from the address Microsoft gave (only ever Microsoft Graph's own).
    public static func nextPage(token: String, url: URL) -> URLRequest? {
        guard url.scheme == "https", url.host?.lowercased() == "graph.microsoft.com" else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return request
    }

    public static func messages(token: String, chatID: String) -> URLRequest {
        // A chat id looks like 19:abc@unq.gbl.spaces; the colon stays as Microsoft writes it, and nothing like "/" can get through.
        let id = chatID.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:@")) ?? chatID
        return graphRequest("/me/chats/\(id)/messages?$top=40", token: token)
    }

    private static func graphRequest(_ path: String, token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: graph + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return request
    }
}

/// The secret one-time proof a desktop app uses instead of a password-like client secret (RFC 7636).
public enum TeamsPKCE {
    public static func randomString(bytes: Int) -> String {
        var data = Data(count: bytes)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        if status != errSecSuccess { data = Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }) }
        return base64URL(data)
    }

    public static func verifier() -> String { randomString(bytes: 64) }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
