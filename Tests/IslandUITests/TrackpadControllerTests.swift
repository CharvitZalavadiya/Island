import CoreGraphics
import Foundation
import Testing
import IslandCore
@testable import IslandUI

// Edge gestures, tried without a trackpad: made-up touches go in, and what comes out is the volume, the brightness, the player,
// the little indicator, and whether the pointer is held. The engine itself is tried in IslandCoreTests/TrackpadGestureTests.

private final class Clock: @unchecked Sendable {
    var time: TimeInterval = 0
}

private final class FakeFreeze: PointerFreezing, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var log: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func engage(at point: CGPoint?) { add("engage " + (point.map { "\(Int($0.x)),\(Int($0.y))" } ?? "nowhere")) }
    func release() { add("release") }
    private func add(_ entry: String) { lock.lock(); entries.append(entry); lock.unlock() }
    var holds: Int { log.filter { $0.hasPrefix("engage") }.count }
}

private final class FakeSource: TouchSource, @unchecked Sendable {
    var result: Result<TrackpadDevice, TouchSourceError> = .success(TrackpadDevice(widthMM: 121.94, heightMM: 74.08, count: 1))
    private(set) var starts = 0
    private(set) var stops = 0
    private var handler: (@Sendable (TrackpadFrame) -> Void)?
    func start(_ handler: @escaping @Sendable (TrackpadFrame) -> Void) -> Result<TrackpadDevice, TouchSourceError> {
        starts += 1
        if case .success = result { self.handler = handler }
        return result
    }
    func stop() { stops += 1; handler = nil }
    var isRunning: Bool { handler != nil }
    func send(_ frame: TrackpadFrame) { handler?(frame) }
}

private final class FakeAudio: AudioSystem {
    var volume: Float? = 0.5
    private(set) var sets: [Float] = []
    func outputVolume() -> Float? { volume }
    func setOutputVolume(_ value: Float) { volume = value; sets.append(value) }
    func clients() -> [AudioClient] { [] }
}

private final class FakeBrightness: BrightnessControlling {
    var level: Float? = 0.4
    private(set) var sets: [Float] = []
    func current() -> Float? { level }
    func set(_ value: Float) { level = value; sets.append(value) }
}

@MainActor private final class FakeSeeker: TrackSeeking {
    var state: (elapsed: TimeInterval, duration: TimeInterval?)? = (100, 300)
    private(set) var listening: [Bool] = []
    private(set) var seeks: [TimeInterval] = []
    func listen(_ on: Bool) { listening.append(on) }
    var seekState: (elapsed: TimeInterval, duration: TimeInterval?)? { state }
    func seek(to seconds: TimeInterval) { seeks.append(seconds) }
}

@MainActor private final class FakeFeedback: TrackpadFeedback {
    private(set) var shown: [(symbol: String, fraction: Double?, text: String)] = []
    func show(symbol: String, fraction: Double?, text: String) { shown.append((symbol, fraction, text)) }
}

@MainActor private struct Rig {
    let controller: TrackpadController
    let settings: SettingsStore
    let source = FakeSource()
    let freeze = FakeFreeze()
    let audio = FakeAudio()
    let brightness = FakeBrightness()
    let seeker = FakeSeeker()
    let feedback = FakeFeedback()
    let clock = Clock()

    init(enabled: Bool = true, tweak: (inout IslandCore.Settings) -> Void = { _ in }) {
        var initial = IslandCore.Settings()
        initial.trackpadEnabled = enabled
        tweak(&initial)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trackpad-\(UUID())/settings.json")
        settings = SettingsStore(store: FileStore(url: url, defaultValue: initial))
        let clock = self.clock, freeze = self.freeze
        let pipeline = TrackpadPipeline(
            config: .init(activeEdges: initial.trackpadActiveEdges, edgeMM: initial.trackpadEdgeMM), freeze: freeze,
            readCursor: { CGPoint(x: 640, y: 300) }, clock: { clock.time })
        controller = TrackpadController(
            settings: settings, seeker: seeker, source: source, freeze: freeze, system: audio, brightness: brightness,
            feedback: feedback, pipeline: pipeline, now: { clock.time })
    }

    /// One whole gesture on an edge: it begins, the finger moves along it by `fraction` of its length (in two steps), it lifts.
    func slide(_ edge: TrackpadEdge, _ fraction: Double) {
        controller.apply(.began(edge))
        clock.time += 0.1
        controller.apply(.moved(edge, delta: fraction / 2))
        clock.time += 0.1
        controller.apply(.moved(edge, delta: fraction / 2))
        controller.apply(.ended(edge))
    }
}

