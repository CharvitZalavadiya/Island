import Foundation

/// Picks names for files Island creates, so it never overwrites anything.
public enum OutputNamer {
    /// `desired` if nothing is there, otherwise the same name with " 2", " 3", ... before the extension.
    public static func uniqueURL(
        for desired: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        guard fileExists(desired) else { return desired }
        let directory = desired.deletingLastPathComponent()
        let ext = desired.pathExtension
        let base = desired.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileExists(candidate) { return candidate }
            number += 1
        }
    }
}
