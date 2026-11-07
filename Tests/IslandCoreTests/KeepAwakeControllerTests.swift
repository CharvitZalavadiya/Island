import Testing
import Foundation
@testable import IslandCore

/// Records every command instead of running it, so no test can touch the real power settings.
final class FakeRunner: CommandRunner {
    var calls: [[String]] = []
    var handler: (([String]) -> CommandResult)?

    func run(_ executable: String, _ args: [String]) throws -> CommandResult {
        let call = [executable] + args
        calls.append(call)
        return handler?(call) ?? CommandResult(status: 0, stdout: "", stderr: "")
    }
}

private let sudoStart = ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]
private let sudoStop = ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
private let pmsetRead = ["/usr/bin/pmset", "-g"]

private func pmsetOutput(sleepDisabled: Int) -> String {
    """
    System-wide power settings:
    Currently in use:
     standby              1
     powernap             1
     SleepDisabled\t\t\(sleepDisabled)
     displaysleep         10
    """
}

private struct Rig {
    let runner = FakeRunner()
    let clock = FakeClock()
    let stateURL = makeTempDirectory().appendingPathComponent("keep-awake.json")
    var store: FileStore<KeepAwakeState?> { FileStore(url: stateURL, defaultValue: nil) }
    var controller: KeepAwakeController {
        KeepAwakeController(runner: runner, stateStore: store, now: { [clock] in clock.now })
    }
}

@Test func startRunsTheExactSudoCommandAndRemembersTheSession() throws {
    let rig = Rig()
    try rig.controller.start(.minutes(5))
    #expect(rig.runner.calls == [sudoStart])
    #expect(rig.store.load() == KeepAwakeState(startedByIsland: true, deadline: rig.clock.now.addingTimeInterval(300)))
}

@Test func startingIndefinitelyHasNoDeadline() throws {
    let rig = Rig()
    try rig.controller.start(.indefinite)
    #expect(rig.store.load() == KeepAwakeState(startedByIsland: true, deadline: nil))
}

@Test func startingWithInvalidInputThrowsAndRunsNothing() {
    let rig = Rig()
    #expect(throws: KeepAwakeError.self) { try rig.controller.start(.invalid("bad")) }
    #expect(rig.runner.calls.isEmpty)
    #expect(rig.store.load() == nil)
}

@Test func stopRunsDisableSleepZeroAndForgetsTheSession() throws {
    let rig = Rig()
    let controller = rig.controller
    try controller.start(.indefinite)
    try controller.stop()
    #expect(rig.runner.calls == [sudoStart, sudoStop])
    #expect(rig.store.load() == nil)
}

@Test func stopStillRunsWhenIslandDidNotStartTheSession() throws {
    let rig = Rig()
    try rig.controller.stop()
    #expect(rig.runner.calls == [sudoStop])
}

@Test func tickDoesNothingBeforeTheDeadline() throws {
    let rig = Rig()
    let controller = rig.controller
    try controller.start(.minutes(5))
    rig.clock.advance(299)
    controller.tick()
    #expect(rig.runner.calls == [sudoStart])
}

@Test func tickAfterTheDeadlineStopsExactlyOnce() throws {
    let rig = Rig()
    let controller = rig.controller
    try controller.start(.minutes(5))
    rig.clock.advance(300)
    controller.tick()
    controller.tick()
    #expect(rig.runner.calls == [sudoStart, sudoStop])
    #expect(rig.store.load() == nil)
}

@Test func tickNeverStopsAnIndefiniteSession() throws {
    let rig = Rig()
    let controller = rig.controller
    try controller.start(.indefinite)
    rig.clock.advance(100 * 3600)
    controller.tick()
    #expect(rig.runner.calls == [sudoStart])
}

@Test func aMissingSudoersRuleIsReportedAsSuch() {
    let rig = Rig()
    rig.runner.handler = { _ in CommandResult(status: 1, stdout: "", stderr: "sudo: a password is required\n") }
    #expect(throws: KeepAwakeError.sudoersMissing) { try rig.controller.start(.indefinite) }
    #expect(rig.store.load() == nil)
}

@Test func anyOtherFailureCarriesTheErrorText() {
    let rig = Rig()
    rig.runner.handler = { _ in CommandResult(status: 1, stdout: "", stderr: "boom") }
    #expect(throws: KeepAwakeError.commandFailed("boom")) { try rig.controller.start(.indefinite) }
}

