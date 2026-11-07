import Foundation
import Observation
import IslandCore

/// The "kill a program / free a port" tool on the Awake tab: it lists programs or listening ports, filters them as you
/// type, and stops one after a second tap. Afterwards it checks whether the program really went away and the port is
/// really free.
@Observable
@MainActor
final class ProcessToolsController {
    enum Mode { case processes, ports }

    struct Message: Equatable {
        enum Tone { case neutral, good, bad }
        var text: String
        var tone: Tone
    }

    var mode: Mode = .processes
    var query = ""
    private(set) var processRows: [ProcessRow] = []
    private(set) var listeners: [PortListener] = []
    private(set) var message: Message?
    /// The program that has had its first tap and waits for the second.
    private(set) var armedPID: Int?
    /// Programs that ignored a polite quit; the next tap stops them for good.
    private(set) var stubborn: Set<Int> = []

    @ObservationIgnored private let readProcesses: @Sendable () -> String
    @ObservationIgnored private let readPorts: @Sendable () -> String
    @ObservationIgnored private let killer: ProcessKiller
    @ObservationIgnored private let settleSeconds: TimeInterval
    @ObservationIgnored private var armTimer: Timer?

    init(
        readProcesses: @escaping @Sendable () -> String = { ProcessToolsController.run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="]) },
        readPorts: @escaping @Sendable () -> String = { ProcessToolsController.run("/usr/sbin/lsof", PortListing.lsofArguments) },
        killer: ProcessKiller = ProcessKiller(),
        settleSeconds: TimeInterval = 0.8
    ) {
        self.readProcesses = readProcesses
        self.readPorts = readPorts
        self.killer = killer
        self.settleSeconds = settleSeconds
    }

    // MARK: What is shown

    var processMatches: [ProcessSearch.Match] {
        ProcessSearch.matches(processRows, query: query, excludingPID: Int(killer.ownPID))
    }

    var portMatches: [PortListener] {
        PortListing.filter(listeners, query: query)
    }

    /// A port number was typed and nothing listens on it: it is free.
    var freePort: Int? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .ports, !text.isEmpty, text.allSatisfy(\.isNumber), let port = Int(text), (1...65_535).contains(port)
        else { return nil }
        return listeners.contains { $0.port == port } ? nil : port
    }

    // MARK: Reading

    /// Reads the list for the current mode (off the main thread).
    func refresh() async {
        switch mode {
        case .processes:
            let read = readProcesses
            let output = await Task.detached { read() }.value
            processRows = ProcessUsage.parse(psOutput: output)
        case .ports:
            let read = readPorts
            let output = await Task.detached { read() }.value
            listeners = PortListing.parse(lsofOutput: output)
        }
    }

    func setMode(_ newMode: Mode) async {
        guard newMode != mode else { return }
        mode = newMode
        message = nil
        disarm()
        await refresh()
    }

    // MARK: Stopping

    /// The first tap arms the button; the second (within a few seconds) stops the program.
    func tapKill(pid: Int, name: String, port: Int? = nil) async {
        guard armedPID == pid else {
            arm(pid)
            let verb = stubborn.contains(pid) ? "force quit" : "quit"
            message = Message(text: "Tap again to \(verb) \(name).", tone: .neutral)
            return
        }
        disarm()
        let force = stubborn.contains(pid)
        switch killer.terminate(pid: pid, force: force) {
        case .refused(let reason):
            message = Message(text: reason, tone: .bad)
        case .notPermitted:
            message = Message(text: "macOS won't let Island stop \(name): it belongs to the system or another user.", tone: .bad)
        case .gone:
            message = Message(text: "\(name) had already stopped.", tone: .good)
            await refresh()
        case .signalled:
            try? await Task.sleep(nanoseconds: UInt64(settleSeconds * 1_000_000_000))
            await refreshBoth()
            let stillRunning = processRows.contains { $0.pid == pid } || listeners.contains { $0.pid == pid }
            if stillRunning {
                stubborn.insert(pid)
                message = Message(text: "\(name) is still running. Tap again to force quit it.", tone: .neutral)
            } else {
                stubborn.remove(pid)
                if let port, !listeners.contains(where: { $0.port == port }) {
                    message = Message(text: "\(name) stopped. Port \(port) is free.", tone: .good)
                } else {
                    message = Message(text: "\(name) stopped.", tone: .good)
                }
            }
        }
    }

    func clearMessage() { message = nil }

    // MARK: Internals

    /// After a stop both lists matter: the program may be in either.
    private func refreshBoth() async {
        let readP = readProcesses, readL = readPorts
        async let processes = Task.detached { readP() }.value
        async let ports = Task.detached { readL() }.value
        let (psOutput, lsofOutput) = await (processes, ports)
        processRows = ProcessUsage.parse(psOutput: psOutput)
        listeners = PortListing.parse(lsofOutput: lsofOutput)
    }

    private func arm(_ pid: Int) {
        armedPID = pid
        armTimer?.invalidate()
        armTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.disarm() }
        }
    }

    private func disarm() {
        armTimer?.invalidate()
        armTimer = nil
        armedPID = nil
    }

    nonisolated static func run(_ executable: String, _ arguments: [String]) -> String {
        (try? ProcessCommandRunner().run(executable, arguments))?.stdout ?? ""
    }
}
