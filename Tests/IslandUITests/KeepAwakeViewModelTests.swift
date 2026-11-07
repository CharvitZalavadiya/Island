import Testing
import Foundation
import IslandCore
@testable import IslandUI

private let sudoStart = ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]
private let sudoStop = ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
private let pmsetRead = ["/usr/bin/pmset", "-g"]
private let sudoCheck = ["/usr/bin/sudo", "-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]
private let noPassword = CommandResult(status: 1, stdout: "", stderr: "sudo: a password is required")

/// A pretend Mac: remembers whether sleep is disabled and records commands. It never touches the real power settings.
private final class SimulatedMac: CommandRunner {
    var sleepDisabled = false
    var calls: [[String]] = []
    var failure: CommandResult?
    /// Whether the passwordless rule is installed; without it every `sudo -n` fails, as on a Mac that never allowed it.
    var permissionInstalled = true

    func run(_ executable: String, _ args: [String]) throws -> CommandResult {
        let call = [executable] + args
        calls.append(call)
        if call == pmsetRead {
            let output = "System-wide power settings:\nCurrently in use:\n SleepDisabled\t\t\(sleepDisabled ? 1 : 0)\n"
            return CommandResult(status: 0, stdout: output, stderr: "")
        }
        if call == sudoCheck { return permissionInstalled ? CommandResult(status: 0, stdout: "", stderr: "") : noPassword }
        if !permissionInstalled { return noPassword }
        if let failure { return failure }
        if call == sudoStart { sleepDisabled = true }
        if call == sudoStop { sleepDisabled = false }
        return CommandResult(status: 0, stdout: "", stderr: "")
    }
}

private final class FakeInstaller: PermissionInstalling {
    var installError: Error?
    var removeError: Error?
    var onInstall: () -> Void = {}
    var onRemove: () -> Void = {}
    private(set) var installs = 0
    private(set) var removes = 0

    func install() async throws {
        installs += 1
        if let installError { throw installError }
        onInstall()
    }

    func remove() async throws {
        removes += 1
        if let removeError { throw removeError }
        onRemove()
    }
}

private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private struct Rig {
    let mac = SimulatedMac()
    let clock = TestClock()
    let model: IslandModel
    let stateURL: URL
    let installer = FakeInstaller()
    let viewModel: KeepAwakeViewModel

    init(rememberedSession: KeepAwakeState? = nil, sleepAlreadyDisabled: Bool = false) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-ui-tests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            store: FileStore(url: directory.appendingPathComponent("settings.json"), defaultValue: Settings()))
        model = IslandModel(settings: settings)
        stateURL = directory.appendingPathComponent("keep-awake.json")
        let store = FileStore<KeepAwakeState?>(url: stateURL, defaultValue: nil)
        if let rememberedSession { try? store.save(rememberedSession) }
        mac.sleepDisabled = sleepAlreadyDisabled
        let clock = self.clock
        let controller = KeepAwakeController(runner: mac, stateStore: store, now: { clock.now })
        let mac = self.mac
        installer.onInstall = { mac.permissionInstalled = true }
        installer.onRemove = { mac.permissionInstalled = false }
        viewModel = KeepAwakeViewModel(model: model, controller: controller, installer: installer, now: { clock.now })
    }
}

@Test @MainActor func anEmptyBoxKeepsTheMacAwakeIndefinitelyAndShowsTheWing() {
    let rig = Rig()
    rig.viewModel.isInfinite = true
    rig.viewModel.start()
    #expect(rig.mac.calls.contains(sudoStart))
    #expect(rig.mac.sleepDisabled)
    #expect(rig.viewModel.status == .on(deadline: nil, startedByIsland: true))
    #expect(rig.viewModel.remaining == nil)
    #expect(rig.model.activities.contains(.keepAwake))
    #expect(rig.viewModel.message == nil)
}