// MARK: Volume and brightness

@Test @MainActor func slidingUpTheRightEdgeRaisesTheVolumeByTheFractionOfTheEdgeSlid() {
    let rig = Rig()
    rig.audio.volume = 0.4
    rig.slide(.right, 0.25)
    #expect(abs(Double(rig.audio.volume ?? 0) - 0.65) < 1e-6)
    #expect(rig.feedback.shown.last?.text == "65%" && rig.feedback.shown.last?.symbol == "speaker.wave.2.fill")
    #expect(rig.feedback.shown.last?.fraction.map { abs($0 - 0.65) < 1e-6 } == true)
}

@Test @MainActor func slidingDownLowersItAndItStopsAtSilenceAndAtFull() {
    let rig = Rig()
    rig.audio.volume = 0.3
    rig.slide(.right, -0.8)
    #expect(rig.audio.volume == 0 && rig.feedback.shown.last?.symbol == "speaker.slash.fill")
    rig.slide(.right, 3)
    #expect(rig.audio.volume == 1)
}

@Test @MainActor func theLeftEdgeChangesTheBrightnessAndTheOtherEdgesDoNotTouchIt() {
    let rig = Rig()
    rig.brightness.level = 0.4
    rig.slide(.left, 0.3)
    #expect(abs(Double(rig.brightness.level ?? 0) - 0.7) < 1e-6)
    #expect(rig.audio.sets.isEmpty)
    #expect(rig.feedback.shown.last?.text == "70%" && rig.feedback.shown.last?.symbol == "sun.max.fill")
}

@Test @MainActor func reversingAnEdgeAndTheSpeedChangeHowFarASlideGoes() {
    let rig = Rig(tweak: {
        $0.trackpadReversedEdges = ["right"]
        $0.trackpadSensitivity = 2
    })
    rig.audio.volume = 0.5
    rig.slide(.right, 0.1)                                                   // up, but reversed, and twice as far
    #expect(abs(Double(rig.audio.volume ?? 0) - 0.3) < 1e-6)
}

@Test @MainActor func anEdgeCanBeGivenAnotherJobAndOffMeansNothingHappens() {
    let rig = Rig(tweak: { $0.trackpadActions = ["right": "brightness", "left": "volume", "top": "off"] })
    rig.slide(.right, 0.2)
    rig.slide(.left, 0.2)
    rig.slide(.top, 0.5)
    #expect(rig.brightness.sets.last.map { abs(Double($0) - 0.6) < 1e-6 } == true)
    #expect(rig.audio.sets.last.map { abs(Double($0) - 0.7) < 1e-6 } == true)
    #expect(rig.seeker.seeks.isEmpty)
}

@Test @MainActor func gesturesDoNothingWhileTheyAreSwitchedOff() {
    let rig = Rig(enabled: false)
    rig.audio.volume = 0.5
    rig.slide(.right, 0.5)
    #expect(rig.audio.sets.isEmpty && rig.feedback.shown.isEmpty)
}

@Test @MainActor func aGestureOnAnEdgeThatCannotBeChangedSaysSoOnceAndChangesNothing() {
    let rig = Rig()
    rig.audio.volume = nil                                                   // an output with no volume control
    rig.brightness.level = nil                                               // a screen whose brightness cannot be read
    rig.slide(.right, 0.5)
    rig.slide(.right, 0.5)
    rig.slide(.left, 0.5)
    #expect(rig.audio.sets.isEmpty && rig.brightness.sets.isEmpty)
    #expect(rig.feedback.shown.map(\.text) == ["This sound output has no volume control", "The brightness of this screen can't be changed"])
}

// MARK: Moving through what is playing

@Test @MainActor func slidingAlongTheTopEdgeSkipsThroughWhatIsPlayingAndLetsGoAtTheEnd() {
    let rig = Rig()
    rig.seeker.state = (100, 300)
    rig.slide(.top, 0.5)                                                     // half the edge = 60 s
    #expect(rig.seeker.seeks.last == 160)
    #expect(rig.feedback.shown.last?.text == "2:40" && rig.feedback.shown.last?.symbol == "forward.fill")
}

@Test @MainActor func skippingBackGoesBackAndNeverPastTheStartOrTheEnd() {
    let rig = Rig(tweak: { $0.trackpadActions["bottom"] = "seek" })
    rig.seeker.state = (100, 300)
    rig.slide(.top, -2)
    #expect(rig.seeker.seeks.last == 0 && rig.feedback.shown.last?.symbol == "backward.fill")
    rig.slide(.bottom, 5)
    #expect(rig.seeker.seeks.last == 300)
}

