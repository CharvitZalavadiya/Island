import Foundation

/// Command-line switches for checking Island by hand. A normal launch has none.
public struct LaunchOptions: Equatable {
    /// Lights up every live indicator at once, to check the wing layout.
    public var debugWings = false
    /// Treats the Pomodoro's configured minutes as seconds.
    public var fastPomodoro = false
    /// Starts the Pomodoro at launch, so CPU use can be measured while it runs.
    public var debugStartPomodoro = false
    /// Opens (and pins) the island on this tab at launch (`focus`, `clipboard`, `shelf`, `stats`, `camera`, `calendar`),
    /// so it can be looked at without touching the pointer.
    public var debugOpenTab: String?
    /// Shows a sample event alert at launch, to check the banner without waiting for a real event.
    public var debugAlert = false
    /// Keeps all of Island's data in this folder instead of the real one. A copy started this way cannot disturb a
    /// running Island (its keep-awake session, history or settings), so it may run beside it.
    public var supportDirectory: URL?

    /// Looks for updates at this address (a GitHub-style "latest release" answer) instead of GitHub's, to try the updater.
    public var updateFeedURL: URL?
    /// Checks for an update at launch and installs it at once if there is one, to try the updater without the Settings window.
    public var debugUpdateNow = false
    /// Behaves as if the screen had no notch (shows the artificial one), to check how Island looks on a Mac without one.
    public var simulateNoNotch = false

    public init() {}

    /// Reads the switches from `CommandLine.arguments`; anything unrecognised is ignored.
    public static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            switch arguments[index] {
            case "--debug-wings":
                options.debugWings = true
            case "--fast-pomodoro":
                options.fastPomodoro = true
            case "--debug-start-pomodoro":
                options.debugStartPomodoro = true
            case "--debug-alert":
                options.debugAlert = true
            case "--simulate-no-notch":
                options.simulateNoNotch = true
            case "--debug-update-now":
                options.debugUpdateNow = true
            case "--update-feed":
                let next = arguments.index(after: index)
                if next < arguments.endIndex, !arguments[next].hasPrefix("--") {
                    options.updateFeedURL = URL(string: arguments[next])
                    index = next
                }
            case "--debug-open":
                let next = arguments.index(after: index)
                if next < arguments.endIndex, !arguments[next].hasPrefix("--") {
                    options.debugOpenTab = arguments[next]
                    index = next
                }
            case "--support-dir":
                let next = arguments.index(after: index)
                if next < arguments.endIndex, !arguments[next].hasPrefix("--") {
                    options.supportDirectory = URL(fileURLWithPath: arguments[next])
                    index = next
                }
            default:
                break
            }
            index = arguments.index(after: index)
        }
        return options
    }
}
