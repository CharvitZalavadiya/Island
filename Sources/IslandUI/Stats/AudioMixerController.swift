import AppKit
import Observation
import IslandCore

/// The sound mixer in the Stats tab: the Mac's overall volume, and one volume for each app that is making sound.
///
/// The overall volume is the same one the keyboard's volume keys change. An app's volume is held lower by
/// `AppVolumeControlling`, and only while it is below full; an app left at full volume is never touched.
@Observable
@MainActor
final class AudioMixerController {
    struct Notice: Equatable {
        var message: String
        /// Offers a button that opens the privacy settings.
        var offersSettings = false
    }

    /// The overall volume, 0 to 1; nil when the sound output has no volume control.
    private(set) var master: Float?
    /// The apps to show: those making sound, and any that were turned down.
    private(set) var apps: [MixerApp] = []
    /// The apps turned below full, by id.
    private(set) var volumes: [String: Float] = [:]
    private(set) var notice: Notice?

    @ObservationIgnored private let system: AudioSystem
    @ObservationIgnored private let permission: AudioCapturePermissionChecking
    @ObservationIgnored private let makeControl: @MainActor () -> AppVolumeControlling
    @ObservationIgnored private var control: AppVolumeControlling?
    @ObservationIgnored private let ownPID: Int32
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var permissionGranted = false
    /// Volumes asked for while macOS is still asking the user for permission.
    @ObservationIgnored private var waitingForPermission: [String: (app: MixerApp, volume: Float)] = [:]
    @ObservationIgnored private var lastMasterChange = Date.distantPast
    @ObservationIgnored private var allApps: [MixerApp] = []

    init(
        system: AudioSystem = CoreAudioSystem(), permission: AudioCapturePermissionChecking = SystemAudioCapturePermission(),
        makeControl: @escaping @MainActor () -> AppVolumeControlling = { AppVolumeEngine() },
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier, now: @escaping () -> Date = Date.init
    ) {
        self.system = system
        self.permission = permission
        self.makeControl = makeControl
        self.ownPID = ownPID
        self.now = now
    }

    var anyReduced: Bool { !volumes.isEmpty }

    func volume(for app: MixerApp) -> Float { volumes[app.id] ?? 1 }

    // MARK: Watching

    /// Starts keeping the list up to date. Called while the Stats tab is on screen.
    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads who is making sound and the overall volume now.
    func refresh() {
        allApps = AudioMixerGrouping.apps(from: system.clients(), ownPID: ownPID)
        // An app with no audio process left (it quit) has nothing to hold down.
        let known = Set(allApps.map(\.id))
        for id in volumes.keys where !known.contains(id) && waitingForPermission[id] == nil {
            volumes[id] = nil
            control?.release(id)
        }
        control?.refresh(apps: allApps.filter { volumes[$0.id] != nil })

        let shown = AudioMixerGrouping.visible(allApps, volumes: volumes)
        if shown != apps { apps = shown }
        // Leave the slider alone just after it was moved, so it doesn't jump back while the system catches up.
        if now().timeIntervalSince(lastMasterChange) > 0.6 {
            let level = system.outputVolume()
            if level != master { master = level }
        }
        dropControlIfUnused()
    }

    // MARK: Changing volumes

    func setMaster(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        lastMasterChange = now()
        system.setOutputVolume(clamped)
        master = clamped
    }

    func setVolume(_ value: Float, for app: MixerApp) {
        let clamped = min(max(value, 0), 1)
        if clamped >= AudioMixerGrouping.fullVolume {
            volumes[app.id] = nil
            waitingForPermission[app.id] = nil
            control?.release(app.id)
            dropControlIfUnused()
            return
        }
        if permissionGranted { return apply(clamped, to: app) }
        switch permission.status() {
        case .granted:
            permissionGranted = true
            apply(clamped, to: app)
        case .denied:
            volumes[app.id] = nil
            notice = Notice(
                message: "To turn an app down, Island needs permission to record system audio. Allow it in System Settings, then try again.",
                offersSettings: true)
        case .unknown:
            // macOS is about to ask. The slider stays where it was put, and the volume applies if the user allows it.
            let first = waitingForPermission.isEmpty
            waitingForPermission[app.id] = (app, clamped)
            volumes[app.id] = clamped
            notice = Notice(message: "macOS is asking whether Island may record system audio. Allow it to turn an app down.")
            if first {
                permission.request { [weak self] granted in self?.permissionAnswered(granted) }
            }
        }
    }

    /// Puts every app back to full volume.
    func resetAll() {
        for id in Array(volumes.keys) { control?.release(id) }
        volumes = [:]
        waitingForPermission = [:]
        notice = nil
        dropControlIfUnused()
        refresh()
    }

    func dismissNotice() { notice = nil }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Called when Island quits: every app plays at full volume again.
    func shutdown() {
        stop()
        control?.shutdown()
        control = nil
    }

    // MARK: Internals

    private func apply(_ value: Float, to app: MixerApp) {
        let control = self.control ?? makeAndConnectControl()
        switch control.setVolume(value, for: app) {
        case .success:
            volumes[app.id] = value
            if notice?.offersSettings == false { notice = nil }
        case .failure(let error):
            volumes[app.id] = nil
            notice = Notice(message: error.message)
            dropControlIfUnused()
        }
    }

    private func permissionAnswered(_ granted: Bool) {
        let waiting = waitingForPermission
        waitingForPermission = [:]
        guard granted else {
            for id in waiting.keys { volumes[id] = nil }
            notice = Notice(
                message: "Island wasn't allowed to record system audio, so it can't turn apps down. You can allow it in System Settings.",
                offersSettings: true)
            return
        }
        permissionGranted = true
        notice = nil
        for (_, request) in waiting { apply(request.volume, to: request.app) }
    }

    private func makeAndConnectControl() -> AppVolumeControlling {
        let control = makeControl()
        control.onSystemChange = { [weak self] in self?.refresh() }
        control.onFailure = { [weak self] id, message in
            guard let self else { return }
            self.volumes[id] = nil
            self.notice = Notice(message: message)
            self.dropControlIfUnused()
        }
        self.control = control
        return control
    }

    /// With every app at full volume nothing needs to be listening for changes, so the control is let go.
    private func dropControlIfUnused() {
        guard volumes.isEmpty, let control else { return }
        control.shutdown()
        self.control = nil
    }
}