@Test @MainActor func typedMinutesStartATimedSessionThatCountsDown() {
    let rig = Rig()
    rig.viewModel.minutes = 10
    rig.viewModel.start()
    #expect(rig.viewModel.status == .on(deadline: rig.clock.now.addingTimeInterval(600), startedByIsland: true))
    #expect(rig.viewModel.remaining == 600)
    rig.clock.advance(60)
    rig.viewModel.tick()
    #expect(rig.viewModel.remaining == 540)
    #expect(rig.mac.sleepDisabled)
}

@Test @MainActor func stopRestoresSleepAndTakesTheWingDown() {
    let rig = Rig()
    rig.viewModel.start()
    rig.viewModel.stop()
    #expect(rig.mac.calls.contains(sudoStop))
    #expect(!rig.mac.sleepDisabled)
    #expect(rig.viewModel.status == .off)
    #expect(!rig.model.activities.contains(.keepAwake))
}

@Test @MainActor func aTimedSessionEndsItselfAtTheDeadline() {
    let rig = Rig()
    rig.viewModel.minutes = 1
    rig.viewModel.start()
    rig.clock.advance(60)
    rig.viewModel.tick()
    #expect(!rig.mac.sleepDisabled)
    #expect(rig.viewModel.status == .off)
    #expect(!rig.model.activities.contains(.keepAwake))
}

@Test @MainActor func startingWithoutThePermissionExplainsAndAsksForItInsteadOfFailing() {
    let rig = Rig()
    rig.mac.permissionInstalled = false
    rig.viewModel.start()
    #expect(rig.viewModel.permission == .missing)
    #expect(rig.viewModel.message?.contains("Allow") == true)
    #expect(rig.viewModel.message?.contains("script") == false)
    #expect(rig.viewModel.status == .off)
    #expect(!rig.mac.sleepDisabled)
}

@Test @MainActor func aSessionStartedOutsideIslandIsShownAndCanBeStopped() {
    let rig = Rig(sleepAlreadyDisabled: true)
    rig.viewModel.launch()
    #expect(rig.viewModel.status == .on(deadline: nil, startedByIsland: false))
    #expect(rig.model.activities.contains(.keepAwake))
    // Launching must not have touched a session Island did not start.
    #expect(rig.mac.sleepDisabled)
    #expect(rig.mac.calls.filter { $0 == sudoStop }.isEmpty)

    rig.viewModel.stop()
    #expect(!rig.mac.sleepDisabled)
    #expect(rig.viewModel.status == .off)
}

@Test @MainActor func launchingAfterACrashRestoresSleep() {
    let rig = Rig(rememberedSession: KeepAwakeState(startedByIsland: true, deadline: nil), sleepAlreadyDisabled: true)
    rig.viewModel.launch()
    #expect(!rig.mac.sleepDisabled)
    #expect(rig.viewModel.status == .off)
    #expect(!rig.model.activities.contains(.keepAwake))
}

@Test @MainActor func quittingEndsAnIslandSessionButLeavesAnOutsideOneAlone() {
    let island = Rig()
    island.viewModel.start()
    island.viewModel.willTerminate()
    #expect(!island.mac.sleepDisabled)

    let outside = Rig(sleepAlreadyDisabled: true)
    outside.viewModel.launch()
    outside.viewModel.willTerminate()
    #expect(outside.mac.sleepDisabled)
}

@Test func compactLabelsFitTheWing() {
    #expect(KeepAwakeViewModel.compactLabel(remaining: nil) == "∞")
    #expect(KeepAwakeViewModel.compactLabel(remaining: 600) == "10m")
    #expect(KeepAwakeViewModel.compactLabel(remaining: 61) == "2m")
    #expect(KeepAwakeViewModel.compactLabel(remaining: 0) == "0m")
    #expect(KeepAwakeViewModel.compactLabel(remaining: 5400) == "90m")
    #expect(KeepAwakeViewModel.compactLabel(remaining: 6000) == "2h")
    #expect(KeepAwakeViewModel.compactLabel(remaining: 49 * 3600) == "49h")
}

// MARK: The permission, set up from inside the app

@Test @MainActor func thePermissionIsCheckedAtLaunch() {
    let granted = Rig()
    granted.viewModel.launch()
    #expect(granted.viewModel.permission == .granted)

    let missing = Rig()
    missing.mac.permissionInstalled = false
    missing.viewModel.launch()
    #expect(missing.viewModel.permission == .missing)
}

