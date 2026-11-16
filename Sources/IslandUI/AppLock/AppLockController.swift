import AppKit
import Foundation
import Observation
import IslandCore

/// Where the App lock password's hash is kept.
protocol AppLockPasswordStoring: AnyObject {
    /// The saved record, or nil when there is none OR it is damaged (App lock then counts the password as not set).
    func load() -> AppLockPasswordRecord?
    func save(_ record: AppLockPasswordRecord) -> Bool
}

/// The record as a file in Island's private data folder (see `FileTokenStore` for why a file and not the Keychain).
final class FileAppLockPasswordStore: AppLockPasswordStoring {
    private let tokens: TokenStoring

    init(tokens: TokenStoring) { self.tokens = tokens }

    func load() -> AppLockPasswordRecord? {
        guard let text = tokens.load(), let record = try? JSONDecoder().decode(AppLockPasswordRecord.self, from: Data(text.utf8)),
            record.isValid
        else { return nil }
        return record
    }

    func save(_ record: AppLockPasswordRecord) -> Bool {
        guard let data = try? JSONEncoder().encode(record), let text = String(data: data, encoding: .utf8) else { return false }
        return tokens.save(text)
    }
}

/// What the cover shows and does. The controller decides; this only puts windows on the screen.
@MainActor
protocol AppLockPresenting: AnyObject {
    var isShowing: Bool { get }
    /// Covers `covered` (screen frames); the box to type in goes on `card`. Takes the keyboard.
    func show(covering covered: [CGRect], card: CGRect)
    /// Takes the cover away. Everything it did is undone: nothing is left on the screen.
    func hide()
    /// The controller whose state the cover shows.
    func attach(_ controller: AppLockController)
}

/// App lock: apps the person chose ask for Touch ID or the password when they are opened.
///
/// HOW IT STAYS SAFE. The whole lock is ONE thing: a cover window that Island puts over the app while it is in front. So:
///  - Quit Island (or it crashes) and the cover is gone and every app opens freely. Nothing else holds an app: no app is ever
///    frozen, quit or changed (`AppLockWorkspace` cannot even do that), and nothing keeps running after Island.
///  - The cover is there only while the locked app is in front. Going to ANY other app (⌘Tab, the Dock, Force Quit), Esc, "Not
///    now", or the app quitting, removes it.
///  - It has its own "Quit Island" button, and the Mac's own password always works, so forgetting the password or a broken
///    Touch ID never traps anyone.
///  - When something is wrong (no password saved, a damaged password file, no screen) the lock does nothing instead of keeping
///    the person out.
@Observable
@MainActor
final class AppLockController {
    struct Request: Equatable {
        var pid: Int32
        var bundleID: String
        var name: String
    }

    struct App: Equatable, Identifiable {
        var id: String
        var name: String
    }

    enum PasswordResult: Equatable {
        case saved, tooShort, doesNotMatch, couldNotSave
        /// The settings are locked: the person has not shown it is them yet.
        case locked
    }

    // MARK: What the views show

    /// The app that is being asked about, while the cover is up.
    private(set) var request: Request?
    /// What went wrong, in words, for the cover or the settings.
    private(set) var message: String?
    private(set) var isUsingTouchID = false
    private(set) var isAskingMacPassword = false
    /// While set and in the future, wrong tries are paused.
    private(set) var pausedUntil: Date?
    private(set) var hasPassword: Bool
    private(set) var touchIDAvailable = false
    /// The person has shown it is them, so the settings may be changed (until the settings are closed).
    private(set) var settingsUnlocked = false

    /// The lock is on, and has a password to check against.
    var isEnabled: Bool { settings.settings.appLockEnabled && hasPassword }
    /// It will really cover something.
    var isProtecting: Bool { isEnabled && !settings.settings.appLockApps.isEmpty }
    /// The settings must be unlocked before they can be changed.
    var needsUnlockForSettings: Bool { isEnabled && !settingsUnlocked }
    var touchIDOffered: Bool { settings.settings.appLockTouchID && touchIDAvailable }
    var lockedApps: [App] {
        settings.settings.appLockApps.map { App(id: $0, name: settings.settings.appLockNames[$0] ?? $0) }
    }
    var relock: AppLockRelock { settings.settings.appLockRelockChoice }

