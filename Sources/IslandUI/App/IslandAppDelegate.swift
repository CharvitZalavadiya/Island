import AppKit
import IslandCore

@MainActor
public final class IslandAppDelegate: NSObject, NSApplicationDelegate {
    private var model: IslandModel?
    private var services: IslandServices?
    private var panelController: IslandPanelController?
    private var terminationSignal: DispatchSourceSignal?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions.parse(CommandLine.arguments)
        MainMenu.install()   // so ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z work in text boxes

        // A second copy would end the first copy's keep-awake session (it would look like a crashed one) and overwrite
        // its files, so quit before touching anything if Island is already running. A copy started with its own data
        // folder (`--support-dir`, for checking changes) shares nothing and may run alongside.
        if options.supportDirectory == nil, let identifier = Bundle.main.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { !$0.isTerminated }
                .map(\.processIdentifier)
            if SingleInstance.otherProcessID(among: running, current: ProcessInfo.processInfo.processIdentifier) != nil {
                exit(0)
            }
        }

        let support = Self.prepareSupportDirectory(options.supportDirectory)
        let settings = SettingsStore(
            store: FileStore(url: support.appendingPathComponent("settings.json"), defaultValue: Settings()))
        let model = IslandModel(settings: settings)
        // `--fast-pomodoro` treats configured minutes as seconds, for checking the timer by hand.
        let services = IslandServices(
            model: model, supportDirectory: support, fastPomodoro: options.fastPomodoro, updateFeedURL: options.updateFeedURL,
            // A copy started with its own data folder comes back the same way after an update.
            relaunchArguments: options.supportDirectory.map { ["--support-dir", $0.path] } ?? [])

        // `--debug-wings` lights up every live activity, for checking the wing layout.
        if options.debugWings {
            for kind in LiveActivityKind.allCases { model.setActivity(kind, active: true) }
        }

        let controller = IslandPanelController(model: model, services: services)
        controller.simulatesNoNotch = options.simulateNoNotch
        controller.show()
        self.model = model
        self.services = services
        self.panelController = controller

        services.start()
        // `--debug-start-pomodoro` starts the timer at launch, so CPU use can be measured while it runs.
        if options.debugStartPomodoro { services.pomodoro.start() }
        services.alerts.start()
        if let name = options.debugOpenTab, let tab = IslandTab(rawValue: name) {
            model.selectedTab = tab
            model.isPinned = true
        }
        if options.debugAlert { services.alerts.showSample() }
        if options.debugUpdateNow { Task { @MainActor in await services.update.runDebugUpdateNow() } }
        handleTerminationSignal()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        services?.willTerminate()
    }

    /// The folder for Island's data: the one given with `--support-dir` (created if needed), else the real one.
    private static func prepareSupportDirectory(_ override: URL?) -> URL {
        guard let override else { return AppPaths.supportDirectory() }
        try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
        return override
    }

    /// `kill` and `pkill` send SIGTERM; treat that as a normal quit so keep awake is switched off.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }
}

public func runIslandApp() -> Never {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = IslandAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
    exit(0)
}