@Test @MainActor func withoutPermissionStartNeverRunsSudo() {
    let rig = Rig()
    rig.mac.permissionInstalled = false
    rig.viewModel.refreshPermission()
    rig.viewModel.start()
    #expect(!rig.mac.calls.contains(sudoStart))
    #expect(rig.viewModel.message != nil)
}

@Test @MainActor func grantingThePermissionMakesStartWork() async {
    let rig = Rig()
    rig.mac.permissionInstalled = false
    rig.viewModel.refreshPermission()
    await rig.viewModel.grantPermission()
    #expect(rig.installer.installs == 1)
    #expect(rig.viewModel.permission == .granted)
    #expect(rig.viewModel.message == nil)
    rig.viewModel.isInfinite = true
    rig.viewModel.start()
    #expect(rig.mac.sleepDisabled)
    #expect(rig.viewModel.status == .on(deadline: nil, startedByIsland: true))
}

@Test @MainActor func cancellingThePasswordDialogLeavesThePermissionMissingWithoutAnError() async {
    let rig = Rig()
    rig.mac.permissionInstalled = false
    rig.viewModel.refreshPermission()
    rig.installer.installError = SudoersError.cancelled
    await rig.viewModel.grantPermission()
    #expect(rig.viewModel.permission == .missing)
    #expect(rig.viewModel.message == nil)
}

@Test @MainActor func aFailedGrantShowsTheReason() async {
    let rig = Rig()
    rig.mac.permissionInstalled = false
    rig.viewModel.refreshPermission()
    rig.installer.installError = SudoersError.failed("visudo: boom")
    await rig.viewModel.grantPermission()
    #expect(rig.viewModel.permission == .missing)
    #expect(rig.viewModel.message?.contains("boom") == true)
}

@Test @MainActor func grantingWhileAlreadyGrantedDoesNotAskAgain() async {
    let rig = Rig()
    rig.viewModel.refreshPermission()
    await rig.viewModel.grantPermission()
    #expect(rig.installer.installs == 0)
}

@Test @MainActor func revokingRemovesThePermission() async {
    let rig = Rig()
    rig.viewModel.refreshPermission()
    #expect(rig.viewModel.permission == .granted)
    await rig.viewModel.revokePermission()
    #expect(rig.installer.removes == 1)
    #expect(rig.viewModel.permission == .missing)
}

@Test @MainActor func revokingStopsASessionThatIsRunning() async {
    let rig = Rig()
    rig.viewModel.start()
    #expect(rig.mac.sleepDisabled)
    await rig.viewModel.revokePermission()
    // The permission is what allows switching sleep back on, so it is switched back first.
    #expect(!rig.mac.sleepDisabled)
    #expect(rig.viewModel.status == .off)
}

@Test @MainActor func aFailedRevokeShowsTheReasonAndKeepsThePermission() async {
    let rig = Rig()
    rig.viewModel.refreshPermission()
    rig.installer.removeError = SudoersError.failed("rm: boom")
    await rig.viewModel.revokePermission()
    #expect(rig.viewModel.permission == .granted)
    #expect(rig.viewModel.message?.contains("boom") == true)
}

@Test @MainActor func thePermissionTurnsMissingIfItIsRemovedBehindIslandsBack() {
    let rig = Rig()
    rig.viewModel.launch()
    #expect(rig.viewModel.permission == .granted)
    rig.mac.permissionInstalled = false     // someone deleted the sudoers file
    rig.viewModel.start()
    #expect(rig.viewModel.permission == .missing)
}

@Test @MainActor func whileTheDialogIsOpenGrantingIsMarkedAsBusy() async {
    let rig = Rig()
    rig.mac.permissionInstalled = false
    rig.viewModel.refreshPermission()
    #expect(!rig.viewModel.isWorking)
    await rig.viewModel.grantPermission()
    #expect(!rig.viewModel.isWorking)       // and it is cleared again afterwards
}
