import Testing
import Foundation
import IslandCore
@testable import IslandUI

private final class FakeAudioSystem: AudioSystem {
    var volume: Float? = 0.5
    var clientList: [AudioClient] = []
    func outputVolume() -> Float? { volume }
    func setOutputVolume(_ value: Float) { volume = value }
    func clients() -> [AudioClient] { clientList }
}

private final class FakePermission: AudioCapturePermissionChecking {
    var current = AudioCaptureStatus.granted
    private(set) var requests = 0
    private var completion: (@MainActor (Bool) -> Void)?
    func status() -> AudioCaptureStatus { current }
    func request(_ completion: @escaping @MainActor (Bool) -> Void) { requests += 1; self.completion = completion }
    @MainActor func answer(_ granted: Bool) { completion?(granted); completion = nil }
}

@MainActor private final class FakeControl: AppVolumeControlling {
    var onSystemChange: (() -> Void)?
    var onFailure: ((String, String) -> Void)?
    var failure: AppVolumeError?
    private(set) var held: [String: Float] = [:]
    private(set) var shutdowns = 0
    func setVolume(_ volume: Float, for app: MixerApp) -> Result<Void, AppVolumeError> {
        if let failure { return .failure(failure) }
        held[app.id] = volume
        return .success(())
    }
    func release(_ appID: String) { held[appID] = nil }
    func refresh(apps: [MixerApp]) {}
    func shutdown() { shutdowns += 1; held = [:] }
}

private let brave = AudioClient(processObject: 1, pid: 10, path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser", isPlaying: true)
private let teams = AudioClient(processObject: 2, pid: 11, path: "/Applications/Microsoft Teams.app/Contents/MacOS/MSTeams", isPlaying: true)
private let iterm = AudioClient(processObject: 3, pid: 12, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2", isPlaying: false)

@MainActor
private func makeMixer(
    permission: FakePermission? = nil, control: FakeControl? = nil
) -> (AudioMixerController, FakeAudioSystem, FakePermission, FakeControl) {
    let system = FakeAudioSystem()
    let permission = permission ?? FakePermission()
    let control = control ?? FakeControl()
    return (AudioMixerController(system: system, permission: permission, makeControl: { control }, ownPID: 1), system, permission, control)
}

@Test @MainActor func onlyAppsMakingSoundAreListed() {
    let (mixer, system, _, _) = makeMixer()
    system.clientList = [brave, teams, iterm]   // iTerm is open but silent
    mixer.refresh()
    #expect(mixer.apps.map(\.name) == ["Brave Browser", "Microsoft Teams"])
    #expect(mixer.master == 0.5)
}

@Test @MainActor func turningOneAppDownLeavesTheOthersAtFull() {
    let (mixer, system, _, control) = makeMixer()
    system.clientList = [brave, teams]
    mixer.refresh()
    let braveApp = mixer.apps[0]
    mixer.setVolume(0.2, for: braveApp)
    #expect(control.held == [braveApp.id: 0.2])
    #expect(mixer.volume(for: braveApp) == 0.2 && mixer.volume(for: mixer.apps[1]) == 1)
    mixer.setVolume(1, for: braveApp)                       // back to full: the tap goes away
    #expect(control.held.isEmpty && !mixer.anyReduced)
    #expect(control.shutdowns == 1)                         // and nothing keeps listening
}

@Test @MainActor func aTurnedDownAppStaysListedWhileQuiet() {
    let (mixer, system, _, _) = makeMixer()
    system.clientList = [brave]
    mixer.refresh()
    mixer.setVolume(0.3, for: mixer.apps[0])
    system.clientList = [AudioClient(processObject: 1, pid: 10, path: brave.path, isPlaying: false)]   // paused
    mixer.refresh()
    #expect(mixer.apps.map(\.name) == ["Brave Browser"])
    system.clientList = []                                  // quit
    mixer.refresh()
    #expect(mixer.apps.isEmpty && !mixer.anyReduced)
}

@Test @MainActor func aDeniedPermissionLeavesTheAppAtFullAndOffersSettings() {
    let permission = FakePermission()
    permission.current = .denied
    let (mixer, system, _, control) = makeMixer(permission: permission)
    system.clientList = [brave]
    mixer.refresh()
    mixer.setVolume(0.2, for: mixer.apps[0])
    #expect(control.held.isEmpty && !mixer.anyReduced)
    #expect(mixer.notice?.offersSettings == true)
}

@Test @MainActor func volumeWaitsForTheSystemQuestionThenApplies() {
    let permission = FakePermission()
    permission.current = .unknown
    let (mixer, system, _, control) = makeMixer(permission: permission)
    system.clientList = [brave]
    mixer.refresh()
    mixer.setVolume(0.4, for: mixer.apps[0])
    mixer.setVolume(0.3, for: mixer.apps[0])                // dragging: still one question
    #expect(permission.requests == 1 && control.held.isEmpty)
    permission.answer(true)
    #expect(control.held.values.first == 0.3)
}

@Test @MainActor func refusingTheSystemQuestionPutsTheSliderBack() {
    let permission = FakePermission()
    permission.current = .unknown
    let (mixer, system, _, control) = makeMixer(permission: permission)
    system.clientList = [brave]
    mixer.refresh()
    mixer.setVolume(0.4, for: mixer.apps[0])
    permission.answer(false)
    #expect(!mixer.anyReduced && control.held.isEmpty && mixer.notice?.offersSettings == true)
}

@Test @MainActor func aFailedTapLeavesTheAppAtFullWithAMessage() {
    let control = FakeControl()
    control.failure = AppVolumeError(message: "Island couldn't start the volume control for Brave Browser (macOS error 1).")
    let (mixer, system, _, _) = makeMixer(control: control)
    system.clientList = [brave]
    mixer.refresh()
    mixer.setVolume(0.5, for: mixer.apps[0])
    #expect(!mixer.anyReduced)
    #expect(mixer.notice?.message.contains("Brave Browser") == true)
}

@Test @MainActor func theWatchdogGivingUpPutsTheAppBackToFull() {
    let (mixer, system, _, control) = makeMixer()
    system.clientList = [brave]
    mixer.refresh()
    mixer.setVolume(0.5, for: mixer.apps[0])
    control.onFailure?(mixer.apps[0].id, "Island lost control of Brave Browser's volume, so it is back to full.")
    #expect(!mixer.anyReduced && mixer.notice?.message.contains("back to full") == true)
}

@Test @MainActor func theOverallVolumeFollowsTheSliderAndTheSystem() {
    var clock = Date(timeIntervalSince1970: 1000)
    let system = FakeAudioSystem()
    let mixer = AudioMixerController(system: system, permission: FakePermission(), makeControl: { FakeControl() }, now: { clock })
    mixer.refresh()
    mixer.setMaster(0.8)
    #expect(system.volume == 0.8 && mixer.master == 0.8)
    system.volume = 0.1                                     // the keyboard's volume keys
    mixer.refresh()                                         // too soon after the slider moved: left alone
    #expect(mixer.master == 0.8)
    clock = clock.addingTimeInterval(2)
    mixer.refresh()
    #expect(mixer.master == 0.1)
}

@Test @MainActor func quittingReleasesEveryApp() {
    let (mixer, system, _, control) = makeMixer()
    system.clientList = [brave]
    mixer.refresh()
    mixer.setVolume(0.2, for: mixer.apps[0])
    mixer.shutdown()
    #expect(control.held.isEmpty && control.shutdowns >= 1)
}
