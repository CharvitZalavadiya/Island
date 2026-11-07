import Foundation
import IslandCore

enum CalendarAccess: Equatable {
    case notDetermined, authorized, denied, restricted
}

/// Where Island gets events from. The real one is `EventKitSource`; tests use a fake.
protocol CalendarEventSource {
    func authorization() -> CalendarAccess
    func requestAccess() async -> Bool
    /// Events that take place (even partly) between `from` and `to`.
    func events(from: Date, to: Date) -> [CalendarEvent]
    /// A new stream on every access; it yields whenever the calendar database changes.
    var changes: AsyncStream<Void> { get }
}
