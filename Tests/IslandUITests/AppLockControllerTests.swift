import AppKit
import Foundation
import LocalAuthentication
import SwiftUI
import Testing
import IslandCore
@testable import IslandUI

// App lock, tried without any real window, finger or other app: made-up apps come to the front, and what comes out is whether a
// cover is up, which app was hidden or brought forward, and what the settings allow. The most important tests are the ones
// that say the lock can never trap the person (see "never traps" below).

private let slack = RunningApp(pid: 100, bundleID: "com.tinyspeck.slackmacgap", name: "Slack", isRegular: true)
private let mail = RunningApp(pid: 200, bundleID: "com.apple.mail", name: "Mail", isRegular: true)
private let notes = RunningApp(pid: 300, bundleID: "com.apple.Notes", name: "Notes", isRegular: true)
private let island = RunningApp(pid: 1, bundleID: "com.example.Island", name: "Island", isRegular: false)
/// The little program macOS shows its Touch ID dialog from: not an app the person went to.
private let touchDialog = RunningApp(pid: 900, bundleID: "com.apple.LocalAuthenticationRemoteUI", name: "Touch ID", isRegular: false)
private let screenOne = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let screenTwo = CGRect(x: 1440, y: 0, width: 1440, height: 900)

private let lockPassword = "open-sesame"

private final class FakeClock {
    var time = Date(timeIntervalSince1970: 1_000_000)
}

private final class Counter {
    var value = 0
}

@MainActor private final class FakeWorkspace: AppLockWorkspace {
    var frontmost: RunningApp?
    var apps: [RunningApp] = []
    var running: Set<Int32> = [100, 200, 300]
    var windows: [Int32: [CGRect]] = [100: [CGRect(x: 100, y: 100, width: 800, height: 600)]]
    private(set) var hidden: [Int32] = []
    private(set) var raised: [Int32] = []
    private var handler: (@MainActor (AppLockWorkspaceEvent) -> Void)?
    private(set) var stops = 0
    var isObserving: Bool { handler != nil }

    func runningApps() -> [RunningApp] { apps }
    func isRunning(pid: Int32) -> Bool { running.contains(pid) }
    func windowFrames(of pid: Int32) -> [CGRect] { windows[pid] ?? [] }
    func hide(pid: Int32) { hidden.append(pid) }
    func bringToFront(pid: Int32) { raised.append(pid) }
    func observe(_ handler: @escaping @MainActor (AppLockWorkspaceEvent) -> Void) -> () -> Void {
        self.handler = handler
        return { [weak self] in
            self?.handler = nil
            self?.stops += 1
        }
    }
    func send(_ event: AppLockWorkspaceEvent) { handler?(event) }
}

@MainActor private final class FakeAuthenticator: LockAuthenticating {
    var touchIDAvailable = false
    /// What the dialogs answer at once; nil makes them wait until `answerTouch` / `answerMac` is called.
    var touchResult: LockAuthResult? = .cancelled
    var macResult: LockAuthResult? = .cancelled
    private var touchWaiters: [CheckedContinuation<LockAuthResult, Never>] = []
    private var macWaiters: [CheckedContinuation<LockAuthResult, Never>] = []
    private(set) var touchCalls = 0
    private(set) var macCalls = 0
    private(set) var cancels = 0

    func authenticateWithTouchID(reason: String) async -> LockAuthResult {
        touchCalls += 1
        if let touchResult { return touchResult }
        return await withCheckedContinuation { touchWaiters.append($0) }
    }
    func authenticateWithMacPassword(reason: String) async -> LockAuthResult {
        macCalls += 1
        if let macResult { return macResult }
        return await withCheckedContinuation { macWaiters.append($0) }
    }
    func cancel() { cancels += 1 }
    /// Answers the oldest question still waiting.
    func answerTouch(_ result: LockAuthResult) { if !touchWaiters.isEmpty { touchWaiters.removeFirst().resume(returning: result) } }
    func answerMac(_ result: LockAuthResult) { if !macWaiters.isEmpty { macWaiters.removeFirst().resume(returning: result) } }
}

@MainActor private final class FakeOverlay: AppLockPresenting {
    private(set) var isShowing = false
    private(set) var shown: [(covered: [CGRect], card: CGRect)] = []
    private(set) var hides = 0
    func attach(_ controller: AppLockController) {}
    func show(covering covered: [CGRect], card: CGRect) {
        isShowing = true
        shown.append((covered, card))
    }
    func hide() {
        isShowing = false
        hides += 1
    }
}

