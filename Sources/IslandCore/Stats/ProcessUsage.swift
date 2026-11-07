import Foundation

/// One line of `ps -axo pid=,pcpu=,rss=,comm=`.
public struct ProcessRow: Equatable {
    public var pid: Int
    /// Percent of one core, so a busy multi-threaded process can read above 100.
    public var cpuPercent: Double
    public var residentBytes: UInt64
    public var path: String

    public init(pid: Int, cpuPercent: Double, residentBytes: UInt64, path: String) {
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.path = path
    }
}

/// What one app (all its helper processes together) is using.
public struct AppUsage: Equatable, Identifiable {
    public var name: String
    public var cpuPercent: Double
    public var residentBytes: UInt64
    public var id: String { name }

    public init(name: String, cpuPercent: Double, residentBytes: UInt64) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
    }
}

public enum Metric: Equatable {
    case cpu, memory
}

public enum ProcessUsage {
    /// Reads `ps -axo pid=,pcpu=,rss=,comm=`: three numbers, then the rest of the line is the path, which may contain
    /// spaces. `rss` is in kilobytes. Blank and malformed lines are skipped.
    public static func parse(psOutput: String) -> [ProcessRow] {
        psOutput.split(whereSeparator: \.isNewline).compactMap { line in
            var rest = Substring(line)
            func nextField() -> Substring? {
                rest = rest.drop(while: \.isWhitespace)
                let field = rest.prefix(while: { !$0.isWhitespace })
                rest = rest.dropFirst(field.count)
                return field.isEmpty ? nil : field
            }
            guard let pidText = nextField(), let cpuText = nextField(), let rssText = nextField(),
                let pid = Int(pidText), pid >= 0,
                // A locale that prints "1,5" instead of "1.5" is understood too.
                let cpu = Double(cpuText.replacingOccurrences(of: ",", with: ".")), cpu.isFinite, cpu >= 0,
                let kilobytes = UInt64(rssText)
            else { return nil }
            let path = rest.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            return ProcessRow(pid: pid, cpuPercent: cpu, residentBytes: kilobytes * 1024, path: path)
        }
    }

    /// Adds up processes per app. A process inside `Some App.app` (helpers and nested login items included) counts
    /// towards "Some App"; anything else is named after its executable. Sorted by name.
    public static func aggregate(_ rows: [ProcessRow]) -> [AppUsage] {
        var totals: [String: (cpu: Double, bytes: UInt64)] = [:]
        for row in rows {
            let name = appName(of: row.path)
            let existing = totals[name] ?? (0, 0)
            totals[name] = (existing.cpu + row.cpuPercent, existing.bytes + row.residentBytes)
        }
        return totals
            .map { AppUsage(name: $0.key, cpuPercent: $0.value.cpu, residentBytes: $0.value.bytes) }
            .sorted { $0.name < $1.name }
    }

    /// The `limit` biggest by `metric`, biggest first; equal values are ordered by name so the list does not shuffle.
    public static func top(_ apps: [AppUsage], by metric: Metric, limit: Int) -> [AppUsage] {
        let sorted = apps.sorted { lhs, rhs in
            switch metric {
            case .cpu where lhs.cpuPercent != rhs.cpuPercent: return lhs.cpuPercent > rhs.cpuPercent
            case .memory where lhs.residentBytes != rhs.residentBytes: return lhs.residentBytes > rhs.residentBytes
            default: return lhs.name < rhs.name
            }
        }
        return Array(sorted.prefix(max(limit, 0)))
    }

    /// The app a program lives in ("Google Chrome" for a helper inside Google Chrome.app), or its own file name when it is
    /// not inside an app.
    public static func appBundleName(of path: String) -> String { appName(of: path) }

    private static func appName(of path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if let bundle = components.first(where: { $0.hasSuffix(".app") && $0.count > 4 }) {
            return String(bundle.dropLast(4))
        }
        return (path as NSString).lastPathComponent
    }
}
