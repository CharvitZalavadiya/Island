import EventKit
import AppKit
import IslandCore

/// The calendars of this Mac (iCloud, Google and so on), read through EventKit. It only reads; nothing is ever written.
final class EventKitSource: CalendarEventSource {
    private let store = EKEventStore()

    func authorization() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .authorized
        case .restricted: .restricted
        // Write-only access cannot read events, so for Island it is the same as no access.
        case .denied, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(from: Date, to: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map(Self.convert)
    }

    var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { _ in continuation.yield() }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        }
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        let start = event.startDate ?? Date()
        // A repeating event shares one identifier between its occurrences, so the start time makes each one unique.
        let id = "\(event.eventIdentifier ?? UUID().uuidString)@\(Int(start.timeIntervalSince1970))"
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarEvent(
            id: id,
            title: (title?.isEmpty == false ? title : nil) ?? "Untitled event",
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            colorHex: event.calendar.flatMap { hex(of: $0.cgColor) },
            calendarTitle: event.calendar?.title ?? "",
            meeting: MeetingLink.find(url: event.url, location: event.location, notes: event.notes))
    }

    private static func hex(of color: CGColor?) -> UInt32? {
        guard let color, let srgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(srgb.redComponent) << 16 | byte(srgb.greenComponent) << 8 | byte(srgb.blueComponent)
    }
}
