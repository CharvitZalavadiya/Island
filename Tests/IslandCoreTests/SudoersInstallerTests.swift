import Testing
import Foundation
@testable import IslandCore

/// Runs a shell command as the current (normal) user, as the install command would run as root.
private func sh(_ command: String) throws -> CommandResult {
    try ProcessCommandRunner().run("/bin/sh", ["-c", command])
}

private let aliceRule = "alice ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"

// MARK: User names (they end up inside a root shell command, so they must be strictly checked)

@Test func ordinaryUserNamesAreValid() {
    for name in ["alice", "a.b", "a-b", "_svc", "Charvit2", "A", "first.last"] {
        #expect(SudoersInstaller.isValidUserName(name), "\(name)")
    }
}

@Test func anythingThatCouldBeShellOrSudoersSyntaxIsInvalid() {
    let bad = [
        "", "a b", "a;rm -rf /", "$(x)", "a'b", "-x", String(repeating: "a", count: 33), "a/b", "é", ".hidden",
        "a\nb", "a\"b", "a`b`", "a#b", "a,b", "a=b", "a\\b", "a:b", "%admin", "!x",
    ]
    for name in bad {
        #expect(!SudoersInstaller.isValidUserName(name), "[\(name)] should be rejected")
    }
}

// MARK: The rule

@Test func theRuleIsForTheGivenUserAndOnlyTheTwoPmsetForms() {
    let rule = SudoersInstaller.rule(for: "alice")
    #expect(rule == aliceRule)
    // Exactly two allowed commands, both pmset with fixed arguments: nothing else can be run without a password.
    let allowed = rule.components(separatedBy: "NOPASSWD:")[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(allowed == ["/usr/bin/pmset -a disablesleep 0", "/usr/bin/pmset -a disablesleep 1"])
}

@Test func theRuleFileIsNamedPerUserWithoutDots() {
    #expect(SudoersInstaller.fileName(for: "alice") == "island-alice")
    #expect(SudoersInstaller.fileName(for: "first.last") == "island-first_last")   // sudo ignores file names with a dot
    #expect(!SudoersInstaller.fileName(for: "a.b.c").contains("."))
}

@Test func anInvalidUserGetsNoCommandAtAll() {
    #expect(SudoersInstaller.installCommand(user: "a;b") == nil)
    #expect(SudoersInstaller.removeCommand(user: "a;b") == nil)
    #expect(SudoersInstaller.installCommand(user: "") == nil)
}

// MARK: The install command (run here as a normal user, in a temp folder)

@Test func theInstallCommandWritesAValidRuleFileWithTheRightMode() throws {
    let directory = makeTempDirectory()
    let command = try #require(SudoersInstaller.installCommand(user: "alice", directory: directory.path))
    let result = try sh(command)
    #expect(result.status == 0, "\(result.stderr)")

    let file = directory.appendingPathComponent("island-alice")
    #expect(try String(contentsOf: file, encoding: .utf8) == aliceRule + "\n")
    let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
    #expect(mode == 0o440)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["island-alice"])   // no .tmp left
    // sudo itself accepts the file.
    #expect(try ProcessCommandRunner().run("/usr/sbin/visudo", ["-cf", file.path]).status == 0)
}

@Test func installingAgainReplacesTheFileAndKeepsOnlyOne() throws {
    let directory = makeTempDirectory()
    let command = try #require(SudoersInstaller.installCommand(user: "alice", directory: directory.path))
    #expect(try sh(command).status == 0)
    #expect(try sh(command).status == 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["island-alice"])
}

@Test func aFailedInstallExitsNonZeroAndLeavesNothingBehind() throws {
    let directory = makeTempDirectory()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)   // read-only
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
    let command = try #require(SudoersInstaller.installCommand(user: "alice", directory: directory.path))
    let result = try sh(command)
    #expect(result.status != 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test func theInstallCommandNeverTouchesOtherFilesInTheFolder() throws {
    let directory = makeTempDirectory()
    try "keep me".write(to: directory.appendingPathComponent("someone-else"), atomically: true, encoding: .utf8)
    let command = try #require(SudoersInstaller.installCommand(user: "alice", directory: directory.path))
    #expect(try sh(command).status == 0)
    #expect(try String(contentsOf: directory.appendingPathComponent("someone-else"), encoding: .utf8) == "keep me")
}

