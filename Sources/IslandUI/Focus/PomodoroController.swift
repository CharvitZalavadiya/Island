import AppKit
import Observation
import IslandCore

/// Everything the views need to draw the timer, captured in one value.
public struct PomodoroSnapshot: Equatable {
    public var phase: PomodoroPhase
    public var mode: PomodoroMode
    public var status: PomodoroStatus
    public var remaining: TimeInterval
    public var elapsed: TimeInterval
    public var completedFocusCount: Int
}

/// Drives the Pomodoro engine: ticks it once a second while it runs, plays the end sound, runs the mascot's
/// celebration, and keeps the `.pomodoro` live activity in sync. It also owns the choices made on the Pomodoro card
/// itself: the length of the current phase, which mascot to show, and whether to shuffle mascots.
@Observable
@MainActor
public final class PomodoroController {
    public private(set) var snapshot: PomodoroSnapshot
    public private(set) var mascotID: String
    public private(set) var isCelebrating = false
    /// When on, the next `start()` begins the stopwatch instead of a countdown.
    public var stopwatchMode = false

    @ObservationIgnored private let engine: PomodoroEngine
    @ObservationIgnored private let model: IslandModel
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let playSound: () -> Void
    @ObservationIgnored private let celebrationSeconds: TimeInterval
    @ObservationIgnored private let minutesAreSeconds: Bool
    @ObservationIgnored private var selector = MascotSelector(
        allIDs: MascotRegistry.all.map(\.id), random: SystemRandomNumberGenerator())
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var celebrationTimer: Timer?

    /// - Parameter minutesAreSeconds: treats the configured minutes as seconds, for checking the app by hand.
    public init(
        model: IslandModel,
        now: @escaping () -> Date = Date.init,
        playSound: @escaping () -> Void = { NSSound(named: "Glass")?.play() },
        celebrationSeconds: TimeInterval = 5,
        minutesAreSeconds: Bool = false
    ) {
        let settings = model.settings.settings
        let engine = PomodoroEngine(config: Self.makeConfig(settings, fast: minutesAreSeconds), now: now)
        self.engine = engine
        self.model = model
        self.now = now
        self.playSound = playSound
        self.celebrationSeconds = celebrationSeconds
        self.minutesAreSeconds = minutesAreSeconds
        self.snapshot = Self.snapshot(of: engine)
        self.mascotID = settings.mascotID
        refresh()
        observeSettings()
    }

    /// The face the mascot should wear right now.
    public var mood: MascotMood {
        if isCelebrating { return .done }
        switch snapshot.phase {
        case .focus: return .focus
        case .shortBreak, .longBreak: return .rest
        }
    }

    /// The mascot drifts about while a countdown or the stopwatch runs and hops while celebrating; paused or idle it
    /// rests. Movement costs CPU, which is why it is only on when it means something.
    public var mascotMoves: Bool { isCelebrating || snapshot.status == .running }

    // MARK: Minutes, from the card itself

    /// The length in minutes of the phase the card is showing (focus, short break or long break).
    public var currentPhaseMinutes: Int {
        let settings = model.settings.settings
        switch snapshot.phase {
        case .focus: return settings.focusMinutes
        case .shortBreak: return settings.shortBreakMinutes
        case .longBreak: return settings.longBreakMinutes
        }
    }

    /// How long the phase the card is showing lasts, in seconds: the full length the ring counts down from.
    public var phaseDuration: TimeInterval {
        TimeInterval(currentPhaseMinutes) * (minutesAreSeconds ? 1 : 60)
    }

    /// How much of the phase is left, 1 down to 0, for the mascot's ring. A stopwatch has nothing to count down to,
    /// so its ring stays full.
    public var ringFraction: Double {
        guard snapshot.mode == .countdown, snapshot.status != .idle, phaseDuration > 0 else { return 1 }
        return min(max(snapshot.remaining / phaseDuration, 0), 1)
    }

