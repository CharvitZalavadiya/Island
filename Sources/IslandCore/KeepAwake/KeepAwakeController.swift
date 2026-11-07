import Foundation

/// A keep-awake session Island started, remembered on disk so a crash can be cleaned up on the next launch.
public struct KeepAwakeState: Codable, Equatable {
    public var startedByIsland: Bool
    public var deadline: Date?

    public init(startedByIsland: Bool, deadline: Date?) {
        self.startedByIsland = startedByIsland
        self.deadline = deadline
    }
}

public enum KeepAwakeStatus: Equatable {
    case off
    case on(deadline: Date?, startedByIsland: Bool)
}

public enum KeepAwakeError: Error, Equatable {
    /// The passwordless sudo rule is not installed, so `sudo -n` was refused.
    case sudoersMissing
    case commandFailed(String)
    case invalidInput(String)
}

/// Does what a `stayawake` shell function does: `pmset -a disablesleep 1`, which keeps the Mac awake
/// even with the lid closed, and `pmset -a disablesleep 0` to restore normal sleep.
public final class KeepAwakeController {
    /// The last failure from an automatic stop (for example when the timer ends), for the UI to show.
    public private(set) var lastError: KeepAwakeError?

    /// The session Island started and still remembers, without running any command.
    public var session: KeepAwakeState? { state }

    private let runner: CommandRunner
    private let stateStore: FileStore<KeepAwakeState?>
    private let now: () -> Date
    private var state: KeepAwakeState?

    public init(runner: CommandRunner, stateStore: FileStore<KeepAwakeState?>, now: @escaping () -> Date = Date.init) {
        self.runner = runner
        self.stateStore = stateStore
        self.now = now
        self.state = stateStore.load()
    }

    /// Starts keeping the Mac awake for the typed minutes, or indefinitely.
    public func start(_ input: MinutesInput) throws {
        let deadline: Date?
        switch input {
        case .invalid(let message): throw KeepAwakeError.invalidInput(message)
        case .indefinite: deadline = nil
        case .minutes(let minutes): deadline = now().addingTimeInterval(TimeInterval(minutes) * 60)
        }
        // Remember the session before the command runs, so a crash right after it is still cleaned up.
        remember(KeepAwakeState(startedByIsland: true, deadline: deadline))
        do {
            try setSleepDisabled(true)
            lastError = nil
        } catch {
            remember(nil)
            throw error
        }
    }

    /// Restores normal sleep. Always runs the command, so it can also end a session started outside Island.
    public func stop() throws {
        try setSleepDisabled(false)
        remember(nil)
        lastError = nil
    }

    /// Call about once a second while a session is on: stops it when its deadline has passed.
    public func tick() {
        guard let deadline = state?.deadline, now() >= deadline else { return }
        do {
            try stop()
        } catch {
            lastError = error as? KeepAwakeError ?? .commandFailed("\(error)")
        }
    }

    /// On launch: if the last run left a session on (it crashed), turn it off.
    /// Never resets blindly, because that would end a `stayawake` session running in a terminal.
    public func recoverAfterCrash() {
        stopIfIslandStartedIt()
    }

    /// On quit: turn off only a session Island itself started.
    public func willTerminate() {
        stopIfIslandStartedIt()
    }

    /// Whether the passwordless rule is installed, asked with sudo's read-only list query (it changes nothing).
    public func hasPermission() -> Bool {
        guard let result = try? runner.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]) else {
            return false
        }
        return result.status == 0
    }

    /// Reads the real state from `pmset -g` so the UI stays truthful if something else changes it.
    public func refreshStatus() -> KeepAwakeStatus {
        guard let result = try? runner.run("/usr/bin/pmset", ["-g"]), result.status == 0 else { return .off }
        if Self.sleepDisabled(in: result.stdout) {
            return .on(deadline: state?.deadline, startedByIsland: state?.startedByIsland ?? false)
        }
        if state != nil { remember(nil) }  // the remembered session is stale: sleep is already back on
        return .off
    }

    // MARK: Internals

    private func stopIfIslandStartedIt() {
        guard state?.startedByIsland == true else { return }
        do {
            try stop()
        } catch {
            lastError = error as? KeepAwakeError ?? .commandFailed("\(error)")
        }
    }

    private func remember(_ newState: KeepAwakeState?) {
        state = newState
        try? stateStore.save(newState)
    }

    private func setSleepDisabled(_ disabled: Bool) throws {
        let result = try runner.run(
            "/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"])
        guard result.status == 0 else {
            let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let needsPassword = ["password is required", "a terminal is required", "no tty present"]
                .contains { text.localizedCaseInsensitiveContains($0) }
            throw needsPassword ? KeepAwakeError.sudoersMissing : KeepAwakeError.commandFailed(text)
        }
    }

    static func sleepDisabled(in output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return false
    }
}
