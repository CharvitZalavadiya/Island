import AppKit
import IslandCore

/// Announces an event on the island ten minutes before it starts.
///
/// It always plans just the next announcement and keeps a single timer for it, so nothing runs in between. It plans
/// again when the calendar changes, when the Mac wakes up and after each announcement. It announces nothing until the
/// user has allowed calendar access, and never while Mission Control is on screen.
@MainActor
final class AlertScheduler {
    /// Runs `action` at `date`; the returned closure cancels it. Tests pass their own.
    typealias Schedule = (_ date: Date, _ action: @escaping @MainActor () -> Void) -> () -> Void

    /// How far ahead the calendar is read.
    static let horizon: TimeInterval = 24 * 3600
    /// With nothing to announce inside the horizon, look again after this long, so an event added for tomorrow is not
    /// missed on a Mac that is left running.
    static let replanInterval: TimeInterval = 12 * 3600
    /// While Mission Control is up the announcement is retried every `retryInterval`, for at most `maxRetries` tries.
    static let retryInterval: TimeInterval = 2
    static let maxRetries = 60

    private let source: CalendarEventSource
    private let model: IslandModel
    private let now: () -> Date
    private let isMissionControlActive: () -> Bool
    private let dismissAfter: TimeInterval
    private let schedule: Schedule
    private let wakeNotifications: NotificationCenter

    private var alerted: Set<String> = []
    private var cancelPlan: (() -> Void)?
    private var cancelDismiss: (() -> Void)?
    private var changesTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(
        source: CalendarEventSource, model: IslandModel,
        now: @escaping () -> Date = Date.init,
        isMissionControlActive: @escaping () -> Bool = { MissionControl.isActive() },
        dismissAfter: TimeInterval = 10,
        schedule: @escaping Schedule = { date, action in AlertScheduler.systemSchedule(date, action) },
        wakeNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.source = source
        self.model = model
        self.now = now
        self.isMissionControlActive = isMissionControlActive
        self.dismissAfter = dismissAfter
        self.schedule = schedule
        self.wakeNotifications = wakeNotifications
    }

    /// Starts watching the calendar. Does nothing until calendar access has been allowed; calling it again once it
    /// has (the Calendar tab does) picks it up.
    func start() {
        guard source.authorization() == .authorized else { return }
        if changesTask == nil {
            let changes = source.changes
            changesTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled, let self else { return }
                    self.reschedule()
                }
            }
        }
        if wakeObserver == nil {
            wakeObserver = wakeNotifications.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reschedule() }
            }
        }
        reschedule()
    }

    func stop() {
        cancelPlan?()
        cancelPlan = nil
        cancelDismiss?()
        cancelDismiss = nil
        changesTask?.cancel()
        changesTask = nil
        if let wakeObserver { wakeNotifications.removeObserver(wakeObserver) }
        wakeObserver = nil
        model.dismissAlert()
    }

    /// Works out the next announcement and sets the one timer for it.
    func reschedule() {
        cancelPlan?()
        cancelPlan = nil
        guard source.authorization() == .authorized else { return }
        let current = now()
        let events = source.events(from: current, to: current.addingTimeInterval(Self.horizon))
        if let plan = EventAlertPlanner.next(events: events, now: current, alerted: alerted) {
            let event = plan.event
            cancelPlan = schedule(plan.fireDate) { [weak self] in self?.fire(event, attempt: 0) }
        } else {
            cancelPlan = schedule(current.addingTimeInterval(Self.replanInterval)) { [weak self] in self?.reschedule() }
        }
    }

    // MARK: The banner

    /// The pointer is over the banner (or the island): the countdown waits until it leaves.
    func holdDismiss(_ hold: Bool) {
        guard model.alert != nil else { return }
        if hold {
            cancelDismiss?()
            cancelDismiss = nil
        } else {
            startCountdown()
        }
    }

    /// A click: the banner goes away at once.
    func dismissNow() {
        cancelDismiss?()
        cancelDismiss = nil
        model.dismissAlert()
    }

    /// For `--debug-alert`: a banner that stays until it is clicked, so it can be looked at.
    func showSample() {
        model.showAlert(EventAlert(
            eventID: "sample", title: "Design review with the platform team",
            start: now().addingTimeInterval(EventAlertPlanner.leadTime), colorHex: 0x22D3EE,
            meeting: MeetingLink(provider: "Google Meet", url: URL(string: "https://meet.google.com/abc-defg-hij")!)))
    }

    // MARK: Internals

    private func fire(_ event: CalendarEvent, attempt: Int) {
        cancelPlan = nil
        let current = now()
        // A timer that fires for an event that was announced already, or has begun (the Mac slept), says nothing.
        guard !alerted.contains(event.id), event.start > current else {
            reschedule()
            return
        }
        if isMissionControlActive() {
            guard attempt < Self.maxRetries else {
                alerted.insert(event.id)
                reschedule()
                return
            }
            cancelPlan = schedule(current.addingTimeInterval(Self.retryInterval)) { [weak self] in
                self?.fire(event, attempt: attempt + 1)
            }
            return
        }
        alerted.insert(event.id)
        model.showAlert(EventAlert(
            eventID: event.id, title: event.title, start: event.start, colorHex: event.colorHex, meeting: event.meeting))
        startCountdown()
        reschedule()
    }

    private func startCountdown() {
        cancelDismiss?()
        cancelDismiss = schedule(now().addingTimeInterval(dismissAfter)) { [weak self] in self?.dismissNow() }
    }

    nonisolated static func systemSchedule(_ date: Date, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
