import Foundation
import IslandCore
@testable import IslandUI

/// A stand-in for the real calendar, shared by the calendar tests.
final class FakeCalendarSource: CalendarEventSource {
    var access: CalendarAccess
    var grantsWhenAsked = true
    var events: [CalendarEvent] = []
    private(set) var accessRequests = 0
    private(set) var fetches: [(from: Date, to: Date)] = []
    private(set) var subscriptions = 0
    /// Runs while the permission prompt is "open", to simulate things that happen meanwhile.
    var duringPrompt: (() -> Void)?
    private var continuations: [AsyncStream<Void>.Continuation] = []

    init(_ access: CalendarAccess = .authorized, events: [CalendarEvent] = []) {
        self.access = access
        self.events = events
    }

    func authorization() -> CalendarAccess { access }

    func requestAccess() async -> Bool {
        accessRequests += 1
        duringPrompt?()
        access = grantsWhenAsked ? .authorized : .denied
        return grantsWhenAsked
    }

    func events(from: Date, to: Date) -> [CalendarEvent] {
        fetches.append((from, to))
        return events.filter { $0.start < to && max($0.end, $0.start) >= from && ($0.end > from || $0.end == $0.start) }
    }

    var changes: AsyncStream<Void> {
        subscriptions += 1
        return AsyncStream { continuation in continuations.append(continuation) }
    }

    /// Tells everyone listening that the calendar changed.
    func announceChange() {
        for continuation in continuations { continuation.yield() }
    }
}

func fakeEvent(
    _ id: String, _ title: String = "Meeting", start: Date, end: Date? = nil, allDay: Bool = false, colorHex: UInt32? = nil
) -> CalendarEvent {
    CalendarEvent(
        id: id, title: title, start: start, end: end ?? start.addingTimeInterval(3600), isAllDay: allDay,
        colorHex: colorHex, calendarTitle: "Work")
}
