import Foundation

/// A program that is listening for connections on a TCP port.
public struct PortListener: Equatable, Identifiable {
    public var pid: Int
    public var command: String
    /// The address it listens on: `*`, `127.0.0.1`, `[::1]` and so on.
    public var address: String
    public var port: Int
    public var id: String { "\(pid):\(port)" }

    public init(pid: Int, command: String, address: String, port: Int) {
        self.pid = pid
        self.command = command
        self.address = address
        self.port = port
    }
}

public enum PortListing {
    /// The arguments for `lsof` that list every listening TCP port of the user's own programs: `+c 0` keeps the full
    /// program name, `-F pcn` asks for just the process id, name and address.
    public static let lsofArguments = ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]

    /// Reads the output of `lsof -F pcn`: a `p` line starts a program, `c` is its name, and each `n` line is an address
    /// it listens on. A program listening on the same port for IPv4 and IPv6 is listed once.
    public static func parse(lsofOutput: String) -> [PortListener] {
        var listeners: [PortListener] = []
        var seen = Set<String>()
        var pid: Int?
        var command = ""
        for line in lsofOutput.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int(value)
                command = ""
            case "c":
                command = value
            case "n":
                guard let pid, let (address, port) = split(value) else { continue }
                let listener = PortListener(pid: pid, command: command, address: address, port: port)
                if seen.insert(listener.id).inserted { listeners.append(listener) }
            default:
                break
            }
        }
        return listeners
    }

    /// "*:3000", "127.0.0.1:8080", "[::1]:5432" → (address, port).
    static func split(_ name: String) -> (String, Int)? {
        let text = name.split(separator: " ").first.map(String.init) ?? name
        guard let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]), (1...65_535).contains(port)
        else { return nil }
        return (String(text[..<colon]), port)
    }

    /// What to show for what was typed: a port number finds the ports that contain it; text finds programs by name.
    /// Nothing typed shows every listener, lowest port first.
    public static func filter(_ listeners: [PortListener], query: String) -> [PortListener] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = listeners.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
        guard !needle.isEmpty else { return sorted }
        if needle.allSatisfy(\.isNumber) {
            return sorted.filter { String($0.port).contains(needle) }
        }
        return sorted.filter { $0.command.localizedCaseInsensitiveContains(needle) }
    }
}
