import AppKit
import ApplicationServices
import Foundation
import IslandCore

/// How an action went.
enum TapActionResult: Equatable {
    case done
    /// macOS only lets an app press keys once it has been allowed in Privacy & Security ▸ Accessibility.
    case needsAccessibility
    case unavailable(String)
}

/// Does what a tap was set to do.
@MainActor
protocol TrackpadActionPerforming: AnyObject {
    func perform(_ action: TrackpadTapAction, app: String?, shortcut: String?) -> TapActionResult
    var hasAccessibility: Bool { get }
    /// Asks macOS to show its "allow Accessibility" dialog.
    func requestAccessibility()
}

/// The real thing. Most actions open one of macOS's own apps, run one of its command-line tools, or call one of its libraries,
/// and so need no permission; only copy and paste (which press keys) need Accessibility.
@MainActor
final class SystemActionRunner: TrackpadActionPerforming {
    private let nowPlaying: NowPlayingController?

    init(nowPlaying: NowPlayingController? = nil) { self.nowPlaying = nowPlaying }

    var hasAccessibility: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func perform(_ action: TrackpadTapAction, app: String?, shortcut: String?) -> TapActionResult {
        switch action {
        case .none:
            return .done
        case .copy:
            return press(key: 8, flags: .maskCommand)                       // C
        case .paste:
            return press(key: 9, flags: .maskCommand)                       // V
        case .screenshot:
            return open("/System/Applications/Utilities/Screenshot.app")    // the same screenshot tools as Shift-Command-5
        case .missionControl:
            return open("/System/Applications/Mission Control.app")
        case .openApp:
            guard let app else { return .unavailable("Choose an app first") }
            return open(app)
        case .shortcut:
            guard let shortcut else { return .unavailable("Choose a Shortcut first") }
            return run("/usr/bin/shortcuts", ["run", shortcut])
        case .lockScreen:
            return lockScreen()
        case .screenSaver:
            return open("/System/Library/CoreServices/ScreenSaverEngine.app")
        case .displaySleep:
            return run("/usr/bin/pmset", ["displaysleepnow"])
        case .mute:
            return run("/usr/bin/osascript", ["-e", "set volume output muted (not (output muted of (get volume settings)))"])
        case .playPause:
            guard let nowPlaying else { return .unavailable("Can't reach the player") }
            nowPlaying.send(.togglePlayPause)
            return .done
        }
    }

    private func open(_ path: String) -> TapActionResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return .unavailable("Can't find \((path as NSString).lastPathComponent)")
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        return .done
    }

    /// Starts a tool and does not wait for it.
    private func run(_ tool: String, _ arguments: [String]) -> TapActionResult {
        guard FileManager.default.isExecutableFile(atPath: tool) else { return .unavailable("\((tool as NSString).lastPathComponent) is not here") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .unavailable("Couldn't start it") }
        return .done
    }

    private func press(key: CGKeyCode, flags: CGEventFlags) -> TapActionResult {
        guard hasAccessibility else {
            requestAccessibility()
            return .needsAccessibility
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                return .unavailable("macOS did not let Island press the key")
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        return .done
    }

    /// The private login library locks the screen at once with no permission; if it is ever not there, Control-Command-Q does it.
    private func lockScreen() -> TapActionResult {
        typealias Lock = @convention(c) () -> Int32
        if let library = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
            let symbol = dlsym(library, "SACLockScreenImmediate")
        {
            _ = unsafeBitCast(symbol, to: Lock.self)()
            return .done
        }
        return press(key: 12, flags: [.maskControl, .maskCommand])           // Q
    }
}

/// The person's own Shortcuts, by name, from the `shortcuts` tool that comes with macOS.
enum ShortcutsList {
    static func load() async -> [String] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }.value
    }
}
