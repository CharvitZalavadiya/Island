import AppKit
import Foundation
import Testing
import IslandCore
@testable import IslandUI

private func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("island-secrets-\(UUID().uuidString)", isDirectory: true)
}

private func mode(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

@Test func aSavedTokenComesBackAndALaterOneReplacesIt() {
    let store = FileTokenStore(directory: tempFolder(), service: "github")
    #expect(store.load() == nil)                                           // nothing yet (a new person: no prompt, nothing found)
    #expect(store.save("ghp_first"))
    #expect(store.load() == "ghp_first")
    #expect(store.save("ghp_second"))
    #expect(store.load() == "ghp_second")
    store.delete()
    #expect(store.load() == nil)
    store.delete()                                                         // deleting what is not there is fine
}

@Test func aTokenSurvivesTheAppBeingClosedAndOpenedAgainOrUpdated() {
    let folder = tempFolder()
    #expect(FileTokenStore(directory: folder, service: "github").save("ghp_abc"))
    #expect(FileTokenStore(directory: folder, service: "github").load() == "ghp_abc")        // a new run of the app, a new build: no prompt, no loss
}

@Test func theFolderAndTheFileAreReadableByTheUserAloneAndKeptOutOfBackups() throws {
    let folder = tempFolder()
    let store = FileTokenStore(directory: folder, service: "github")
    #expect(store.save("ghp_secret"))
    #expect(mode(folder) == 0o700)                                         // nobody else can even look inside
    #expect(mode(folder.appendingPathComponent("github")) == 0o600)        // nor read the file
    let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)                           // and it is not swept into a backup
    #expect((try FileManager.default.contentsOfDirectory(atPath: folder.path)).sorted() == ["github"])   // no temporary file left behind
}

@Test func aFolderOrFileThatWasLeftOpenToOthersIsClosedUpAgain() {
    let folder = tempFolder()
    let store = FileTokenStore(directory: folder, service: "github")
    #expect(store.save("ghp_secret"))
    let file = folder.appendingPathComponent("github")
    chmod(file.path, 0o644)
    chmod(folder.path, 0o755)
    #expect(store.load() == "ghp_secret")                                  // reading tightens the file...
    #expect(mode(file) == 0o600)
    #expect(store.save("ghp_next") && mode(folder) == 0o700)               // ...and saving tightens the folder
}

@Test func differentServicesKeepTheirOwnTokens() {
    let folder = tempFolder()
    let github = FileTokenStore(directory: folder, service: "github"), todoist = FileTokenStore(directory: folder, service: "todoist")
    #expect(github.save("g") && todoist.save("t"))
    #expect(github.load() == "g" && todoist.load() == "t")
    github.delete()
    #expect(github.load() == nil && todoist.load() == "t")
}

@Test func aServiceNameCanNeverLeadOutOfTheFolder() {
    #expect(FileTokenStore.fileName(for: "github") == "github" && FileTokenStore.fileName(for: "teams-app") == "teams-app")
    #expect(FileTokenStore.fileName(for: "../../etc/passwd") == "------etc-passwd")
    #expect(FileTokenStore.fileName(for: "a/b") == "a-b" && FileTokenStore.fileName(for: "GitHub") == "github")
    #expect(FileTokenStore.fileName(for: "") == "secret" && FileTokenStore.fileName(for: ".hidden") == "-hidden")
    let folder = tempFolder()
    let store = FileTokenStore(directory: folder, service: "../outside")
    #expect(store.save("x"))
    #expect(!FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().appendingPathComponent("outside").path))
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) == ["---outside"])
}

@Test func aLinkPutInTheTokensPlaceIsNeitherReadNorWrittenThrough() throws {
    let folder = tempFolder()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let target = folder.deletingLastPathComponent().appendingPathComponent("island-victim-\(UUID().uuidString).txt")
    try "do not touch".write(to: target, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: target) }
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("github"), withDestinationURL: target)

    let store = FileTokenStore(directory: folder, service: "github")
    #expect(store.load() == nil)                                           // not read through the link
    #expect(store.save("ghp_real"))
    #expect((try String(contentsOf: target, encoding: .utf8)) == "do not touch")           // the link's target is untouched
    #expect(store.load() == "ghp_real")                                    // the link itself was replaced by a real file
}

