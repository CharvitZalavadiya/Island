import AppKit

/// An app that is running, as far as App lock needs to know it.
struct RunningApp: Equatable {
    var pid: Int32
    var bundleID: String?
    var name: String
    /// An app with a Dock icon. The little helper programs macOS starts to ask for a fingerprint or a password are not: they are
    /// not "the person going to another app".
    var isRegular: Bool
}

enum AppLockWorkspaceEvent {
    /// An app came to the front.
    case activated(RunningApp)
    case terminated(pid: Int32)
    /// The Mac is going to sleep, or was locked, or the screen saver started: every locked app asks again afterwards.
    case locked
}

/// What App lock asks of the Mac about other apps. It can look, bring an app to the front, and hide one (⌘H). It CANNOT quit,
/// freeze or change an app, so no mistake in App lock can ever leave an app stuck: this is on purpose.
@MainActor
protocol AppLockWorkspace: AnyObject {
    var frontmost: RunningApp? { get }
    /// The apps with a Dock icon, for choosing one to lock.
    func runningApps() -> [RunningApp]
    func isRunning(pid: Int32) -> Bool
    /// Where the app's windows are, in screen coordinates (empty when unknown).
    func windowFrames(of pid: Int32) -> [CGRect]
    /// Hides the app, as ⌘H does. It comes back when the person opens it.
    func hide(pid: Int32)
    /// Shows the app if it was hidden and brings it to the front.
    func bringToFront(pid: Int32)
    /// Starts telling `handler` what happens; the result stops it.
    func observe(_ handler: @escaping @MainActor (AppLockWorkspaceEvent) -> Void) -> () -> Void
}

@MainActor
final class SystemAppLockWorkspace: AppLockWorkspace {
    var frontmost: RunningApp? { NSWorkspace.shared.frontmostApplication.map(Self.app) }

    func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }.map(Self.app)
    }

    func isRunning(pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } ?? false }

    func windowFrames(of pid: Int32) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        // Window lists put the origin at the top left of the main screen; AppKit puts it at the bottom left.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? Int32 == pid, info[kCGWindowLayer as String] as? Int == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    func hide(pid: Int32) { NSRunningApplication(processIdentifier: pid)?.hide() }

    func bringToFront(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.unhide()
        _ = app.activate(from: NSRunningApplication.current, options: [])
    }

    func observe(_ handler: @escaping @MainActor (AppLockWorkspaceEvent) -> Void) -> () -> Void {
        let center = NSWorkspace.shared.notificationCenter
        var tokens: [(NotificationCenter, NSObjectProtocol)] = []
        // The notifications are delivered on the main queue, so the handler (which belongs to the main actor) may run at once.
        func add(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (Notification) -> Void) {
            tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { body(note) }
            }))
        }
        add(center, NSWorkspace.didActivateApplicationNotification) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { handler(.activated(Self.app(app))) }
        }
        add(center, NSWorkspace.didTerminateApplicationNotification) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                handler(.terminated(pid: app.processIdentifier))
            }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            add(center, name) { _ in handler(.locked) }
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            add(DistributedNotificationCenter.default(), Notification.Name(name)) { _ in handler(.locked) }
        }
        return { for (center, token) in tokens { center.removeObserver(token) } }
    }

    private static func app(_ running: NSRunningApplication) -> RunningApp {
        RunningApp(
            pid: running.processIdentifier, bundleID: running.bundleIdentifier,
            name: running.localizedName ?? running.bundleIdentifier ?? "This app", isRegular: running.activationPolicy == .regular)
    }
}