private final class FakePasswords: AppLockPasswordStoring {
    var record: AppLockPasswordRecord?
    var saveFails = false
    func load() -> AppLockPasswordRecord? { record }
    func save(_ record: AppLockPasswordRecord) -> Bool {
        guard !saveFails else { return false }
        self.record = record
        return true
    }
}

@MainActor private final class Rig {
    let controller: AppLockController
    let settings: SettingsStore
    let workspace = FakeWorkspace()
    let authenticator = FakeAuthenticator()
    let overlay = FakeOverlay()
    let passwords = FakePasswords()
    let clock = FakeClock()
    private let quits = Counter()
    var quitCalls: Int { quits.value }

    init(
        enabled: Bool = true, apps: [String] = ["com.tinyspeck.slackmacgap", "com.apple.mail"], password: String? = lockPassword,
        touchIDAvailable: Bool = false, relock: AppLockRelock = .everyTime, frontmost: RunningApp? = nil, start: Bool = true
    ) {
        var initial = IslandCore.Settings()
        initial.appLockEnabled = enabled
        initial.appLockApps = apps
        initial.appLockNames = ["com.tinyspeck.slackmacgap": "Slack", "com.apple.mail": "Mail"]
        initial.appLockRelock = relock.rawValue
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("applock-\(UUID())/settings.json")
        settings = SettingsStore(store: FileStore(url: url, defaultValue: initial))
        passwords.record = password.flatMap { AppLockPassword.makeRecord(for: $0, rounds: 10_000) }
        authenticator.touchIDAvailable = touchIDAvailable
        workspace.frontmost = frontmost
        let clock = self.clock
        let quits = self.quits
        controller = AppLockController(
            settings: settings, passwords: passwords, authenticator: authenticator, workspace: workspace, presenter: overlay,
            screens: { [screenOne, screenTwo] }, now: { clock.time }, ownPID: 1, ownBundleID: "com.example.Island",
            quit: { quits.value += 1 })
        if start { controller.start() }
    }

    /// An app comes to the front, as macOS reports it.
    func open(_ app: RunningApp) {
        workspace.frontmost = app
        workspace.send(.activated(app))
    }

    /// What really follows a cover: Island takes the keyboard, so macOS reports Island coming to the front.
    func islandTakesTheKeyboard() { open(island) }

    func settle() async { for _ in 0..<10 { await Task.yield() } }
}

// MARK: When a locked app covers

@Test @MainActor func openingALockedAppCoversItOnTheScreenItsWindowsAreOn() {
    let rig = Rig()
    rig.open(slack)
    #expect(rig.overlay.isShowing)
    #expect(rig.overlay.shown.last?.covered == [screenOne] && rig.overlay.shown.last?.card == screenOne)
    #expect(rig.controller.request == AppLockController.Request(pid: 100, bundleID: "com.tinyspeck.slackmacgap", name: "Slack"))
}

@Test @MainActor func whenItCannotTellWhereTheWindowsAreItCoversEveryScreen() {
    let rig = Rig()
    rig.workspace.windows[100] = []                        // no window found
    rig.open(slack)
    #expect(rig.overlay.shown.last?.covered == [screenOne, screenTwo], "when unsure it hides more, not less")
}

@Test @MainActor func anAppThatIsNotOnTheListIsNeverCovered() {
    let rig = Rig()
    rig.open(notes)
    #expect(!rig.overlay.isShowing && rig.controller.request == nil)
}