@Test func theRemoveCommandDeletesOnlyThatUsersFile() throws {
    let directory = makeTempDirectory()
    for user in ["alice", "bob"] {
        let install = try #require(SudoersInstaller.installCommand(user: user, directory: directory.path))
        #expect(try sh(install).status == 0)
    }
    let remove = try #require(SudoersInstaller.removeCommand(user: "alice", directory: directory.path))
    #expect(try sh(remove).status == 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["island-bob"])
    #expect(try sh(remove).status == 0)   // removing again is not an error
}

@Test func aDirectoryNameWithSpacesAndQuotesIsHandled() throws {
    let base = makeTempDirectory().appendingPathComponent("it's a folder with spaces", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let command = try #require(SudoersInstaller.installCommand(user: "alice", directory: base.path))
    #expect(try sh(command).status == 0)
    #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("island-alice").path))
}

// MARK: The password dialog

@Test func theAppleScriptEscapesQuotesAndBackslashes() {
    let script = SudoersInstaller.appleScript(running: #"echo "hi" \n"#, prompt: #"Say "hi""#)
    #expect(script == #"do shell script "echo \"hi\" \\n" with administrator privileges with prompt "Say \"hi\"""#)
}

@Test func installRunsOsascriptOnceWithTheInstallCommand() throws {
    let runner = FakeRunner()
    try SudoersInstaller.install(user: "alice", runner: runner)
    #expect(runner.calls.count == 1)
    let call = try #require(runner.calls.first)
    #expect(Array(call.prefix(2)) == ["/usr/bin/osascript", "-e"])
    #expect(call[2].contains("with administrator privileges"))
    #expect(call[2].contains("island-alice"))
    #expect(call[2].contains(aliceRule))
}

@Test func removeRunsOsascriptWithTheRemoveCommand() throws {
    let runner = FakeRunner()
    try SudoersInstaller.remove(user: "alice", runner: runner)
    let call = try #require(runner.calls.first)
    #expect(call[2].contains("rm -f"))
    #expect(call[2].contains("island-alice"))
    #expect(!call[2].contains("NOPASSWD"))
}

@Test func cancellingThePasswordDialogIsReportedAsCancelled() {
    let runner = FakeRunner()
    runner.handler = { _ in
        CommandResult(status: 1, stdout: "", stderr: "0:123: execution error: User canceled. (-128)\n")
    }
    #expect(throws: SudoersError.cancelled) { try SudoersInstaller.install(user: "alice", runner: runner) }
}

@Test func anyOtherFailureCarriesItsText() {
    let runner = FakeRunner()
    runner.handler = { _ in CommandResult(status: 1, stdout: "", stderr: "visudo: syntax error\n") }
    #expect(throws: SudoersError.failed("visudo: syntax error")) { try SudoersInstaller.install(user: "alice", runner: runner) }
}

@Test func anInvalidUserNeverReachesTheRunner() {
    let runner = FakeRunner()
    #expect(throws: SudoersError.invalidUser) { try SudoersInstaller.install(user: "a;b", runner: runner) }
    #expect(throws: SudoersError.invalidUser) { try SudoersInstaller.remove(user: "a;b", runner: runner) }
    #expect(runner.calls.isEmpty)
}

// MARK: The generated AppleScript is real, valid AppleScript (checked without running anything privileged)

@Test func theInstallAndRemoveScriptsCompileAsAppleScript() throws {
    for user in ["alice", "first.last", "_svc"] {
        for command in [SudoersInstaller.installCommand(user: user), SudoersInstaller.removeCommand(user: user)] {
            let script = SudoersInstaller.appleScript(running: try #require(command), prompt: "Island needs your password once.")
            let output = makeTempDirectory().appendingPathComponent("check.scpt")
            // osacompile only compiles. Nothing runs and no password dialog appears.
            let result = try ProcessCommandRunner().run("/usr/bin/osacompile", ["-e", script, "-o", output.path])
            #expect(result.status == 0, "\(user): \(result.stderr)")
        }
    }
}

@Test func theEscapingSurvivesARoundTripThroughAppleScriptAndTheShell() throws {
    // The same escaping, run without the administrator part: quotes and backslashes must arrive intact.
    let payload = #"printf '%s' 'a"b\c $HOME `x`'"#
    let prompt = "x"
    let full = SudoersInstaller.appleScript(running: payload, prompt: prompt)
    let tail = " with administrator privileges with prompt \"\(prompt)\""
    #expect(full.hasSuffix(tail))
    let plain = String(full.dropLast(tail.count))
    let result = try ProcessCommandRunner().run("/usr/bin/osascript", ["-e", plain])
    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout == #"a"b\c $HOME `x`"# + "\n")
}
