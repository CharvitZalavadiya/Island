import Foundation

/// One entry from the user's calendars, reduced to what Island shows.
public struct CalendarEvent: Equatable, Identifiable, Sendable {
    /// Unique per occurrence (a repeating event has a different id each time it happens).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The calendar's colour as 0xRRGGBB, if it has one.
    public var colorHex: UInt32?
    public var calendarTitle: String
    /// How to join, when the event is an online meeting (Meet, Zoom, Teams and so on).
    public var meeting: MeetingLink?

    public init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool, colorHex: UInt32?, calendarTitle: String,
        meeting: MeetingLink? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.calendarTitle = calendarTitle
        self.meeting = meeting
    }

    /// Whether the event takes place (even partly) on the calendar day containing `day`. An event ending exactly at
    /// midnight does not belong to the next day; one that spans midnight belongs to both.
    public func overlaps(day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart), start < dayEnd else { return false }
        return end > dayStart || (end == start && start >= dayStart)
    }
}

public enum EventSorting {
    /// The order events are listed in for one day: all-day events first, then by start time, then by title.
    public static func forDay(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}
