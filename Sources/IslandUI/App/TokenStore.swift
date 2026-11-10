import Foundation
import Security

/// Where Island keeps a person's access token for an outside service (Todoist, GitHub): somewhere safe, and nowhere else.
protocol TokenStoring: AnyObject {
    func load() -> String?
    /// Returns false when the token could not be kept.
    func save(_ token: String) -> Bool
    func delete()
}

/// A secret kept in a file that only the signed-in user can read, in Island's own data folder (a folder with permissions 700
/// holding files with permissions 600, which is how ssh, git and the GitHub CLI keep theirs).
///
/// Island does NOT use the Keychain, on purpose. macOS lets an app use a Keychain item without asking only while the app has
/// the same code signature as the app that saved it. Island is signed without a paid Apple developer account ("ad-hoc"), and an
/// ad-hoc signature is different in every build, so macOS would ask the person for their Mac password, once per saved token,
/// after every update (and for anyone who ever ran a differently signed copy). Nobody should be asked that by a small app.
/// A file survives updates and asks nothing. The cost is real and should be said plainly: any program running as the same
/// user can read it, which is also true of a Keychain item once its owner has been allowed to; and it is not encrypted beyond
/// what FileVault already does for the disk. With a paid Developer ID signature (stable across updates) `KeychainTokenStore`
/// below becomes usable again and is the better place.
final class FileTokenStore: TokenStoring {
    private let directory: URL
    private let file: URL

    /// `service` names the secret ("github", "todoist", "teams"): each gets its own file in `directory`.
    init(directory: URL, service: String) {
        self.directory = directory
        self.file = directory.appendingPathComponent(Self.fileName(for: service))
    }

    /// A name that cannot lead out of the folder, whatever it is given.
    static func fileName(for service: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let cleaned = String(service.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return cleaned.isEmpty ? "secret" : cleaned
    }

    func load() -> String? {
        let fileManager = FileManager.default
        // Never read through a link someone put in its place.
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path), attributes[.type] as? FileAttributeType == .typeRegular,
              let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        // A file that somehow became readable by others is closed up again.
        if let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 != 0 {
            chmod(file.path, 0o600)
        }
        return text
    }

    func save(_ token: String) -> Bool {
        guard prepareDirectory() else { return false }
        let temporary = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]) else {
            return false
        }
        chmod(temporary.path, 0o600)
        // One atomic step that replaces what was there (a link included, without following it): there is never a moment with a
        // half-written token, or with one that others can read.
        guard rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
        return true
    }

    func delete() {
        try? FileManager.default.removeItem(at: file)
    }

    private func prepareDirectory() -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return false
        }
        chmod(directory.path, 0o700)
        // Secrets do not belong in a backup or on another Mac.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = directory
        try? mutable.setResourceValues(values)
        return true
    }
}

/// NOT USED by Island (see `FileTokenStore` for why): a token in the Mac's Keychain. It is kept for the day Island is signed with
/// a stable Developer ID certificate, when the Keychain stops asking for a password after every update. A test makes sure
/// nothing else uses it in the meantime.
final class KeychainTokenStore: TokenStoring {
    private let service: String
    private let account: String

    /// `suffix` names the service ("todoist", "github"): each gets its own Keychain item, under the app's own name.
    convenience init(forService suffix: String) {
        self.init(service: (Bundle.main.bundleIdentifier ?? "Island") + "." + suffix)
    }

    init(service: String, account: String = "api-token") {
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
        item[kSecAttrLabel as String] = "Island: access token (\(service))"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(identity as CFDictionary)
    }
}
