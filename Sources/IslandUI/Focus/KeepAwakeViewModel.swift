import Foundation
import Observation
import IslandCore

/// Sets up and removes the passwordless permission keep awake needs. The real one is `SystemPermissionInstaller`
/// (macOS's own password dialog); tests use a fake.
public protocol PermissionInstalling {
    func install() async throws
    func remove() async throws
}

/// Asks macOS for the administrator password through its own dialog, for the current user, off the main thread
/// (the dialog stays open until the person answers).
struct SystemPermissionInstaller: PermissionInstalling {
    func install() async throws {
        try await Task.detached { try SudoersInstaller.install(user: NSUserName(), runner: ProcessCommandRunner()) }.value
    }

    func remove() async throws {
        try await Task.detached { try SudoersInstaller.remove(user: NSUserName(), runner: ProcessCommandRunner()) }.value
    }
}

/// Connects the keep-awake controller to the UI: the minutes box, Start and Stop, the live wing, the one-time
/// permission setup, and the launch and quit hooks. A one-second timer exists only while a timed session is on.
@Observable
@MainActor
public final class KeepAwakeViewModel {
    public enum Permission: Equatable {
        /// Not checked yet.
        case unknown
        /// The passwordless rule is installed, so Start works.
        case granted
        /// It is not installed: the card offers "Allow…" instead of Start.
        case missing
    }

    /// The minutes to stay awake, picked on the wheel (1 to 60). Values outside that are clamped when a session starts
    /// (a `didSet` that clamps would recurse forever inside an `@Observable` class).
    public var minutes = 30
    /// "Awake infinitely": stay awake until Stop. The wheel is not used then.
    public var isInfinite = false
    public static let minutesRange = 1...60
    public private(set) var status: KeepAwakeStatus = .off
    /// Seconds left in a timed session; nil when off or indefinite.
    public private(set) var remaining: TimeInterval?
    /// How long the timed session was meant to last, for the ring. Unknown for a session that was already running when
    /// Island started: then the time left at first sight is used.
    public private(set) var totalDuration: TimeInterval?
    public private(set) var message: String?
    public private(set) var permission: Permission = .unknown
    /// True while the password dialog (for allowing or removing the permission) is open.
    public private(set) var isWorking = false

    @ObservationIgnored private let model: IslandModel
    @ObservationIgnored private let controller: KeepAwakeController
    @ObservationIgnored private let installer: PermissionInstalling
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tickTimer: Timer?

    public init(
        model: IslandModel, controller: KeepAwakeController, installer: PermissionInstalling,
        now: @escaping () -> Date = Date.init
    ) {
        self.model = model
        self.controller = controller
        self.installer = installer
        self.now = now
    }

    static let needsPermissionMessage =
        "Keep awake needs your OK once. Press Allow… and macOS will ask for your password."

    /// On launch: clean up after a crash, then show the real state.
    public func launch() {
        controller.recoverAfterCrash()
        if let error = controller.lastError { message = Self.describe(error) }
        refreshPermission()
        refresh()
    }

    /// On quit: ends a session Island started, and leaves one started elsewhere alone.
    public func willTerminate() {
        controller.willTerminate()
    }

    // MARK: The permission

    public func refreshPermission() {
        permission = controller.hasPermission() ? .granted : .missing
    }

    /// Shows macOS's password dialog and installs the rule. Cancelling is not an error: nothing changes.
    public func grantPermission() async {
        guard permission != .granted, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await installer.install()
            message = nil
        } catch SudoersError.cancelled {
            message = nil
        } catch {
            message = "Couldn't set up keep awake: " + Self.describe(error)
        }
        refreshPermission()
    }

    /// Removes the permission again (another password dialog). A session Island started is ended first, because
    /// switching sleep back on needs the permission.
    public func revokePermission() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if case .on(_, true) = status { try? controller.stop() }
        do {
            try await installer.remove()
            message = nil
        } catch SudoersError.cancelled {
            message = nil
        } catch {
            message = "Couldn't remove the permission: " + Self.describe(error)
        }
        refreshPermission()
        refresh()
    }

    // MARK: Keep awake itself

    public func start() {
        if permission == .missing {
            message = Self.needsPermissionMessage
            return
        }
        do {
            let chosen = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
            try controller.start(isInfinite ? .indefinite : .minutes(chosen))
            totalDuration = isInfinite ? nil : TimeInterval(chosen) * 60
            message = nil
        } catch {
            if case KeepAwakeError.sudoersMissing = error { permission = .missing }
            message = Self.describe(error)
        }
        refresh()
    }

    public func stop() {
        do {
            try controller.stop()
            message = nil
        } catch {
            if case KeepAwakeError.sudoersMissing = error { permission = .missing }
            message = Self.describe(error)
        }
        refresh()
    }

    /// Once a second while a timed session is on: ends it at the deadline and updates the countdown.
    public func tick() {
        controller.tick()
        if let error = controller.lastError { message = Self.describe(error) }
        updateRemaining()
        // The session ended on its own: confirm the real state.
        if controller.session == nil, case .on(_, true) = status { refresh() }
    }

    /// Reads the real state from the system (one `pmset -g`). Called at launch, after Start/Stop, and when the island opens.
    public func refresh() {
        status = controller.refreshStatus()
        updateRemaining()
        model.setActivity(.keepAwake, active: status != .off)
        updateTimer()
    }

    /// How much of a timed session is left, 1 down to 0, for the ring; nil when there is no timed session.
    public var progress: Double? {
        guard let remaining, let totalDuration, totalDuration > 0 else { return nil }
        return min(max(remaining / totalDuration, 0), 1)
    }

    /// A short label for the collapsed wing: "∞", "12m", or "3h".
    nonisolated public static func compactLabel(remaining: TimeInterval?) -> String {
        guard let remaining else { return "∞" }
        let minutes = Int((max(remaining, 0) / 60).rounded(.up))
        return minutes <= 99 ? "\(minutes)m" : "\(Int((remaining / 3600).rounded(.up)))h"
    }

    // MARK: Internals

    private func updateRemaining() {
        if case .on(let deadline?, _) = status {
            remaining = max(0, deadline.timeIntervalSince(now()))
            if totalDuration == nil { totalDuration = remaining }
        } else {
            remaining = nil
            if status == .off { totalDuration = nil }
        }
    }

    private func updateTimer() {
        if case .on(.some, _) = status {
            guard tickTimer == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case KeepAwakeError.sudoersMissing:
            return needsPermissionMessage
        case KeepAwakeError.commandFailed(let text):
            return "Couldn't change the sleep setting: \(text)"
        case KeepAwakeError.invalidInput(let text):
            return text
        case SudoersError.invalidUser:
            return "Island couldn't use your account name for this."
        case SudoersError.cancelled:
            return "The password dialog was cancelled."
        case SudoersError.failed(let text):
            return text
        default:
            return error.localizedDescription
        }
    }
}
