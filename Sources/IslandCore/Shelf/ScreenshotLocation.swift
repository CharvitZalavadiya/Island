import Foundation

public enum ScreenshotLocation {
    /// Where macOS saves screenshots, from the `location` value of `com.apple.screencapture`.
    /// Not set means the Desktop; a leading `~` means the home folder.
    public static func resolve(defaultsValue: String?, home: URL) -> URL {
        let raw = defaultsValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return home.appendingPathComponent("Desktop") }
        if raw == "~" { return URL(fileURLWithPath: home.path) }
        if raw.hasPrefix("~/") { return URL(fileURLWithPath: home.path + "/" + raw.dropFirst(2)) }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        return URL(fileURLWithPath: home.path + "/" + raw)
    }
}