    // MARK: Parts

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let passwords: AppLockPasswordStoring
    @ObservationIgnored private let authenticator: LockAuthenticating
    @ObservationIgnored private let workspace: AppLockWorkspace
    @ObservationIgnored private let presenter: AppLockPresenting
    @ObservationIgnored private let screens: () -> [CGRect]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let ownPID: Int32
    @ObservationIgnored private let ownBundleID: String?
    @ObservationIgnored private let quit: () -> Void

    @ObservationIgnored private var policy = AppLockPolicy()
    @ObservationIgnored private var attempts = AppLockAttempts()
    @ObservationIgnored private var stopObserving: (() -> Void)?
    /// The locked app the person is using now (opened with the password), so leaving it can be noticed.
    @ObservationIgnored private var frontLockedPID: Int32?
    /// The last app the person was in that is not locked: where "Not now" goes back to.
    @ObservationIgnored private var previous: RunningApp?
    /// Counts the covers and settings sessions, so an answer that arrives after the person left is ignored.
    @ObservationIgnored private var generation = 0

    init(
        settings: SettingsStore, passwords: AppLockPasswordStoring, authenticator: LockAuthenticating, workspace: AppLockWorkspace,
        presenter: AppLockPresenting, screens: @escaping () -> [CGRect] = { NSScreen.screens.map(\.frame) },
        now: @escaping () -> Date = Date.init, ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        ownBundleID: String? = Bundle.main.bundleIdentifier, quit: @escaping () -> Void = { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    ) {
        self.settings = settings
        self.passwords = passwords
        self.authenticator = authenticator
        self.workspace = workspace
        self.presenter = presenter
        self.screens = screens
        self.now = now
        self.ownPID = ownPID
        self.ownBundleID = ownBundleID
        self.quit = quit
        hasPassword = passwords.load() != nil
        presenter.attach(self)
    }

    // MARK: Starting and stopping

    func start() {
        guard stopObserving == nil else { return }
        touchIDAvailable = authenticator.touchIDAvailable
        refreshPassword()
        stopObserving = workspace.observe { [weak self] event in self?.handle(event) }
        // The app that is in front now may be a locked one.
        if let front = workspace.frontmost { activated(front) }
    }

    /// Island is quitting: nothing is left behind (there is nothing to restore: no other app was ever changed).
    func shutdown() {
        stopObserving?()
        stopObserving = nil
        dismissCover()
    }

    private func handle(_ event: AppLockWorkspaceEvent) {
        switch event {
        case .activated(let app):
            activated(app)
        case .terminated(let pid):
            policy.quit(pid: pid)
            if frontLockedPID == pid { frontLockedPID = nil }
            if previous?.pid == pid { previous = nil }
            if request?.pid == pid { dismissCover() }
        case .locked:
            policy.forgetAll()
            frontLockedPID = nil
        }
    }

    // MARK: Which app is in front

    private func activated(_ app: RunningApp) {
        // The helpers macOS uses to ask for a fingerprint or a password are not "another app".
        if app.pid != ownPID, !app.isRegular { return }
        // A password file that was deleted or damaged since is noticed now, so the lock never covers with nothing to check against.
        if settings.settings.appLockEnabled { refreshPassword() }
        policy.relock = relock
        if let front = frontLockedPID, front != app.pid {
            policy.leftFront(pid: front, at: now())
            frontLockedPID = nil
        }
        // Island itself came to the front: it is the cover taking the keyboard, or the person using the island.
        if app.pid == ownPID { return }

        let locked = isProtecting && app.bundleID.map { settings.settings.appLockApps.contains($0) } == true
        if let request, app.pid != request.pid, !locked {
            walkAway()                                  // the person went to another app: the cover goes, and so does what it hid
        }
        guard locked, let bundleID = app.bundleID else {
            if !isLockedApp(app) { previous = app }
            return
        }
        frontLockedPID = app.pid
        if policy.comesToFront(pid: app.pid, now: now()) { present(Request(pid: app.pid, bundleID: bundleID, name: app.name)) }
    }

    private func isLockedApp(_ app: RunningApp) -> Bool { app.bundleID.map { settings.settings.appLockApps.contains($0) } == true }

    // MARK: The cover

    private func present(_ new: Request) {
        guard let plan = AppLockCoverage.plan(windows: workspace.windowFrames(of: new.pid), screens: screens()) else { return }
        if request != new {
            authenticator.cancel()
            generation += 1
            message = nil
            isUsingTouchID = false
            isAskingMacPassword = false
            request = new
        }
        presenter.show(covering: plan.covered, card: plan.card)
        if request == new, !isUsingTouchID, touchIDOffered, message == nil { tryTouchID() }
    }

    /// Takes the cover away and forgets what it was asking. The app it covered is left as it is.
    private func dismissCover() {
        authenticator.cancel()
        generation += 1
        request = nil
        message = nil
        isUsingTouchID = false
        isAskingMacPassword = false
        if presenter.isShowing { presenter.hide() }
    }

    /// The person went elsewhere (or said "Not now"): the cover goes, and the locked app is hidden (⌘H) so that taking the
    /// cover away does not show it.
    private func walkAway() {
        guard let request else { return }
        dismissCover()
        if workspace.isRunning(pid: request.pid) { workspace.hide(pid: request.pid) }
    }

    /// "Not now": back to the app the person was in before.
    func notNow() {
        guard request != nil else { return }
        let back = previous
        walkAway()
        if let back, workspace.isRunning(pid: back.pid) { workspace.bringToFront(pid: back.pid) }
    }

    /// "Quit Island": the lock only exists while Island runs, so this is the way out of any trouble.
    func quitIsland() { quit() }

    private func openRequestedApp() {
        guard let request else { return }
        policy.opened(pid: request.pid)
        frontLockedPID = request.pid
        attempts.succeeded()
        pausedUntil = nil
        dismissCover()
        workspace.bringToFront(pid: request.pid)
    }

    // MARK: Asking who is there

    func submitPassword(_ text: String) {
        guard request != nil else { return }
        if passwordIsRight(text) { openRequestedApp() }
    }

    func tryTouchID() {
        guard let request, touchIDOffered, !isUsingTouchID else { return }
        isUsingTouchID = true
        let session = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await authenticator.authenticateWithTouchID(reason: "open \(request.name)")
            // The person may have gone elsewhere while the dialog was up: then nothing it says counts any more.
            guard session == generation, self.request == request else { return }
            isUsingTouchID = false
            switch result {
            case .success: openRequestedApp()
            case .cancelled: break
            case .failed(let text), .unavailable(let text): message = text
            }
        }
    }

