import Foundation

public enum AppPaths {
    /// `~/Library/Application Support/Island`, created if needed. `base` replaces Application Support (for tests).
    public static func supportDirectory(base: URL? = nil) -> URL {
        let root = base
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("Island", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
