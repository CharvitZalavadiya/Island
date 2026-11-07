import Foundation
import Security

/// Where Island keeps the person's Todoist token: somewhere safe, and nowhere else.
protocol TodoistTokenStoring: AnyObject {
    func load() -> String?
    /// Returns false when the token could not be kept.
    func save(_ token: String) -> Bool
    func delete()
}

/// The token in the Mac's Keychain, the place macOS keeps passwords. It never goes into a settings file, and the Keychain
/// (not Island) is what guards it. Another app cannot read it without the person's permission.
final class KeychainTodoistTokenStore: TodoistTokenStoring {
    private let service: String
    private let account: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "Island") + ".todoist", account: String = "api-token") {
        self.service = service
        self.account = account
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) -> Bool {
        delete()   // replaces any earlier token
        var item = identity
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrLabel as String] = "Island: Todoist token"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(identity as CFDictionary)
    }
}