@Test func aFailedStopAtTheDeadlineIsKeptAsTheLastErrorAndRetried() throws {
    let rig = Rig()
    let controller = rig.controller
    try controller.start(.minutes(1))
    rig.runner.handler = { _ in CommandResult(status: 1, stdout: "", stderr: "sudo: a password is required") }
    rig.clock.advance(60)
    controller.tick()
    #expect(controller.lastError == .sudoersMissing)
    #expect(rig.store.load() != nil)
    controller.tick()
    #expect(rig.runner.calls.suffix(2) == [sudoStop, sudoStop])
}

@Test func recoverAfterACrashStopsASessionIslandLeftOn() throws {
    let rig = Rig()
    try rig.store.save(KeepAwakeState(startedByIsland: true, deadline: nil))
    rig.controller.recoverAfterCrash()
    #expect(rig.runner.calls == [sudoStop])
    #expect(rig.store.load() == nil)
}

@Test func recoverWithNoRememberedSessionRunsNothing() {
    let rig = Rig()
    rig.controller.recoverAfterCrash()
    #expect(rig.runner.calls.isEmpty)
}

@Test func quittingStopsOnlyASessionIslandStarted() throws {
    let started = Rig()
    try started.controller.start(.indefinite)
    started.controller.willTerminate()
    #expect(started.runner.calls == [sudoStart, sudoStop])

    // Something else (a terminal `stayawake`) disabled sleep: Island leaves it alone.
    let outside = Rig()
    outside.runner.handler = { call in
        call == pmsetRead ? CommandResult(status: 0, stdout: pmsetOutput(sleepDisabled: 1), stderr: "") : CommandResult(status: 0, stdout: "", stderr: "")
    }
    outside.controller.willTerminate()
    #expect(outside.runner.calls.isEmpty)
}

@Test func statusIsReadFromPmsetAndMatchesTheRememberedSession() throws {
    let rig = Rig()
    rig.runner.handler = { call in
        call == pmsetRead ? CommandResult(status: 0, stdout: pmsetOutput(sleepDisabled: 1), stderr: "") : CommandResult(status: 0, stdout: "", stderr: "")
    }
    #expect(rig.controller.refreshStatus() == .on(deadline: nil, startedByIsland: false))

    let deadline = rig.clock.now.addingTimeInterval(600)
    try rig.store.save(KeepAwakeState(startedByIsland: true, deadline: deadline))
    #expect(rig.controller.refreshStatus() == .on(deadline: deadline, startedByIsland: true))
}

@Test func statusIsOffWhenPmsetSaysSleepIsEnabledAndStaleStateIsForgotten() throws {
    let rig = Rig()
    rig.runner.handler = { call in
        call == pmsetRead ? CommandResult(status: 0, stdout: pmsetOutput(sleepDisabled: 0), stderr: "") : CommandResult(status: 0, stdout: "", stderr: "")
    }
    try rig.store.save(KeepAwakeState(startedByIsland: true, deadline: nil))
    #expect(rig.controller.refreshStatus() == .off)
    #expect(rig.store.load() == nil)
}

@Test func statusIsOffWhenPmsetCannotBeRead() {
    let rig = Rig()
    rig.runner.handler = { _ in CommandResult(status: 1, stdout: "", stderr: "nope") }
    #expect(rig.controller.refreshStatus() == .off)
}

@Test func theRememberedSessionIsExposedWithoutRunningAnyCommand() throws {
    let rig = Rig()
    let controller = rig.controller
    #expect(controller.session == nil)
    try controller.start(.minutes(2))
    #expect(controller.session == KeepAwakeState(startedByIsland: true, deadline: rig.clock.now.addingTimeInterval(120)))
    try controller.stop()
    #expect(controller.session == nil)
    #expect(rig.runner.calls == [sudoStart, sudoStop])
}

@Test func thePermissionCheckIsTheReadOnlySudoListQuery() {
    let granted = Rig()
    #expect(granted.controller.hasPermission())
    #expect(granted.runner.calls == [["/usr/bin/sudo", "-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]])

    let missing = Rig()
    missing.runner.handler = { _ in CommandResult(status: 1, stdout: "", stderr: "sudo: a password is required\n") }
    #expect(!missing.controller.hasPermission())
}

@Test func checkingThePermissionNeverChangesAnything() {
    let rig = Rig()
    _ = rig.controller.hasPermission()
    #expect(rig.store.load() == nil)
    #expect(!rig.runner.calls.contains(sudoStart) && !rig.runner.calls.contains(sudoStop))
}

@Test func processRunnerCapturesOutputAndStatus() throws {
    let runner = ProcessCommandRunner()
    let echo = try runner.run("/bin/echo", ["hello"])
    #expect(echo.status == 0)
    #expect(echo.stdout == "hello\n")
    let failure = try runner.run("/usr/bin/false", [])
    #expect(failure.status == 1)
}
