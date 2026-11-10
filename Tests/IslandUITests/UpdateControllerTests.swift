import Foundation
import Testing
import IslandCore
@testable import IslandUI

// The update controller with a stand-in for GitHub and a stand-in installer (the real installer is tested separately).

private final class FakeFeed: UpdateFeed, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Result<UpdateRelease, Error>
    private var asked = 0
    init(_ answer: Result<UpdateRelease, Error>) { self.answer = answer }
    var timesAsked: Int { lock.lock(); defer { lock.unlock() }; return asked }
    func set(_ new: Result<UpdateRelease, Error>) { lock.lock(); answer = new; lock.unlock() }
    func latestRelease() async throws -> UpdateRelease {
        lock.lock(); asked += 1; let current = answer; lock.unlock()
        return try current.get()
    }
}

private actor Gate {
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async { if open { return }; await withCheckedContinuation { waiting.append($0) } }
    func release() { open = true; waiting.forEach { $0.resume() }; waiting = [] }
}

private final class FakeInstaller: UpdateInstalling, @unchecked Sendable {
    private let lock = NSLock()
    var prepareError: Error?
    var relaunchError: Error?
    var gate: Gate?
    var reportProgress: [Double] = []
    private var events: [String] = []
    var log: [String] { lock.lock(); defer { lock.unlock() }; return events }
    private func note(_ text: String) { lock.lock(); events.append(text); lock.unlock() }

