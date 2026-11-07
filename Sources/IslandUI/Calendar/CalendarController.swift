import Foundation
import Observation
import IslandCore

/// What the Calendar tab shows: a month, the selected day, and that day's events. It reads the calendar only while the
/// tab is on screen (between `start()` and `stop()`).
@Observable
@MainActor
final class CalendarController {
    private(set) var access: CalendarAccess
    /// The first day of the month on show.
    private(set) var visibleMonth: Date
    /// The start of the selected day.
    private(set) var selectedDay: Date
    private(set) var eventsForSelectedDay: [CalendarEvent] = []
    /// Start-of-day dates in the visible month on which something happens.
    private(set) var daysWithEvents: Set<Date> = []

    let calendar: Calendar
    /// Called once calendar access is known to be allowed (the event alerts use it to start without a relaunch).
    var onAuthorized: (() -> Void)?
    /// The start of today.
    var today: Date { calendar.startOfDay(for: now()) }

    @ObservationIgnored private let source: CalendarEventSource
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var monthEvents: [CalendarEvent] = []
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    /// True from `start()` until `stop()`: lets a permission prompt answered after the tab was left do nothing.
    @ObservationIgnored private var wantsRunning = false

    init(source: CalendarEventSource, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.calendar = calendar
        self.now = now
        self.access = source.authorization()
        self.selectedDay = calendar.startOfDay(for: now())
        self.visibleMonth = MonthGrid.month(byAdding: 0, to: now(), calendar: calendar)
    }

    /// Called when the tab appears. Permission is checked every time, so granting it later in System Settings works.
    func start() async {
        wantsRunning = true
        var current = source.authorization()
        if current == .notDetermined {
            access = .notDetermined
            current = await source.requestAccess() ? .authorized : .denied
            guard wantsRunning else { return }
        }
        access = current
        guard current == .authorized else {
            stopListening()
            clear()
            return
        }
        goToToday()
        listenForChanges()
        onAuthorized?()
    }

    /// Called when the tab goes away or the island collapses.
    func stop() {
        wantsRunning = false
        stopListening()
    }

    func selectDay(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        updateSelectedDay()
    }

    func showMonth(byAdding months: Int) {
        visibleMonth = MonthGrid.month(byAdding: months, to: visibleMonth, calendar: calendar)
        reload()
    }

    func goToToday() {
        selectedDay = today
        visibleMonth = MonthGrid.month(byAdding: 0, to: selectedDay, calendar: calendar)
        reload()
    }

    /// Reads the calendar again (it changed, or the month did).
    func refresh() {
        reload()
    }

    // MARK: Internals

    private func clear() {
        monthEvents = []
        daysWithEvents = []
        eventsForSelectedDay = []
    }

    /// Reads the visible month once and works out the day marks and the selected day's list from that.
    private func reload() {
        guard access == .authorized, let interval = calendar.dateInterval(of: .month, for: visibleMonth) else {
            clear()
            return
        }
        monthEvents = source.events(from: interval.start, to: interval.end)
        let days = MonthGrid.weeks(containing: visibleMonth, calendar: calendar).flatMap { $0 }.compactMap { $0 }
        daysWithEvents = Set(days.filter { day in monthEvents.contains { $0.overlaps(day: day, calendar: calendar) } })
        updateSelectedDay()
    }

    private func updateSelectedDay() {
        guard access == .authorized else {
            eventsForSelectedDay = []
            return
        }
        let candidates: [CalendarEvent]
        if let interval = calendar.dateInterval(of: .month, for: visibleMonth), interval.contains(selectedDay) {
            candidates = monthEvents
        } else if let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) {
            // The selected day is in another month than the one on show, so it needs a read of its own.
            candidates = source.events(from: selectedDay, to: end)
        } else {
            candidates = []
        }
        eventsForSelectedDay = EventSorting.forDay(candidates.filter { $0.overlaps(day: selectedDay, calendar: calendar) })
    }

    private func listenForChanges() {
        guard changesTask == nil else { return }
        let changes = source.changes
        changesTask = Task { [weak self] in
            for await _ in changes {
                // A change that was already on its way when the tab was left must not read the calendar.
                guard !Task.isCancelled, let self, self.wantsRunning else { return }
                self.refresh()
            }
        }
    }

    private func stopListening() {
        changesTask?.cancel()
        changesTask = nil
    }
}
