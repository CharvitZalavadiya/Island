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
    let ambient: AmbientPlayer
    let processTools: ProcessToolsController
    let textTools: TextToolsController
    let tools: ToolsController
    let nowPlaying: NowPlayingController
    let mediaMonitor: MediaActivityMonitor
    let cameraSession: AVCaptureSession
    let cameraPreview: PreviewView
    private var screenshotWatcher: ScreenshotWatcher?

    public init(model: IslandModel, supportDirectory: URL, fastPomodoro: Bool = false) {
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
        settingsWindow = SettingsWindowController(settings: model.settings, launchAtLogin: login, keepAwake: keepAwake)

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
        tasks = TasksController(
            store: TaskStore(store: FileStore(url: supportDirectory.appendingPathComponent("tasks.json"), defaultValue: [])))
        // Allowing calendar access in the Calendar tab starts the alerts at once, no relaunch needed.
        calendar.onAuthorized = { [weak alertScheduler] in alertScheduler?.start() }
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