@Test func emptyAndOddContentsAreHandled() throws {
    let folder = tempFolder()
    let store = FileTokenStore(directory: folder, service: "github")
    #expect(store.save("") && store.load() == nil)                         // an empty token is no token
    #expect(store.save("tökén-日本語-🔑") && store.load() == "tökén-日本語-🔑")
    try Data([0xff, 0xfe, 0x00]).write(to: folder.appendingPathComponent("github"))        // damaged contents (not text)
    #expect(store.load() == nil)
    #expect(store.save("fresh") && store.load() == "fresh")                // and saving over it works
}

@Test func aFolderThatCannotBeWrittenMeansSavingSaysNoInsteadOfPretending() {
    let folder = tempFolder()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    chmod(folder.path, 0o500)
    defer { chmod(folder.path, 0o700); try? FileManager.default.removeItem(at: folder) }
    // (prepareDirectory tightens the folder to 0700 for its owner, so a folder owned by the user can be written again; what must
    // never happen is a "true" without a token saved.)
    let store = FileTokenStore(directory: folder, service: "github")
    let saved = store.save("ghp_x")
    #expect(saved == (store.load() == "ghp_x"))
}

// MARK: Nothing may ask the Keychain

private let sourcesRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")

@Test func noPartOfIslandUsesTheKeychainSoNobodyIsEverAskedForAPassword() throws {
    let walker = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    for case let url as URL in walker where url.pathExtension == "swift" && url.lastPathComponent != "TokenStore.swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        // (Importing Security alone is fine: the Teams sign-in uses it for random numbers.)
        let keychainCalls = ["KeychainTokenStore", "SecItemAdd", "SecItemCopyMatching", "SecItemUpdate", "SecItemDelete", "kSecClass"]
        if keychainCalls.contains(where: text.contains) { offenders.append(url.lastPathComponent) }
    }
    #expect(offenders.isEmpty, "these files use the Keychain: \(offenders)")
}

// MARK: A brand-new install

@MainActor private func emptyFolder() -> URL { tempFolder() }

@Test @MainActor func aBrandNewInstallStartsCompletelyEmptyWithNothingOfAnyonesBookmarksOrAccounts() async {
    _ = NSApplication.shared
    // The browser: no bookmarks, one blank tab, tabs on the side with the list hidden.
    let browser = BrowserController(store: FileStore(url: tempFolder().appendingPathComponent("browser.json"), defaultValue: BrowserState()))
    #expect(browser.tabs.bookmarks.isEmpty)
    #expect(browser.tabs.open.count == 1 && browser.tabs.open[0].url == nil && browser.tabs.open[0].title.isEmpty)
    #expect(!browser.tabs.sidebarOpen && !browser.tabs.tabsOnTop && !browser.hasPage)
    #expect(BrowserState().tabs == nil && BrowserState().lastAddress == nil)

    // The accounts: nothing saved anywhere, so nothing is connected and nothing is read from the Mac's Keychain.
    let secrets = emptyFolder()
    let github = GitHubController(tokens: FileTokenStore(directory: secrets, service: "github"))
    await github.start()
    #expect(github.connection == .disconnected && github.isReady)
    let todoist = TodoistController(tokens: FileTokenStore(directory: secrets, service: "todoist"))
    await todoist.start()
    #expect(todoist.connection == .disconnected)
    let teams = TeamsController(sessions: FileTokenStore(directory: secrets, service: "teams"), config: FileTokenStore(directory: secrets, service: "teams-app"))
    await teams.start()
    #expect(teams.connection == .disconnected && teams.clientID.isEmpty && teams.chats.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: secrets.path))                      // not even an empty secrets folder is made until something is saved

    // The settings: the defaults, the update check on, nothing ever checked.
    let settings = Settings()
    #expect(settings.tabOrder.isEmpty && settings.checkForUpdates && settings.lastUpdateCheck == nil && settings.tasksSource == "local")
}
