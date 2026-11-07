import Foundation

/// Persists one Codable value as JSON in a single file.
/// A missing or unreadable file yields the default value; a corrupt file is kept as `<name>.corrupt`.
public struct FileStore<T: Codable> {
    public let url: URL
    private let defaultValue: T

    public init(url: URL, defaultValue: T) {
        self.url = url
        self.defaultValue = defaultValue
    }

    public func load() -> T {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return defaultValue
        }
    }

    public func save(_ value: T) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
}
