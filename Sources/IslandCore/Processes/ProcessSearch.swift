import Foundation

public enum ProcessSearch {
    public struct Match: Equatable, Identifiable {
        public var pid: Int
        /// The program's own name ("Google Chrome Helper").
        public var name: String
        /// The app it belongs to ("Google Chrome"), when it lives inside one.
        public var app: String?
        public var residentBytes: UInt64
        public var id: Int { pid }
    }

    /// Programs whose name (or app's name) contains `query`, the closest names first and then the biggest. With nothing
    /// typed, the biggest programs. Never includes the system's first process or Island itself.
    public static func matches(
        _ rows: [ProcessRow], query: String, excludingPID: Int, limit: Int = 40
    ) -> [Match] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [(Match, Int)] = []
        for row in rows where row.pid > 1 && row.pid != excludingPID {
            let name = (row.path as NSString).lastPathComponent
            let app = ProcessUsage.appBundleName(of: row.path)
            let match = Match(pid: row.pid, name: name, app: app == name ? nil : app, residentBytes: row.residentBytes)
            if needle.isEmpty {
                results.append((match, 2))
            } else if name.localizedCaseInsensitiveContains(needle) || app.localizedCaseInsensitiveContains(needle) {
                // 0 for a name that starts with what was typed, 1 for one that merely contains it.
                let starts = name.lowercased().hasPrefix(needle.lowercased()) || app.lowercased().hasPrefix(needle.lowercased())
                results.append((match, starts ? 0 : 1))
            }
        }
        let ordered = results.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.residentBytes != rhs.0.residentBytes { return lhs.0.residentBytes > rhs.0.residentBytes }
            return lhs.0.pid < rhs.0.pid
        }
        return ordered.prefix(limit).map(\.0)
    }
}
