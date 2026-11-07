import Foundation

public enum ClockFormat {
    /// `mm:ss`, rounded up so a running countdown never reads 00:00 before it ends. Minutes keep counting past 59.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// `mm:ss`, or `h:mm:ss` from one hour on, rounded down.
    public static func stopwatch(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }
}