@Test @MainActor func whileSlidingTheSongIsMovedNowAndThenNotWithEveryTinyStep() {
    let rig = Rig()
    rig.controller.apply(.began(.top))
    for _ in 0..<50 {
        rig.clock.time += 0.02                                               // a second of fifty small steps
        rig.controller.apply(.moved(.top, delta: 0.002))
    }
    let during = rig.seeker.seeks.count
    #expect(during >= 3 && during <= 6)
    rig.controller.apply(.ended(.top))
    #expect(rig.seeker.seeks.count == during + 1)                            // and once more, exactly, when the finger lifts
}

@Test @MainActor func skippingWithNothingPlayingSaysSoOnceAndMovesNothing() {
    let rig = Rig()
    rig.seeker.state = nil
    rig.slide(.top, 0.5)
    rig.slide(.top, 0.5)
    #expect(rig.seeker.seeks.isEmpty)
    #expect(rig.feedback.shown.map(\.text) == ["Nothing playing that can be skipped through"])
}

@Test @MainActor func theCurrentEdgeIsKnownWhileAGestureGoesOn() {
    let rig = Rig()
    #expect(rig.controller.edgeInUse == nil)
    rig.controller.apply(.began(.right))
    #expect(rig.controller.edgeInUse == .right)
    rig.controller.apply(.ended(.right))
    #expect(rig.controller.edgeInUse == nil)
}

// MARK: What is set, and starting and stopping

@Test @MainActor func theChoicesAreSavedAndKeptInRange() {
    let rig = Rig()
    rig.controller.setAction(.brightness, for: .bottom)
    rig.controller.setReversed(true, for: .left)
    rig.controller.setEdgeMM(500)
    rig.controller.setSensitivity(0)
    let saved = rig.settings.settings
    #expect(saved.trackpadAction(for: .bottom) == .brightness && saved.trackpadIsReversed(.left))
    #expect(saved.trackpadEdgeMM == 20 && saved.trackpadSensitivity == 0.4)
    rig.controller.setReversed(false, for: .left)
    #expect(!rig.settings.settings.trackpadIsReversed(.left))
}

@Test @MainActor func startingGivesThePointerBackFirstAndReadsTheTrackpadOnlyWhenSwitchedOn() {
    let off = Rig(enabled: false)
    off.controller.start()
    #expect(off.freeze.log.first == "release")                              // in case an earlier run stopped mid-gesture
    #expect(off.source.starts == 0 && off.controller.status == .off)

    let on = Rig(enabled: true)
    on.controller.start()
    #expect(on.source.starts == 1 && on.source.isRunning)
    #expect(on.controller.status == .running && on.controller.device?.widthMM == 121.94)
    on.controller.shutdown()
}

@Test @MainActor func switchingOffStopsReadingAndGivesThePointerBack() {
    let rig = Rig(enabled: false)
    rig.controller.start()
    rig.controller.setEnabled(true)
    #expect(rig.source.isRunning && rig.controller.isEnabled)
    rig.controller.setEnabled(false)
    #expect(!rig.source.isRunning && rig.source.stops == 1 && rig.controller.status == .off)
    #expect(rig.freeze.log.last == "release")
    #expect(!rig.settings.settings.trackpadEnabled)
}

@Test @MainActor func thePlayerIsOnlyListenedToWhileGesturesAreOnAndAnEdgeSkips() {
    let rig = Rig(enabled: false)
    rig.controller.start()
    #expect(rig.seeker.listening.last == false)
    rig.controller.setEnabled(true)
    #expect(rig.seeker.listening.last == true)                              // the top edge skips by default
    rig.controller.setAction(.off, for: .top)
    #expect(rig.seeker.listening.last == false)
    rig.controller.setAction(.seek, for: .bottom)
    #expect(rig.seeker.listening.last == true)
}

@Test @MainActor func aMacWithoutATrackpadOrWithoutTheLibraryIsToldSo() {
    let none = Rig()
    none.source.result = .failure(.noTrackpad)
    none.controller.start()
    #expect(none.controller.status == .noTrackpad && none.controller.device == nil)

    let blocked = Rig()
    blocked.source.result = .failure(.unavailable("macOS did not let Island read the trackpad."))
    blocked.controller.start()
    #expect(blocked.controller.status == .unavailable("macOS did not let Island read the trackpad."))
}

