import Foundation

/// Decides which upcoming event the island should announce next, and when.
public enum EventAlertPlanner {
    /// How long before an event starts the island announces it.
    public static let leadTime: TimeInterval = 600

    /// The earliest event that has not started yet, is not all-day and has not been announced. It is announced
    /// `leadTime` before it starts, or right away if that moment has already passed. Nil when there is nothing to
    /// announce.
    public static func next(
        events: [CalendarEvent], now: Date, alerted: Set<String>
    ) -> (event: CalendarEvent, fireDate: Date)? {
        let upcoming = events.filter { !$0.isAllDay && $0.start > now && !alerted.contains($0.id) }
        guard let event = upcoming.min(by: { ($0.start, $0.id) < ($1.start, $1.id) }) else { return nil }
        return (event, max(now, event.start.addingTimeInterval(-leadTime)))
    }
}