    func useMacPassword() {
        guard let request, !isAskingMacPassword else { return }
        isAskingMacPassword = true
        let session = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await authenticator.authenticateWithMacPassword(reason: "open \(request.name)")
            guard session == generation, self.request == request else { return }
            isAskingMacPassword = false
            switch result {
            case .success: openRequestedApp()
            case .cancelled: break
            case .failed(let text), .unavailable(let text): message = text
            }
        }
    }

    /// Checks the typed password, with a pause after too many wrong ones.
    private func passwordIsRight(_ text: String) -> Bool {
        guard let record = passwords.load() else {
            refresh()                                   // the password is gone: the lock does nothing rather than keep anyone out
            return false
        }
        let current = now()
        let wait = attempts.wait(now: current)
        guard wait == 0 else {
            message = "Too many wrong tries. Wait \(Int(wait.rounded(.up))) seconds."
            return false
        }
        if AppLockPassword.matches(text, record: record) {
            attempts.succeeded()
            pausedUntil = nil
            message = nil
            return true
        }
        attempts.failed(now: current)
        let after = attempts.wait(now: current)
        pausedUntil = after > 0 ? current.addingTimeInterval(after) : nil
        message = after > 0 ? "That is not the password. Wait \(Int(after.rounded(.up))) seconds." : "That is not the password."
        return false
    }

    // MARK: The settings

    /// The settings were closed: they ask again next time.
    func lockSettings() {
        authenticator.cancel()
        generation += 1
        settingsUnlocked = false
        isUsingTouchID = false
        isAskingMacPassword = false
        message = nil
    }

    func unlockSettings(password text: String) {
        if passwordIsRight(text) { settingsUnlocked = true }
    }

    func unlockSettingsWithTouchID() { unlockSettings(using: { [authenticator] in await authenticator.authenticateWithTouchID(reason: "change App lock settings") }, touch: true) }

    func unlockSettingsWithMacPassword() { unlockSettings(using: { [authenticator] in await authenticator.authenticateWithMacPassword(reason: "change App lock settings") }, touch: false) }

    private func unlockSettings(using ask: @escaping () async -> LockAuthResult, touch: Bool) {
        guard touch ? (touchIDOffered && !isUsingTouchID) : !isAskingMacPassword else { return }
        if touch { isUsingTouchID = true } else { isAskingMacPassword = true }
        let session = generation
        Task { @MainActor [weak self] in
            let result = await ask()
            guard let self, session == generation else { return }
            if touch { isUsingTouchID = false } else { isAskingMacPassword = false }
            switch result {
            case .success:
                settingsUnlocked = true
                message = nil
            case .cancelled: break
            case .failed(let text), .unavailable(let text): message = text
            }
        }
    }

    /// Whether the settings may be changed now: always while the lock is off (nothing is protected then), and otherwise only
    /// once the person has shown it is them.
    private var canChange: Bool { !isEnabled || settingsUnlocked }

    /// Turns the lock on or off. On needs a password; off needs the settings unlocked. Returns whether it is as asked.
    @discardableResult
    func setEnabled(_ on: Bool) -> Bool {
        if on {
            guard hasPassword else {
                message = "Set a password first."
                return false
            }
        } else if !canChange {
            message = "Unlock the settings to turn App lock off."
            return false
        }
        settings.update { $0.appLockEnabled = on }
        policy.forgetAll()
        refresh()
        return isEnabled == on
    }

    func setPassword(_ new: String, repeated: String) -> PasswordResult {
        guard canChange else { return .locked }
        if let problem = AppLockPassword.problem(newPassword: new, repeated: repeated) {
            return problem == .tooShort ? .tooShort : .doesNotMatch
        }
        guard let record = AppLockPassword.makeRecord(for: new), passwords.save(record) else { return .couldNotSave }
        let first = !hasPassword
        hasPassword = true
        settingsUnlocked = true
        attempts.succeeded()
        pausedUntil = nil
        message = nil
        // Setting the first password is asking for the lock to be on.
        if first { settings.update { $0.appLockEnabled = true } }
        policy.forgetAll()
        refresh()
        return .saved
    }

    @discardableResult
    func addApp(bundleID: String, name: String) -> Bool {
        guard AppLockRules.canLock(bundleID, island: ownBundleID) else {
            message = "\(name) cannot be locked."
            return false
        }
        message = nil
        if !settings.settings.appLockApps.contains(bundleID) {
            settings.update {
                $0.appLockApps.append(bundleID)
                $0.appLockNames[bundleID] = name
            }
        }
        refresh()
        return true
    }

    /// Adds the app at `url` (an `.app` chosen in a file chooser).
    @discardableResult
    func addApp(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            message = "That is not an app Island can lock."
            return false
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
        return addApp(bundleID: id, name: name)
    }

    func removeApp(_ id: String) {
        guard canChange else {
            message = "Unlock the settings to remove an app."
            return
        }
        settings.update {
            $0.appLockApps.removeAll { $0 == id }
            $0.appLockNames[id] = nil
        }
        refresh()
    }

    func setRelock(_ choice: AppLockRelock) {
        guard canChange else { return }
        settings.update { $0.appLockRelock = choice.rawValue }
    }

    func setTouchID(_ on: Bool) {
        guard canChange else { return }
        settings.update { $0.appLockTouchID = on }
    }

    /// Running apps that could be added, for the "Add app" menu.
    func candidates() -> [App] {
        let locked = Set(settings.settings.appLockApps)
        var seen = Set<String>()
        return workspace.runningApps().compactMap { app in
            guard let id = app.bundleID, app.pid != ownPID, AppLockRules.canLock(id, island: ownBundleID), !locked.contains(id),
                seen.insert(id).inserted
            else { return nil }
            return App(id: id, name: app.name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Keeping the state true

    private func refreshPassword() { hasPassword = passwords.load() != nil }

    /// After anything changed: the cover goes if there is nothing to ask for any more.
    private func refresh() {
        refreshPassword()
        if let request, !isProtecting || !settings.settings.appLockApps.contains(request.bundleID) { dismissCover() }
        // An app that was just added is NOT covered while the person is still in it (they are setting this up): it asks the
        // next time it comes to the front.
    }
}