@Test @MainActor func nothingIsCoveredWhileTheLockIsOffEvenForAnAppOnTheList() {
    let rig = Rig(enabled: false)
    rig.open(slack)
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func withNoPasswordSavedTheLockDoesNothingInsteadOfKeepingThePersonOut() {
    let rig = Rig(enabled: true, password: nil)
    #expect(!rig.controller.isEnabled && !rig.controller.isProtecting)
    rig.open(slack)
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func aPasswordThatVanishesWhileIslandRunsIsNoticedAndTheLockDoesNothing() {
    let rig = Rig()
    rig.passwords.record = nil                              // the file was deleted, or damaged (see the store test below)
    rig.open(slack)
    #expect(!rig.overlay.isShowing && !rig.controller.isEnabled, "noticed at once, not only when a password is typed")
}

@Test @MainActor func aPasswordThatVanishesWhileTheCoverIsUpEndsTheCoverInsteadOfTrappingThePerson() {
    let rig = Rig()
    rig.open(slack)
    #expect(rig.overlay.isShowing)
    rig.passwords.record = nil
    rig.controller.submitPassword("anything")
    #expect(!rig.overlay.isShowing && !rig.controller.isEnabled)
    #expect(rig.workspace.raised.isEmpty, "it does not pretend the person got in")
}

@Test @MainActor func anEmptyListCoversNothing() {
    let rig = Rig(apps: [])
    #expect(!rig.controller.isProtecting)
    rig.open(slack)
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func aLockedAppAlreadyInFrontWhenIslandStartsIsCoveredAtOnce() {
    let rig = Rig(frontmost: slack)
    #expect(rig.overlay.isShowing && rig.controller.request?.pid == 100)
    let calm = Rig(frontmost: notes)
    #expect(!calm.overlay.isShowing)
}

@Test @MainActor func islandTakingTheKeyboardAndMacOSsOwnHelpersDoNotEndTheCover() {
    let rig = Rig()
    rig.open(slack)
    rig.islandTakesTheKeyboard()
    #expect(rig.overlay.isShowing, "that is the cover itself taking the keyboard")
    rig.open(touchDialog)
    #expect(rig.overlay.isShowing, "the Touch ID dialog is not another app the person went to")
    #expect(rig.workspace.hidden.isEmpty)
}

@Test @MainActor func addingAnAppToTheListDoesNotCoverItWhileThePersonIsStillInIt() {
    let rig = Rig(apps: ["com.apple.mail"], frontmost: slack)
    #expect(!rig.overlay.isShowing)
    #expect(rig.controller.setPassword("same", repeated: "same") == .locked, "the lock is on, so the settings need unlocking first")
    rig.controller.unlockSettings(password: lockPassword)
    rig.controller.addApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    #expect(!rig.overlay.isShowing, "it asks the next time it comes to the front")
    rig.open(notes)
    rig.open(slack)
    #expect(rig.overlay.isShowing)
}

// MARK: Opening with the password

@Test @MainActor func theRightPasswordOpensTheAppAndItDoesNotAskWhileItIsInUse() {
    let rig = Rig()
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    #expect(!rig.overlay.isShowing && rig.controller.request == nil)
    #expect(rig.workspace.raised == [100], "the app is brought to the front for the person")
    rig.open(slack)                                          // macOS reports it coming to the front
    #expect(!rig.overlay.isShowing, "it was just opened")
}

@Test @MainActor func aWrongPasswordKeepsTheCoverAndNeverBringsTheAppForward() {
    let rig = Rig()
    rig.open(slack)
    rig.controller.submitPassword("not-it")
    #expect(rig.overlay.isShowing && rig.workspace.raised.isEmpty)
    #expect(rig.controller.message == "That is not the password.")
    rig.controller.submitPassword("")
    #expect(rig.overlay.isShowing)
}

@Test @MainActor func afterFiveWrongTriesThePersonMustWaitAndThenMayTryAgain() {
    let rig = Rig()
    rig.open(slack)
    for _ in 0..<5 { rig.controller.submitPassword("nope") }
    #expect(rig.controller.message?.contains("Wait 5 seconds") == true)
    rig.controller.submitPassword(lockPassword)             // right, but too soon
    #expect(rig.overlay.isShowing && rig.controller.message?.contains("Too many wrong tries") == true)
    rig.clock.time += 5
    rig.controller.submitPassword(lockPassword)
    #expect(!rig.overlay.isShowing && rig.workspace.raised == [100])
}

// MARK: Touch ID

@Test @MainActor func touchIDIsAskedForAtOnceWhenTheCoverComesUpAndOpensTheAppWhenItWorks() async {
    let rig = Rig(touchIDAvailable: true)
    rig.authenticator.touchResult = .success
    rig.open(slack)
    await rig.settle()
    #expect(rig.authenticator.touchCalls == 1)
    #expect(!rig.overlay.isShowing && rig.workspace.raised == [100])
}

@Test @MainActor func touchIDThatDoesNotRecogniseThePersonLeavesTheCoverAndSaysSo() async {
    let rig = Rig(touchIDAvailable: true)
    rig.authenticator.touchResult = .failed("Touch ID did not recognise you.")
    rig.open(slack)
    await rig.settle()
    #expect(rig.overlay.isShowing && rig.workspace.raised.isEmpty)
    #expect(rig.controller.message == "Touch ID did not recognise you." && !rig.controller.isUsingTouchID)
    rig.controller.submitPassword(lockPassword)             // the password is still there
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func aCancelledTouchIDLeavesTheCoverWithoutAMessageAndCanBeTriedAgainByHand() async {
    let rig = Rig(touchIDAvailable: true)
    rig.open(slack)
    await rig.settle()
    #expect(rig.overlay.isShowing && rig.controller.message == nil)
    rig.authenticator.touchResult = .success
    rig.controller.tryTouchID()
    await rig.settle()
    #expect(!rig.overlay.isShowing && rig.authenticator.touchCalls == 2)
}

@Test @MainActor func touchIDThatCannotBeUsedSaysWhyAndTheCoverStaysUsableWithThePassword() async {
    let rig = Rig(touchIDAvailable: true)
    rig.authenticator.touchResult = .unavailable("Touch ID is locked after too many tries. Use the password.")
    rig.open(slack)
    await rig.settle()
    #expect(rig.controller.message?.contains("Touch ID is locked") == true && rig.overlay.isShowing)
    rig.controller.submitPassword(lockPassword)
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func touchIDIsNotAskedForWhenThisMacHasNoneOrThePersonSwitchedItOff() async {
    let none = Rig(touchIDAvailable: false)
    none.open(slack)
    await none.settle()
    #expect(none.authenticator.touchCalls == 0 && !none.controller.touchIDOffered)

    let off = Rig(touchIDAvailable: true)
    off.controller.unlockSettings(password: lockPassword)
    off.controller.setTouchID(false)
    off.open(slack)
    await off.settle()
    #expect(off.authenticator.touchCalls == 0 && !off.controller.touchIDOffered)
}

@Test @MainActor func aTouchIDAnswerThatArrivesAfterThePersonLeftOpensNothing() async {
    let rig = Rig(touchIDAvailable: true)
    rig.authenticator.touchResult = nil                      // the dialog stays up
    rig.open(slack)
    await rig.settle()
    #expect(rig.authenticator.touchCalls == 1 && rig.controller.isUsingTouchID)
    rig.open(notes)                                          // the person goes to another app
    #expect(!rig.overlay.isShowing)
    rig.authenticator.answerTouch(.success)                  // ... and only then a finger is recognised
    await rig.settle()
    #expect(rig.workspace.raised.isEmpty, "a late answer must not bring a locked app forward")
    rig.open(slack)
    #expect(rig.overlay.isShowing, "it was never opened, so it still asks")
}

@Test @MainActor func aTouchIDAnswerForOneAppDoesNotOpenAnother() async {
    let rig = Rig(touchIDAvailable: true)
    rig.authenticator.touchResult = nil                      // every dialog stays up until answered
    rig.open(slack)
    await rig.settle()
    rig.open(mail)                                           // another locked app comes up instead
    await rig.settle()
    #expect(rig.controller.request?.pid == 200 && rig.authenticator.touchCalls == 2)
    rig.authenticator.answerTouch(.success)                  // the answer to Slack's question, the older one
    await rig.settle()
    #expect(rig.workspace.raised.isEmpty && rig.overlay.isShowing, "Slack's answer must not open Slack or Mail")
    rig.authenticator.answerTouch(.success)                  // Mail's own answer
    await rig.settle()
    #expect(rig.workspace.raised == [200] && !rig.overlay.isShowing)
}

@Test @MainActor func theMacsOwnPasswordOpensTheAppForSomeoneWhoForgotTheLockPassword() async {
    let rig = Rig()
    rig.authenticator.macResult = .success
    rig.open(slack)
    rig.controller.useMacPassword()
    await rig.settle()
    #expect(rig.authenticator.macCalls == 1 && !rig.overlay.isShowing && rig.workspace.raised == [100])
}

@Test @MainActor func aFailedMacPasswordKeepsTheCoverAndSaysWhy() async {
    let rig = Rig()
    rig.authenticator.macResult = .failed("That did not work.")
    rig.open(slack)
    rig.controller.useMacPassword()
    await rig.settle()
    #expect(rig.overlay.isShowing && rig.controller.message == "That did not work." && !rig.controller.isAskingMacPassword)
}

// MARK: The lock never traps the person

@Test @MainActor func goingToAnotherAppRemovesTheCoverAndHidesOnlyTheLockedApp() {
    let rig = Rig()
    rig.open(slack)
    rig.islandTakesTheKeyboard()
    rig.open(notes)                                          // ⌘Tab, the Dock, or Force Quit
    #expect(!rig.overlay.isShowing && rig.controller.request == nil)
    #expect(rig.workspace.hidden == [100], "only the locked app is hidden, so taking the cover away does not show it")
    #expect(rig.workspace.raised.isEmpty)
    #expect(rig.authenticator.cancels > 0, "a Touch ID dialog still open is closed too")
}

@Test @MainActor func notNowRemovesTheCoverAndGoesBackToTheAppThePersonWasIn() {
    let rig = Rig()
    rig.open(notes)
    rig.open(slack)
    rig.islandTakesTheKeyboard()
    rig.controller.notNow()                                  // the button, or Esc
    #expect(!rig.overlay.isShowing)
    #expect(rig.workspace.hidden == [100] && rig.workspace.raised == [300])
}

@Test @MainActor func notNowWithNoAppToGoBackToStillRemovesTheCover() {
    let rig = Rig()
    rig.open(slack)
    rig.controller.notNow()
    #expect(!rig.overlay.isShowing && rig.workspace.hidden == [100] && rig.workspace.raised.isEmpty)
}

@Test @MainActor func theLockedAppQuittingRemovesTheCover() {
    let rig = Rig()
    rig.open(slack)
    rig.workspace.running.remove(100)
    rig.workspace.send(.terminated(pid: 100))
    #expect(!rig.overlay.isShowing && rig.controller.request == nil)
    #expect(rig.workspace.hidden.isEmpty, "nothing is hidden for an app that is gone")
}

@Test @MainActor func quitIslandIsOnTheCoverAndReallyQuits() {
    let rig = Rig()
    rig.open(slack)
    rig.controller.quitIsland()
    #expect(rig.quitCalls == 1)
}

@Test @MainActor func shuttingDownRemovesTheCoverStopsListeningAndLeavesEveryAppAlone() {
    let rig = Rig()
    rig.open(slack)
    #expect(rig.workspace.isObserving)
    rig.controller.shutdown()
    #expect(!rig.overlay.isShowing && rig.controller.request == nil)
    #expect(!rig.workspace.isObserving && rig.workspace.stops == 1)
    #expect(rig.workspace.hidden.isEmpty && rig.workspace.raised.isEmpty, "quitting Island changes no app")
    rig.open(mail)                                           // nothing listens any more
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func startingAppLockTwiceListensOnlyOnce() {
    let rig = Rig()
    rig.controller.start()
    rig.open(slack)
    #expect(rig.overlay.shown.count == 1)
}

@Test @MainActor func turningTheLockOffWhileTheCoverIsUpRemovesIt() {
    let rig = Rig()
    rig.open(slack)
    rig.controller.unlockSettings(password: lockPassword)
    #expect(rig.controller.setEnabled(false))
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func takingTheAppOffTheListWhileTheCoverIsUpRemovesIt() {
    let rig = Rig()
    rig.open(slack)
    rig.controller.unlockSettings(password: lockPassword)
    rig.controller.removeApp("com.tinyspeck.slackmacgap")
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func throughAWholeSessionNoAppIsEverHiddenExceptOneThePersonLeftWhileItWasCovered() {
    let rig = Rig()
    rig.open(notes)
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    rig.open(slack)
    rig.open(mail)                                           // Slack was opened with the password, so it is not hidden
    rig.controller.notNow()
    rig.open(notes)
    #expect(rig.workspace.hidden == [200], "only Mail, which was covered and then left")
}

// MARK: When a locked app asks again

@Test @MainActor func everyTimeAsksAgainOnceThePersonWentToAnotherAppAndCameBack() {
    let rig = Rig(relock: .everyTime)
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    rig.open(slack)
    rig.open(notes)
    rig.open(slack)
    #expect(rig.overlay.isShowing)
}

@Test @MainActor func onlyAfterTheAppQuitsDoesNotAskAgainWhenThePersonComesBack() {
    let rig = Rig(relock: .whenAppQuits)
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    rig.open(slack)
    rig.open(notes)
    rig.open(slack)
    #expect(!rig.overlay.isShowing)
    rig.workspace.send(.terminated(pid: 100))
    rig.open(RunningApp(pid: 101, bundleID: slack.bundleID, name: "Slack", isRegular: true))
    #expect(rig.overlay.isShowing, "a new run of the app asks")
}

@Test @MainActor func aTimedChoiceAsksAfterThatLongAwayAndNotBefore() {
    let rig = Rig(relock: .oneMinute)
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    rig.open(slack)
    rig.open(notes)
    rig.clock.time += 30
    rig.open(slack)
    #expect(!rig.overlay.isShowing)
    rig.open(notes)
    rig.clock.time += 61
    rig.open(slack)
    #expect(rig.overlay.isShowing)
}

@Test @MainActor func theMacSleepingOrLockingMakesEveryAppAskAgain() {
    let rig = Rig(relock: .whenAppQuits)
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    rig.open(slack)
    rig.workspace.send(.locked)
    rig.open(notes)
    rig.open(slack)
    #expect(rig.overlay.isShowing)
}

// MARK: The settings

@Test @MainActor func withTheLockOnNothingCanBeChangedUntilThePersonShowsItIsThem() {
    let rig = Rig()
    #expect(rig.controller.needsUnlockForSettings)
    #expect(!rig.controller.setEnabled(false) && rig.controller.isEnabled)
    rig.controller.removeApp("com.apple.mail")
    rig.controller.setRelock(.fifteenMinutes)
    rig.controller.setTouchID(false)
    #expect(rig.controller.setPassword("brand-new", repeated: "brand-new") == .locked)
    #expect(rig.settings.settings.appLockApps.count == 2 && rig.controller.relock == .everyTime)
    #expect(rig.settings.settings.appLockTouchID && AppLockPassword.matches(lockPassword, record: rig.passwords.record!))
}

@Test @MainActor func theRightPasswordUnlocksTheSettingsAndThenChangesWork() {
    let rig = Rig()
    rig.controller.unlockSettings(password: "wrong")
    #expect(rig.controller.needsUnlockForSettings)
    rig.controller.unlockSettings(password: lockPassword)
    #expect(!rig.controller.needsUnlockForSettings)
    rig.controller.removeApp("com.apple.mail")
    rig.controller.setRelock(.fifteenMinutes)
    #expect(rig.settings.settings.appLockApps == ["com.tinyspeck.slackmacgap"] && rig.controller.relock == .fifteenMinutes)
    #expect(rig.settings.settings.appLockNames["com.apple.mail"] == nil)
}

@Test @MainActor func theSettingsCanBeUnlockedWithTouchIDOrTheMacPasswordToo() async {
    let touch = Rig(touchIDAvailable: true)
    touch.authenticator.touchResult = .success
    touch.controller.unlockSettingsWithTouchID()
    await touch.settle()
    #expect(!touch.controller.needsUnlockForSettings)

    let mac = Rig()
    mac.authenticator.macResult = .success
    mac.controller.unlockSettingsWithMacPassword()
    await mac.settle()
    #expect(!mac.controller.needsUnlockForSettings, "the way back in for someone who forgot the password")
    #expect(mac.controller.setPassword("a-new-one", repeated: "a-new-one") == .saved)
}

@Test @MainActor func aTouchIDAnswerForTheSettingsThatArrivesAfterTheyWereClosedUnlocksNothing() async {
    let rig = Rig(touchIDAvailable: true)
    rig.authenticator.touchResult = nil
    rig.controller.unlockSettingsWithTouchID()
    await rig.settle()
    rig.controller.lockSettings()                            // the popup was closed
    rig.authenticator.answerTouch(.success)
    await rig.settle()
    #expect(rig.controller.needsUnlockForSettings)
}

@Test @MainActor func closingTheSettingsLocksThemAgain() {
    let rig = Rig()
    rig.controller.unlockSettings(password: lockPassword)
    #expect(!rig.controller.needsUnlockForSettings)
    rig.controller.lockSettings()
    #expect(rig.controller.needsUnlockForSettings)
}

@Test @MainActor func withTheLockOffTheSettingsAreFreeToChange() {
    let rig = Rig(enabled: false)
    #expect(!rig.controller.needsUnlockForSettings)
    rig.controller.setRelock(.oneMinute)
    rig.controller.removeApp("com.apple.mail")
    #expect(rig.controller.relock == .oneMinute && rig.settings.settings.appLockApps == ["com.tinyspeck.slackmacgap"])
}

@Test @MainActor func theLockCannotBeTurnedOnWithoutAPasswordAndTheFirstPasswordTurnsItOn() {
    let rig = Rig(enabled: false, password: nil)
    #expect(!rig.controller.setEnabled(true) && !rig.controller.isEnabled)
    #expect(rig.controller.message == "Set a password first.")
    #expect(rig.controller.setPassword("abcd", repeated: "abcd") == .saved)
    #expect(rig.controller.hasPassword && rig.controller.isEnabled, "choosing the first password is asking for the lock")
}

@Test @MainActor func aNewPasswordIsCheckedBeforeItIsKept() {
    let rig = Rig(enabled: false, password: nil)
    #expect(rig.controller.setPassword("abc", repeated: "abc") == .tooShort)
    #expect(rig.controller.setPassword("abcd", repeated: "abce") == .doesNotMatch)
    rig.passwords.saveFails = true
    #expect(rig.controller.setPassword("abcd", repeated: "abcd") == .couldNotSave)
    #expect(!rig.controller.hasPassword && !rig.controller.isEnabled, "a password that could not be kept turns nothing on")
}

@Test @MainActor func changingThePasswordMakesTheNewOneWorkAndTheOldOneStop() {
    let rig = Rig()
    rig.controller.unlockSettings(password: lockPassword)
    #expect(rig.controller.setPassword("fresh-start", repeated: "fresh-start") == .saved)
    rig.controller.lockSettings()
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    #expect(rig.overlay.isShowing, "the old password no longer opens it")
    rig.controller.submitPassword("fresh-start")
    #expect(!rig.overlay.isShowing)
}

@Test @MainActor func turningTheLockOnAgainAfterItWasOffNeedsNoUnlockAndOldOpeningsAreForgotten() {
    let rig = Rig(relock: .whenAppQuits)
    rig.open(slack)
    rig.controller.submitPassword(lockPassword)
    rig.open(slack)
    rig.controller.unlockSettings(password: lockPassword)
    rig.controller.setEnabled(false)
    rig.controller.lockSettings()
    #expect(rig.controller.setEnabled(true))
    rig.open(notes)
    rig.open(slack)
    #expect(rig.overlay.isShowing, "turning it off and on starts afresh")
}

@Test @MainActor func islandAndFinderCannotBeLockedAndAnAppIsListedOnce() {
    let rig = Rig(enabled: false)
    #expect(!rig.controller.addApp(bundleID: "com.example.Island", name: "Island"))
    #expect(!rig.controller.addApp(bundleID: "com.apple.finder", name: "Finder"))
    #expect(rig.controller.message == "Finder cannot be locked.")
    #expect(rig.controller.addApp(bundleID: "com.apple.mail", name: "Mail"))
    #expect(rig.settings.settings.appLockApps == ["com.tinyspeck.slackmacgap", "com.apple.mail"])
}

@Test @MainActor func somethingThatIsNotAnAppCannotBeAdded() {
    let rig = Rig(enabled: false)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-app-\(UUID()).app")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(!rig.controller.addApp(at: folder))
    #expect(rig.controller.message == "That is not an app Island can lock.")
}

@Test @MainActor func theAppsToChooseFromLeaveOutTheLockedOnesIslandAndFinderAndAreInOrder() {
    let rig = Rig()
    rig.workspace.apps = [
        notes, slack, island, RunningApp(pid: 5, bundleID: "com.apple.finder", name: "Finder", isRegular: true),
        RunningApp(pid: 6, bundleID: "com.example.Zed", name: "zed", isRegular: true),
        RunningApp(pid: 7, bundleID: "com.example.Zed", name: "zed again", isRegular: true),
        RunningApp(pid: 8, bundleID: "com.example.Arc", name: "Arc", isRegular: true), RunningApp(pid: 9, bundleID: nil, name: "?", isRegular: true),
    ]
    #expect(rig.controller.candidates().map(\.name) == ["Arc", "Notes", "zed"])
}

// MARK: Looks

@Test @MainActor func theCoverWindowsSitAboveTheAppButBelowTheDockAndTheMenuBarAndCanTakeTheKeyboard() {
    let panel = LockPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 300))       // never shown
    #expect(panel.level == IslandWindowLevel.lock)
    #expect(panel.level.rawValue > NSWindow.Level.modalPanel.rawValue)
    #expect(panel.level.rawValue < NSWindow.Level.statusBar.rawValue && panel.level.rawValue < NSWindow.Level.mainMenu.rawValue,
        "the menu bar must stay reachable, to go to another app")
    #expect(panel.level.rawValue < Int(CGWindowLevelForKey(.dockWindow)), "the Dock must stay reachable, to go to another app")
    #expect(panel.level.rawValue < IslandWindowLevel.island.rawValue, "the island stays above it")
    #expect(panel.canBecomeKey && panel.isOpaque)
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.fullScreenAuxiliary))
}

@Test @MainActor func theRealCoverIsNotShownUntilAskedAndHidingItWhenNothingShowsIsHarmless() {
    let overlay = LockOverlay()
    #expect(!overlay.isShowing)
    overlay.hide()
    overlay.hide()
    #expect(!overlay.isShowing)
}

@Test @MainActor func theCardAsksForTheAppAndHasEveryWayOut() {
    let rig = Rig()
    rig.open(slack)
    let card = NSHostingView(rootView: LockCardView(controller: rig.controller).frame(width: 600, height: 500))
    card.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
    card.layoutSubtreeIfNeeded()
    #expect(card.fittingSize.height > 150, "the card has real content")
    // The ways out are plain controller calls the buttons make: not now, the Mac's password, and quitting Island.
    rig.controller.useMacPassword()
    rig.controller.notNow()
    rig.controller.quitIsland()
    #expect(rig.quitCalls == 1 && !rig.overlay.isShowing)
}

@Test @MainActor func theSettingsPopupFitsTheUsualToolsTabInEveryState() {
    let usualToolsTab = CGSize(width: 556, height: 232)
    func height(_ rig: Rig) -> CGFloat {
        let popup = ToolPopup(title: "App lock", symbol: "lock.app.dashed", tint: .green, isOn: .constant(true), onClose: {}) {
            AppLockSettings(controller: rig.controller)
        }
        .frame(width: usualToolsTab.width)
        return NSHostingView(rootView: popup).fittingSize.height
    }
    let gate = Rig()                                                                       // on, not yet shown it is them
    let first = Rig(enabled: false, password: nil)                                         // choosing the first password
    let main = Rig(apps: ["a.b.One", "a.b.Two", "a.b.Three", "a.b.Four", "a.b.Five", "a.b.Six"], touchIDAvailable: true)
    main.controller.unlockSettings(password: lockPassword)
    let empty = Rig(apps: [], touchIDAvailable: true)
    empty.controller.unlockSettings(password: lockPassword)
    for (name, rig) in [("gate", gate), ("first password", first), ("main", main), ("no apps", empty)] {
        let measured = height(rig)
        #expect(measured <= usualToolsTab.height, "\(name): \(measured) pt tall")
        #expect(measured > 100, "\(name): measured a real popup")
    }
}

// MARK: The password file and the Mac's answers

@Test func thePasswordFileHoldsOnlyTheHashIsPrivateAndADamagedOneCountsAsNone() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("applock-store-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let tokens = FileTokenStore(directory: folder, service: "app-lock")
    let store = FileAppLockPasswordStore(tokens: tokens)
    #expect(store.load() == nil)
    let record = try #require(AppLockPassword.makeRecord(for: "hunter2-words", rounds: 10_000))
    #expect(store.save(record) && store.load() == record)
    let file = folder.appendingPathComponent("app-lock")
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(!text.contains("hunter2-words"))
    let mode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
    #expect(mode & 0o077 == 0, "only the user can read it")
    // Damaged: cut short, not JSON, a record that asks for an endless number of rounds.
    _ = tokens.save("{\"version\":1,\"rounds\":")
    #expect(store.load() == nil)
    _ = tokens.save("not json at all")
    #expect(store.load() == nil)
    var hostile = record
    hostile.rounds = Int.max / 4
    _ = tokens.save(String(data: try JSONEncoder().encode(hostile), encoding: .utf8) ?? "")
    #expect(store.load() == nil, "a record that would take forever to check is refused, not tried")
}

@Test func theMacsAnswersBecomeWhatThePersonSees() {
    #expect(SystemLockAuthenticator.result(for: LAError(.userCancel)) == .cancelled)
    #expect(SystemLockAuthenticator.result(for: LAError(.appCancel)) == .cancelled)
    #expect(SystemLockAuthenticator.result(for: LAError(.userFallback)) == .cancelled)
    if case .failed = SystemLockAuthenticator.result(for: LAError(.authenticationFailed)) {} else { Issue.record("expected failed") }
    if case .unavailable(let text) = SystemLockAuthenticator.result(for: LAError(.biometryLockout)) {
        #expect(text.contains("Use the password"))
    } else { Issue.record("expected unavailable") }
    if case .unavailable = SystemLockAuthenticator.result(for: LAError(.biometryNotEnrolled)) {} else { Issue.record("expected unavailable") }
    if case .failed = SystemLockAuthenticator.result(for: nil) {} else { Issue.record("expected failed") }
}

// MARK: The real Mac-facing parts, only looked at (nothing is hidden, raised, asked or shown)

@Test @MainActor func theRealWorkspaceCanBeStartedAndStoppedAndOnlyLooksAtTheRunningApps() {
    let workspace = SystemAppLockWorkspace()
    let stop = workspace.observe { _ in }
    stop()
    stop()                                                    // stopping again is harmless
    let apps = workspace.runningApps()
    #expect(apps.allSatisfy { $0.isRegular && $0.pid > 0 }, "only apps with a Dock icon are offered")
    let own = ProcessInfo.processInfo.processIdentifier
    #expect(workspace.isRunning(pid: own))
    #expect(!workspace.isRunning(pid: 2_000_000_000))
    #expect(workspace.windowFrames(of: 2_000_000_000).isEmpty, "an app that is not there has no windows")
    _ = workspace.frontmost
}

@Test @MainActor func theRealAuthenticatorSaysWhetherTouchIDExistsWithoutAskingForAnything() {
    let authenticator = SystemLockAuthenticator()
    _ = authenticator.touchIDAvailable                        // reads the answer; shows no dialog
    authenticator.cancel()                                    // nothing is waiting: harmless
    authenticator.cancel()
}