@Test @MainActor func theFingersAreFollowedWhileTheTabIsOpenEvenWithGesturesOffButNothingHappens() {
    let rig = Rig(enabled: false)
    rig.controller.start()
    #expect(rig.source.starts == 0)
    rig.controller.setPreviewing(true)
    #expect(rig.source.isRunning)
    // A whole slide up the right edge, with the gestures off: the finger is seen, the volume and the pointer are left alone.
    rig.source.send(frame((1, 118, 20)))
    rig.source.send(frame((1, 118, 30)))
    rig.source.send(frame((1, 118, 50)))
    #expect(rig.controller.pipeline.snapshot().touches.count == 1 && rig.controller.pipeline.snapshot().frames == 3)
    #expect(rig.freeze.holds == 0 && rig.audio.sets.isEmpty)
    rig.controller.setPreviewing(false)
    #expect(!rig.source.isRunning)
}

// MARK: The whole way: touches in, volume and pointer out

private func frame(_ fingers: (id: Int, x: Double, y: Double)...) -> TrackpadFrame {
    TrackpadFrame(touches: fingers.map { TrackpadTouch(id: $0.id, x: $0.x / 121.94, y: $0.y / 74.08) }, widthMM: 121.94, heightMM: 74.08)
}

@Test @MainActor func aSlideUpTheRightEdgeHoldsThePointerWhereItWasChangesTheVolumeAndLetsGoAtTheEnd() async throws {
    let rig = Rig()
    rig.audio.volume = 0.3
    rig.controller.start()
    func send(_ frame: TrackpadFrame) async throws {
        rig.clock.time += 0.02
        rig.source.send(frame)
        try await Task.sleep(nanoseconds: 20_000_000)                         // let the main queue hand the events over
    }

    try await send(frame((1, 118, 20)))
    #expect(rig.freeze.holds == 0)                                           // only touched down: the pointer is still free
    try await send(frame((1, 118, 24)))                                      // slid 4 mm along the edge: now it is a gesture
    #expect(rig.freeze.log.last == "engage 640,300")                         // held where the pointer was at touch-down
    #expect(rig.controller.edgeInUse == .right)
    try await send(frame((1, 118, 44)))                                      // 20 mm further up
    try await send(frame((1, 118, 44.5)))
    let expected = 0.3 + (44.5 - 24) / 74.08
    #expect(abs(Double(rig.audio.volume ?? 0) - expected) < 0.02, "volume \(String(describing: rig.audio.volume)) expected about \(expected)")
    try await send(TrackpadFrame(touches: [], widthMM: 121.94, heightMM: 74.08))
    #expect(rig.freeze.log.last == "release" && rig.controller.edgeInUse == nil)
    rig.controller.shutdown()
}

@Test @MainActor func aFingerThatMovesTheFingerIntoThePadNeverHoldsThePointer() async throws {
    let rig = Rig()
    rig.controller.start()
    for step in [(118.0, 30.0), (112.0, 31.0), (104.0, 32.0), (96.0, 33.0)] {
        rig.clock.time += 0.02
        rig.source.send(frame((1, step.0, step.1)))
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(rig.freeze.holds == 0 && rig.audio.sets.isEmpty && rig.controller.edgeInUse == nil)
    rig.controller.shutdown()
}

@Test @MainActor func aSecondFingerEndsTheGestureAndGivesThePointerBack() async throws {
    let rig = Rig()
    rig.controller.start()
    for f in [frame((1, 118, 20)), frame((1, 118, 30)), frame((1, 118, 40)), frame((1, 118, 41), (2, 60, 30))] {
        rig.clock.time += 0.02
        rig.source.send(f)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(rig.freeze.holds == 1 && rig.freeze.log.last == "release" && rig.controller.edgeInUse == nil)
    rig.controller.shutdown()
}

@Test @MainActor func switchingGesturesOffInTheMiddleOfOneGivesThePointerBack() async throws {
    let rig = Rig()
    rig.controller.start()
    for f in [frame((1, 118, 20)), frame((1, 118, 30)), frame((1, 118, 40))] {
        rig.clock.time += 0.02
        rig.source.send(f)
    }
    #expect(rig.freeze.holds == 1)
    rig.controller.setEnabled(false)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(rig.freeze.log.last == "release" && rig.controller.edgeInUse == nil)
}

@Test @MainActor func quittingWhileAGestureIsGoingOnGivesThePointerBack() {
    let rig = Rig()
    rig.controller.start()
    for f in [frame((1, 118, 20)), frame((1, 118, 30)), frame((1, 118, 40))] {
        rig.clock.time += 0.02
        rig.source.send(f)
    }
    rig.controller.shutdown()
    #expect(rig.freeze.log.last == "release" && !rig.source.isRunning)
}
