import Foundation

public enum PomodoroPhase: Codable, Equatable {
    case focus, shortBreak, longBreak
}

public enum PomodoroMode: Equatable {
    case countdown, stopwatch
}

public enum PomodoroStatus: Equatable {
    case idle, running, paused
}

public enum PomodoroEvent: Equatable {
    case phaseFinished(PomodoroPhase)
    case phaseStarted(PomodoroPhase)
}

public struct PomodoroConfig: Equatable {
    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    public var longBreakEvery: Int
    public var autoChain: Bool

    public init(
        focus: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval,
        longBreakEvery: Int, autoChain: Bool
    ) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.longBreakEvery = longBreakEvery
        self.autoChain = autoChain
    }

    public init(settings: Settings) {
        self.init(
            focus: TimeInterval(settings.focusMinutes) * 60,
            shortBreak: TimeInterval(settings.shortBreakMinutes) * 60,
            longBreak: TimeInterval(settings.longBreakMinutes) * 60,
            longBreakEvery: settings.longBreakEvery,
            autoChain: settings.autoChain)
    }

    func length(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

/// A Pomodoro timer that stores an absolute end time, so it stays correct across sleep and never relies on tick counts.
/// The caller calls `tick()` periodically and reacts to the events it returns.
public final class PomodoroEngine {
    public var config: PomodoroConfig
    public private(set) var phase: PomodoroPhase = .focus
    public private(set) var mode: PomodoroMode = .countdown
    public private(set) var status: PomodoroStatus = .idle
    public private(set) var completedFocusCount = 0

    private let now: () -> Date
    private var endDate: Date?
    private var startedAt: Date?
    private var pausedRemaining: TimeInterval = 0
    private var accumulated: TimeInterval = 0

    public init(config: PomodoroConfig, now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
    }

    /// Seconds left in the current countdown phase; 0 in stopwatch mode.
    public var remaining: TimeInterval {
        guard mode == .countdown else { return 0 }
        let length = config.length(of: phase)
        switch status {
        case .idle:
            return length
        case .paused:
            return pausedRemaining
        case .running:
            guard let endDate else { return length }
            return min(max(endDate.timeIntervalSince(now()), 0), length)
        }
    }

    /// Seconds spent in the current phase (countdown) or on the stopwatch.
    public var elapsed: TimeInterval {
        switch mode {
        case .countdown:
            return config.length(of: phase) - remaining
        case .stopwatch:
            switch status {
            case .idle: return 0
            case .paused: return accumulated
            case .running: return accumulated + max(0, now().timeIntervalSince(startedAt ?? now()))
            }
        }
    }

    public func start(mode: PomodoroMode = .countdown) {
        guard status == .idle else { return }
        self.mode = mode
        begin(at: now())
    }

    public func pause() {
        guard status == .running else { return }
        switch mode {
        case .countdown:
            pausedRemaining = remaining
            endDate = nil
        case .stopwatch:
            accumulated = elapsed
            startedAt = nil
        }
        status = .paused
    }

    public func resume() {
        guard status == .paused else { return }
        let current = now()
        switch mode {
        case .countdown: endDate = current.addingTimeInterval(pausedRemaining)
        case .stopwatch: startedAt = current
        }
        status = .running
    }

    public func reset() {
        clearTimer()
        phase = .focus
        mode = .countdown
        completedFocusCount = 0
    }

    /// Moves on to the next phase without counting the current one, and waits for `start()`.
    public func skip() {
        guard mode == .countdown else {
            clearTimer()
            return
        }
        clearTimer()
        phase = phase == .focus ? .shortBreak : .focus
    }

    /// Finishes the phase if its end time has passed. Safe to call as often as you like.
    public func tick() -> [PomodoroEvent] {
        guard status == .running, mode == .countdown, let endDate else { return [] }
        let current = now()
        guard current >= endDate else { return [] }

        let finished = phase
        var events: [PomodoroEvent] = [.phaseFinished(finished)]
        if finished == .focus { completedFocusCount += 1 }
        phase = nextPhase(after: finished)
        clearTimer()
        if config.autoChain {
            begin(at: current)
            events.append(.phaseStarted(phase))
        }
        return events
    }

    private func begin(at date: Date) {
        status = .running
        switch mode {
        case .countdown:
            endDate = date.addingTimeInterval(config.length(of: phase))
        case .stopwatch:
            startedAt = date
            accumulated = 0
        }
    }

    private func clearTimer() {
        status = .idle
        endDate = nil
        startedAt = nil
        pausedRemaining = 0
        accumulated = 0
    }

    private func nextPhase(after finished: PomodoroPhase) -> PomodoroPhase {
        guard finished == .focus else { return .focus }
        let every = max(config.longBreakEvery, 1)
        return completedFocusCount % every == 0 ? .longBreak : .shortBreak
    }
}
