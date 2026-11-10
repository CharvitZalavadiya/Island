import AVFoundation
import Foundation
import IslandCore

/// The long-lived objects behind the island's features. Later features add their controllers here.
@MainActor
public final class IslandServices {
    public let pomodoro: PomodoroController
    public let keepAwake: KeepAwakeViewModel
    public let focus: FocusStatusMonitor
    let clipboard: ClipboardController
    let shelf: ShelfController
    let stats = StatsSampler()
    let mixer = AudioMixerController()
    let launchAtLogin: LaunchAtLoginController
    private let settingsWindow: SettingsWindowController
    let camera: CameraController
    let calendarSource: CalendarEventSource
    let calendar: CalendarController
    let alerts: AlertScheduler
    let lockSounds: LockSoundController
    let tasks: TasksController
    let todoist: TodoistController
    let github: GitHubController
    let update: UpdateController
    let teams: TeamsController
    let browser: BrowserController
    let settings: SettingsStore
    let ambient: AmbientPlayer
    let processTools: ProcessToolsController
    let textTools: TextToolsController
    let tools: ToolsController
    let nowPlaying: NowPlayingController
    let mediaMonitor: MediaActivityMonitor
    let cameraSession: AVCaptureSession
    let cameraPreview: PreviewView
    private var screenshotWatcher: ScreenshotWatcher?

    public init(model: IslandModel, supportDirectory: URL, fastPomodoro: Bool = false, updateFeedURL: URL? = nil, relaunchArguments: [String] = []) {
        pomodoro = PomodoroController(model: model, minutesAreSeconds: fastPomodoro)

        let keepAwakeController = KeepAwakeController(
            runner: ProcessCommandRunner(),
            stateStore: FileStore<KeepAwakeState?>(
                url: supportDirectory.appendingPathComponent("keep-awake.json"), defaultValue: nil))
        keepAwake = KeepAwakeViewModel(model: model, controller: keepAwakeController, installer: SystemPermissionInstaller())
        focus = FocusStatusMonitor(model: model)

        let clipboardHistory = ClipboardHistory(
            store: FileStore(url: supportDirectory.appendingPathComponent("clipboard.json"), defaultValue: []))
        clipboard = ClipboardController(
            history: clipboardHistory,
            imagesDirectory: supportDirectory.appendingPathComponent("clipboard-images", isDirectory: true),
            ocr: { await OCRService().recognizeText(in: $0) },
            quickOCR: { await OCRService(attempts: [.fast]).recognizeText(in: $0) })

        shelf = ShelfController(
            store: ShelfStore(store: FileStore(url: supportDirectory.appendingPathComponent("shelf.json"), defaultValue: [])),
            model: model)

        let login = LaunchAtLoginController(settings: model.settings, service: SystemLoginItem())
        launchAtLogin = login
        // Updates: the version is the running app's own (the built app says it in its Info.plist), and the address GitHub's
        // newest release is asked at can be changed with `--update-feed` to try the updater without publishing anything.
        let runningVersion = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? AppVersion(islandVersion)!
        let updater = UpdateController(
            feed: GitHubUpdateFeed(url: updateFeedURL ?? GitHubUpdateFeed.defaultURL),
            installer: AppUpdateInstaller(currentVersion: runningVersion, allowAnyHost: updateFeedURL != nil),
            settings: model.settings, currentVersion: runningVersion, relaunchArguments: relaunchArguments)
        update = updater
        settingsWindow = SettingsWindowController(settings: model.settings, launchAtLogin: login, keepAwake: keepAwake, update: updater)

        let capture = SystemCameraCapture()
        camera = CameraController(authorizer: SystemCameraAuthorizer(), capture: capture)
        cameraSession = capture.session
        cameraPreview = PreviewView(session: capture.session)

        calendarSource = EventKitSource()
        calendar = CalendarController(source: calendarSource)
        let alertScheduler = AlertScheduler(source: calendarSource, model: model)
        alerts = alertScheduler
        lockSounds = LockSoundController(settings: model.settings)
        ambient = AmbientPlayer(settings: model.settings)
        processTools = ProcessToolsController()
        textTools = TextToolsController()
        tools = ToolsController()
        nowPlaying = NowPlayingController()
        mediaMonitor = MediaActivityMonitor(player: nowPlaying, model: model)
        // Logins and tokens: files in Island's own data folder, readable only by this user (see `FileTokenStore` for why not the
        // Keychain). A copy started with its own data folder (`--support-dir`) therefore has its own, empty, set.
        let secrets = supportDirectory.appendingPathComponent("secrets", isDirectory: true)
        todoist = TodoistController(tokens: FileTokenStore(directory: secrets, service: "todoist"))
        github = GitHubController(tokens: FileTokenStore(directory: secrets, service: "github"))
        teams = TeamsController(
            sessions: FileTokenStore(directory: secrets, service: "teams"), config: FileTokenStore(directory: secrets, service: "teams-app"))
        browser = BrowserController(
            store: FileStore(url: supportDirectory.appendingPathComponent("browser.json"), defaultValue: BrowserState()),
            adBlocker: BrowserAdBlocker())
        settings = model.settings
        tasks = TasksController(
            store: TaskStore(store: FileStore(url: supportDirectory.appendingPathComponent("tasks.json"), defaultValue: [])))
        // A pull request clicked in a Teams message opens for review in the GitHub tab.
        teams.openPullRequest = { [weak model, weak github] link in
            guard let model, let github else { return }
            Task { @MainActor in await IslandServices.openPullRequestInGitHubTab(link, model: model, github: github) }
        }
        // Allowing calendar access in the Calendar tab starts the alerts at once, no relaunch needed.
        calendar.onAuthorized = { [weak alertScheduler] in alertScheduler?.start() }
    }

    /// Shows the GitHub tab and opens a pull request link there for review. GitHub is started first: its saved token is only
    /// read when its tab is first used, and the tab may not have been opened yet this time.
    static func openPullRequestInGitHubTab(_ link: String, model: IslandModel, github: GitHubController) async {
        model.selectedTab = .github
        await github.start()
        _ = await github.openPullRequest(link: link)
    }

    func showSettings() {
        settingsWindow.show()
    }

    /// Called once at launch.
    public func start() {
        launchAtLogin.syncWithSystem()
        keepAwake.launch()
        focus.requestAndStart()
        clipboard.start()
        lockSounds.start()
        mediaMonitor.start()
        update.startAutomaticChecks()
        startScreenshotWatcher()
    }

    /// Watches the folder macOS saves screenshots to, and puts new ones on the shelf.
    private func startScreenshotWatcher() {
        let folder = ScreenshotLocation.resolve(
            defaultsValue: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            home: FileManager.default.homeDirectoryForCurrentUser)
        let watcher = ScreenshotWatcher(folder: folder) { [weak shelf] url in
            Task { @MainActor in shelf?.handleScreenshot(url) }
        }
        watcher.start()
        screenshotWatcher = watcher
    }

    /// Called when Island quits normally.
    public func willTerminate() {
        mixer.shutdown()   // every app plays at full volume again
        keepAwake.willTerminate()
    }
}
