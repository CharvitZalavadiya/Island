import Foundation

/// How soon an app that was opened with the password asks again once the person has left it.
public enum AppLockRelock: String, CaseIterable, Sendable {
    case everyTime, oneMinute, fiveMinutes, fifteenMinutes, whenAppQuits

    public var title: String {
        switch self {
        case .everyTime: "Every time"
        case .oneMinute: "After 1 minute away"
        case .fiveMinutes: "After 5 minutes away"
        case .fifteenMinutes: "After 15 minutes away"
        case .whenAppQuits: "Only after the app quits"
        }
    }

    /// How long the person may be away before it asks again; nil when time never makes it ask again.
    public var seconds: TimeInterval? {
        switch self {
        case .everyTime: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .whenAppQuits: nil
        }
    }
}

/// Which apps App lock will not take: the ones Island or the Mac itself cannot work without, and Island.
public enum AppLockRules {
    /// Finder is behind every desktop click, so locking it would put the lock in the way of the whole Mac.
    public static let neverLocked: Set<String> = [
        "com.apple.finder", "com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver", "com.apple.SecurityAgent",
    ]

    public static func canLock(_ bundleIdentifier: String, island: String?) -> Bool {
        !bundleIdentifier.isEmpty && bundleIdentifier != island && !neverLocked.contains(bundleIdentifier)
    }
}

/// Which locked apps the person has opened (by process), and so which must ask for the password when they come to the front.
/// Nothing here outlives Island: it is all in memory, so quitting Island forgets it, and with nothing running nothing asks.
public struct AppLockPolicy: Sendable {
    public var relock: AppLockRelock
    private var sessions: [Int32: Session] = [:]

    private enum Session: Sendable {
        case inUse
        case away(since: Date)
    }

    public init(relock: AppLockRelock = .everyTime) { self.relock = relock }

    /// A locked app came to the front. Returns whether it must ask for the password; if not, it is in use again.
    public mutating func comesToFront(pid: Int32, now: Date) -> Bool {
        guard let session = sessions[pid] else { return true }
        switch session {
        case .inUse:
            return false
        case .away(let since):
            // A clock that went backwards counts as time that has passed: when unsure it asks.
            if let seconds = relock.seconds, now >= since, now.timeIntervalSince(since) < seconds {
                sessions[pid] = .inUse
                return false
            }
            if relock.seconds == nil {
                sessions[pid] = .inUse
                return false
            }
            sessions[pid] = nil
            return true
        }
    }

    /// The person opened the app with the password (or Touch ID).
    public mutating func opened(pid: Int32) { sessions[pid] = .inUse }

    /// The app is no longer in front (the person went to another app).
    public mutating func leftFront(pid: Int32, at date: Date) {
        if case .inUse? = sessions[pid] { sessions[pid] = .away(since: date) }
    }

    public mutating func quit(pid: Int32) { sessions[pid] = nil }

    /// Every app asks again: the Mac went to sleep or was locked, or the lock was changed.
    public mutating func forgetAll() { sessions = [:] }
}

/// Wrong tries at the password: after a few, it makes the person wait a little before the next one, longer each time.
public struct AppLockAttempts: Sendable {
    public static let freeTries = 5
    private(set) var failures = 0
    private(set) var pausedUntil = Date.distantPast

    public init() {}

    /// How many seconds before the next try is allowed (0 when one is allowed now).
    public func wait(now: Date) -> TimeInterval { max(0, pausedUntil.timeIntervalSince(now)) }

    public mutating func failed(now: Date) {
        failures += 1
        guard failures >= Self.freeTries else { return }
        let steps = min(failures - Self.freeTries, 4)               // 5, 10, 20, 40, 80 seconds
        pausedUntil = now.addingTimeInterval(5 * pow(2, Double(steps)))
    }

    public mutating func succeeded() {
        failures = 0
        pausedUntil = .distantPast
    }
}