    /// Makes the current phase longer or shorter (the − and + buttons). Only while nothing is running and the
    /// stopwatch is not selected, and always within the allowed range.
    public func adjustMinutes(by delta: Int) {
        guard snapshot.status == .idle, !stopwatchMode else { return }
        let phase = snapshot.phase
        model.settings.update { settings in
            switch phase {
            case .focus:
                settings.focusMinutes = Self.clamp(settings.focusMinutes + delta, Settings.focusMinutesRange)
            case .shortBreak:
                settings.shortBreakMinutes = Self.clamp(settings.shortBreakMinutes + delta, Settings.shortBreakMinutesRange)
            case .longBreak:
                settings.longBreakMinutes = Self.clamp(settings.longBreakMinutes + delta, Settings.longBreakMinutesRange)
            }
        }
        settingsChanged()
    }

    // MARK: Mascot, from the card itself

    public var shuffleOn: Bool { model.settings.settings.shuffleMascots }

    /// Chooses the mascot (the carousel), saves the choice and shows it at once. Unknown ids are ignored.
    public func selectMascot(_ id: String) {
        guard MascotRegistry.all.contains(where: { $0.id == id }) else { return }
        model.settings.update { $0.mascotID = id }
        mascotID = id
    }

    /// Turns "a different mascot every session" on or off. Off returns to the mascot that was chosen.
    public func setShuffle(_ on: Bool) {
        model.settings.update { $0.shuffleMascots = on }
        settingsChanged()
    }

    // MARK: Actions

    public func start() {
        engine.start(mode: stopwatchMode ? .stopwatch : .countdown)
        refresh()
    }

    public func pause() {
        engine.pause()
        refresh()
    }

    public func resume() {
        engine.resume()
        refresh()
    }

    public func reset() {
        engine.reset()
        endCelebration()
    }

    public func skip() {
        engine.skip()
        refresh()
    }

    /// Called once a second while the timer runs (and by tests).
    public func tick() {
        for event in engine.tick() {
            guard case .phaseFinished = event else { continue }
            playSound()
            startCelebration()
            if model.settings.settings.shuffleMascots {
                mascotID = selector.nextID(current: mascotID, shuffle: true)
            }
        }
        refresh()
    }

    public func endCelebration() {
        celebrationTimer?.invalidate()
        celebrationTimer = nil
        isCelebrating = false
        refresh()
    }

    /// Picks up changed durations and mascot choices from the settings.
    func settingsChanged() {
        let settings = model.settings.settings
        engine.config = Self.makeConfig(settings, fast: minutesAreSeconds)
        if !settings.shuffleMascots { mascotID = settings.mascotID }
        refresh()
    }

    // MARK: Internals

    private func startCelebration() {
        isCelebrating = true
        celebrationTimer?.invalidate()
        celebrationTimer = Timer.scheduledTimer(withTimeInterval: celebrationSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endCelebration() }
        }
    }

    private func refresh() {
        snapshot = Self.snapshot(of: engine)
        // The wings stay up while idle only for the celebration.
        model.setActivity(.pomodoro, active: snapshot.status != .idle || isCelebrating)
        updateTickTimer()
    }

    /// The one-second timer exists only while the engine is running, so an idle app wakes for nothing.
    private func updateTickTimer() {
        if snapshot.status == .running {
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

    private func observeSettings() {
        withObservationTracking {
            _ = model.settings.settings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.settingsChanged()
                self?.observeSettings()
            }
        }
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func makeConfig(_ settings: Settings, fast: Bool) -> PomodoroConfig {
        var config = PomodoroConfig(settings: settings)
        if fast {
            config.focus /= 60
            config.shortBreak /= 60
            config.longBreak /= 60
        }
        return config
    }

    private static func snapshot(of engine: PomodoroEngine) -> PomodoroSnapshot {
        PomodoroSnapshot(
            phase: engine.phase, mode: engine.mode, status: engine.status,
            remaining: engine.remaining, elapsed: engine.elapsed,
            completedFocusCount: engine.completedFocusCount)
    }
}