    func prepare(_ release: UpdateRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> PreparedUpdate {
        note("prepare \(release.version)")
        for step in reportProgress { progress(step) }
        if let gate { await gate.wait() }
        if let prepareError { throw prepareError }
        return PreparedUpdate(
            version: release.version, installedApp: URL(fileURLWithPath: "/Applications/Island.app"),
            newApp: URL(fileURLWithPath: "/Applications/.Island-update.app"), backupApp: URL(fileURLWithPath: "/Applications/.Island-previous.app"),
            workDirectory: URL(fileURLWithPath: "/tmp/island-update"))
    }
    func relaunch(_ prepared: PreparedUpdate, processID: Int32, extraArguments: [String]) throws {
        note("relaunch pid=\(processID) args=\(extraArguments.joined(separator: " "))")
        if let relaunchError { throw relaunchError }
    }
    func discard(_ prepared: PreparedUpdate) { note("discard") }
}

private func release(_ version: String) -> UpdateRelease {
    UpdateRelease(
        version: AppVersion(version)!, tag: "v\(version)", notes: "## What is new\n- Things.\n\n## Install\n1. Drag.", pageURL: URL(string: "https://github.com/o/r/releases/tag/v\(version)")!,
        dmgName: "Island-\(version).dmg", dmgURL: URL(string: "https://github.com/o/r/Island-\(version).dmg")!, checksumURL: URL(string: "https://github.com/o/r/Island-\(version).dmg.sha256")!)
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private final class Box<T>: @unchecked Sendable { var value: T; init(_ value: T) { self.value = value } }

@MainActor private struct Rig {
    let controller: UpdateController
    let feed: FakeFeed
    let installer: FakeInstaller
    let settings: SettingsStore
    let clock: Clock
    let quit: Box<Int>
    let opened: Box<[URL]>
}

@MainActor private func rig(current: String = "1.0.0", latest: String? = "1.1.0", settings change: (inout Settings) -> Void = { _ in }) -> Rig {
    let feed = FakeFeed(latest.map { .success(release($0)) } ?? .failure(UpdateError.network("offline")))
    let installer = FakeInstaller()
    var initial = Settings()
    change(&initial)
    let settings = SettingsStore(store: FileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("u-\(UUID()).json"), defaultValue: initial))
    let clock = Clock(), quit = Box(0), opened = Box<[URL]>([])
    let controller = UpdateController(
        feed: feed, installer: installer, settings: settings, currentVersion: AppVersion(current)!, now: { clock.now },
        quit: { quit.value += 1 }, openURL: { opened.value.append($0) }, processID: 4242, relaunchArguments: ["--support-dir", "/tmp/x"])
    return Rig(controller: controller, feed: feed, installer: installer, settings: settings, clock: clock, quit: quit, opened: opened)
}

private func eventually(timeout: TimeInterval = 4, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

@Test @MainActor func updatesCheckNowFindsANewerVersionAndRemembersWhenItLooked() async {
    let r = rig(current: "1.0.0", latest: "1.1.0")
    #expect(r.controller.state == .idle && r.controller.availableVersion == nil && r.controller.lastChecked == nil)
    await r.controller.checkNow()
    #expect(r.controller.state == .available && r.controller.availableVersion == AppVersion("1.1.0"))
    #expect(r.controller.release?.whatsNew == "## What is new\n- Things.")
    #expect(r.controller.lastChecked == r.clock.now)                                    // saved in the settings
    #expect(r.settings.settings.lastUpdateCheck == r.clock.now)
}

@Test @MainActor func updatesTheSameOrAnOlderVersionIsNotAnUpdate() async {
    for latest in ["1.0.0", "0.9.0", "v1.0"] {
        let r = rig(current: "1.0.0", latest: latest)
        await r.controller.checkNow()
        #expect(r.controller.state == .upToDate && r.controller.availableVersion == nil && r.controller.release == nil, "\(latest)")
    }
}

@Test @MainActor func updatesAnUpdateThatWasFoundDisappearsWhenItIsInstalledBySomeOtherMeansAndTheNextLookSaysUpToDate() async {
    let r = rig(current: "1.0.0", latest: "1.1.0")
    await r.controller.checkNow()
    #expect(r.controller.availableVersion != nil)
    r.feed.set(.success(release("1.0.0")))                                              // the release was withdrawn, or Island was updated by hand
    await r.controller.checkNow()
    #expect(r.controller.availableVersion == nil && r.controller.state == .upToDate)
}

@Test @MainActor func updatesAFailedCheckSaysWhatWentWrongAndKeepsTheLastCheckTime() async {
    let r = rig(latest: nil)
    await r.controller.checkNow()
    #expect(r.controller.state == .failed("Couldn't reach GitHub. offline"))
    #expect(r.controller.lastChecked == nil)                                            // it did not look, so it does not say it did
    r.feed.set(.failure(UpdateError.rateLimited))
    await r.controller.checkNow()
    #expect(r.controller.state == .failed(UpdateError.rateLimited.message))
}

@Test @MainActor func updatesTheAutomaticCheckHappensOnlyWhenSwitchedOnAndDue() async {
    // Off: never.
    let off = rig(settings: { $0.checkForUpdates = false })
    await off.controller.automaticCheckIfDue()
    #expect(off.feed.timesAsked == 0 && off.controller.state == .idle)

    // On, never checked: checks.
    let on = rig()
    await on.controller.automaticCheckIfDue()
    #expect(on.feed.timesAsked == 1 && on.controller.availableVersion != nil)

    // Checked a little while ago: leaves GitHub alone. A day later: asks again.
    on.clock.advance(19 * 3600)
    await on.controller.automaticCheckIfDue()
    #expect(on.feed.timesAsked == 1)
    on.clock.advance(2 * 3600)
    await on.controller.automaticCheckIfDue()
    #expect(on.feed.timesAsked == 2)
}

@Test @MainActor func updatesAnAutomaticCheckThatFailsIsSilentAndTriesAgainNextTime() async {
    let r = rig(latest: nil)
    await r.controller.automaticCheckIfDue()
    #expect(r.controller.state == .idle)                                                // no error shown for something nobody asked for
    #expect(r.controller.lastChecked == nil)                                            // so the next chance is not skipped
    r.feed.set(.success(release("1.1.0")))
    await r.controller.automaticCheckIfDue()
    #expect(r.controller.state == .available && r.feed.timesAsked == 2)
}

@Test @MainActor func updatesAFailedAutomaticCheckKeepsShowingAnUpdateAlreadyFound() async {
    let r = rig()
    await r.controller.checkNow()
    #expect(r.controller.state == .available)
    r.clock.advance(25 * 3600)
    r.feed.set(.failure(UpdateError.network("offline")))
    await r.controller.automaticCheckIfDue()
    #expect(r.controller.state == .available && r.controller.availableVersion != nil)
}

@Test @MainActor func updatesInstallDownloadsThenHandsOverToTheSwapAndQuitsIsland() async {
    let r = rig()
    await r.controller.checkNow()
    await r.controller.installAvailable()
    #expect(r.installer.log == ["prepare 1.1.0", "relaunch pid=4242 args=--support-dir /tmp/x"])
    #expect(r.quit.value == 1)                                                          // Island quits so the new one can take its place
    #expect(r.controller.state == .installing)
}

@Test @MainActor func updatesTheProgressOfTheDownloadIsShownAsItGoes() async {
    let r = rig()
    let gate = Gate()
    r.installer.gate = gate
    r.installer.reportProgress = [0.25, 0.6]
    await r.controller.checkNow()
    let installing = Task { await r.controller.installAvailable() }
    #expect(await eventually { r.controller.state == .downloading(0.6) })
    #expect(r.controller.isBusy)
    await gate.release()
    await installing.value
    #expect(r.controller.state == .installing)
}

@Test @MainActor func updatesWhileBusyNothingElseStartsSoItIsNeverInstalledOrCheckedTwiceAtOnce() async {
    let r = rig()
    let gate = Gate()
    r.installer.gate = gate
    await r.controller.checkNow()
    let installing = Task { await r.controller.installAvailable() }
    #expect(await eventually { r.controller.isBusy })
    let before = r.feed.timesAsked
    await r.controller.checkNow()                                                       // ignored: an install is under way
    await r.controller.automaticCheckIfDue()
    await r.controller.installAvailable()                                               // ignored too
    #expect(r.feed.timesAsked == before)
    #expect(r.installer.log.filter { $0.hasPrefix("prepare") }.count == 1)
    await gate.release()
    await installing.value
    #expect(r.quit.value == 1)
}

@Test @MainActor func updatesADownloadThatFailsShowsWhyKeepsTheUpdateAndDoesNotQuit() async {
    let r = rig()
    r.installer.prepareError = UpdateError.checksumMismatch
    await r.controller.checkNow()
    await r.controller.installAvailable()
    #expect(r.controller.state == .failed(UpdateError.checksumMismatch.message))
    #expect(r.quit.value == 0)                                                          // Island is still running, untouched
    #expect(r.controller.availableVersion == AppVersion("1.1.0"))                       // and can try again
    r.installer.prepareError = nil
    await r.controller.installAvailable()
    #expect(r.controller.state == .installing && r.quit.value == 1)
}

@Test @MainActor func updatesIfTheSwapCannotBeStartedTheStagedUpdateIsDiscardedAndIslandKeepsRunning() async {
    let r = rig()
    r.installer.relaunchError = UpdateError.installFailed("the installer could not be started")
    await r.controller.checkNow()
    await r.controller.installAvailable()
    #expect(r.installer.log.contains("discard"))
    #expect(r.quit.value == 0)
    #expect(r.controller.state == .failed(UpdateError.installFailed("the installer could not be started").message))
}

@Test @MainActor func updatesInstallingWithNothingFoundDoesNothing() async {
    let r = rig(current: "1.1.0", latest: "1.1.0")
    await r.controller.installAvailable()                                               // nothing was ever found
    await r.controller.checkNow()
    await r.controller.installAvailable()                                               // up to date
    #expect(r.installer.log.isEmpty && r.quit.value == 0)
}

@Test @MainActor func updatesTheReleasePageOpensInTheBrowserForWhenInstallingInPlaceIsNotPossible() async {
    let r = rig()
    r.controller.openReleasePage()                                                      // nothing found yet
    #expect(r.opened.value.isEmpty)
    await r.controller.checkNow()
    r.controller.openReleasePage()
    #expect(r.opened.value == [URL(string: "https://github.com/o/r/releases/tag/v1.1.0")!])
}

@Test @MainActor func updatesTheDebugSwitchLooksAndInstallsInOneGo() async {
    let r = rig()
    await r.controller.runDebugUpdateNow()
    #expect(r.installer.log.first == "prepare 1.1.0" && r.quit.value == 1)
    let none = rig(current: "1.1.0", latest: "1.1.0")
    await none.controller.runDebugUpdateNow()
    #expect(none.installer.log.isEmpty && none.quit.value == 0)
}

@Test @MainActor func updatesTheAutomaticChecksStartAndStopWithoutLeavingATimerBehind() async {
    let r = rig()
    r.controller.startAutomaticChecks(firstDelay: 0.05)
    #expect(await eventually { r.feed.timesAsked == 1 })                                // the first look, a moment after start
    r.controller.stopAutomaticChecks()
    r.controller.startAutomaticChecks(firstDelay: 0.05)                                 // starting again does not double up
    r.clock.advance(25 * 3600)
    #expect(await eventually { r.feed.timesAsked == 2 })
    r.controller.stopAutomaticChecks()
}
