import Foundation

public enum KillOutcome: Equatable {
    /// The signal was sent (the program may still take a moment to exit).
    case signalled
    /// macOS did not allow it: the program belongs to another user or to the system.
    case notPermitted
    /// The program had already gone.
    case gone
    /// Island will not do this one.
    case refused(String)
}

/// Asks a program to quit, or stops it. It refuses the two things that must never be done from here: stopping the
/// system's first process, and stopping Island itself.
public struct ProcessKiller {
    /// Sends a signal to a process and returns 0 or the error number. Tests replace it.
    public var send: (Int32, Int32) -> Int32
    public var ownPID: Int32

    public init(
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        send: @escaping (Int32, Int32) -> Int32 = { pid, signal in kill(pid, signal) == 0 ? 0 : errno }
    ) {
        self.ownPID = ownPID
        self.send = send
    }

    /// `force` stops it at once (SIGKILL); otherwise it is asked to quit (SIGTERM) and may save its work first.
    public func terminate(pid: Int, force: Bool) -> KillOutcome {
        guard pid > 1 else { return .refused("That is a system process.") }
        guard pid != Int(ownPID) else { return .refused("That is Island itself.") }
        switch send(Int32(pid), force ? SIGKILL : SIGTERM) {
        case 0: return .signalled
        case ESRCH: return .gone
        case EPERM: return .notPermitted
        default: return .notPermitted
        }
    }
}
