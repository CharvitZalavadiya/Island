import Testing
import Foundation
@testable import IslandCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func event(
    _ id: String, _ title: String, _ start: Date, _ end: Date? = nil, allDay: Bool = false
) -> CalendarEvent {
    CalendarEvent(
        id: id, title: title, start: start, end: end ?? start.addingTimeInterval(3600), isAllDay: allDay,
        colorHex: nil, calendarTitle: "Work")
}

// MARK: sorting

@Test func allDayFirstThenByStartThenTitle() {
    let events = [
        event("1", "Standup", date(2026, 11, 2, 10)),
        event("2", "Dentist", date(2026, 11, 2, 9)),
        event("3", "Zebra day", date(2026, 11, 2), allDay: true),
        event("4", "Apple day", date(2026, 11, 2), allDay: true),
        event("5", "Brunch", date(2026, 11, 2, 10)),
    ]
    #expect(EventSorting.forDay(events).map(\.id) == ["4", "3", "2", "5", "1"])
}

@Test func titlesAreComparedWithoutCase() {
    let events = [event("1", "banana", date(2026, 11, 2, 9)), event("2", "Apple", date(2026, 11, 2, 9))]
    #expect(EventSorting.forDay(events).map(\.title) == ["Apple", "banana"])
}

@Test func identicalEventsKeepAStableOrderByID() {
    let events = [event("b", "Same", date(2026, 11, 2, 9)), event("a", "Same", date(2026, 11, 2, 9))]
    #expect(EventSorting.forDay(events).map(\.id) == ["a", "b"])
}

@Test func sortingNothingGivesNothing() {
    #expect(EventSorting.forDay([]).isEmpty)
}

// MARK: which day an event belongs to

@Test func anEventBelongsToItsOwnDayOnly() {
    let meeting = event("m", "Meeting", date(2026, 11, 2, 14), date(2026, 11, 2, 15))
    #expect(meeting.overlaps(day: date(2026, 11, 2, 8), calendar: utc))
    #expect(!meeting.overlaps(day: date(2026, 11, 1), calendar: utc))
    #expect(!meeting.overlaps(day: date(2026, 11, 3), calendar: utc))
}

@Test func anEventSpanningMidnightBelongsToBothDays() {
    let late = event("l", "Late call", date(2026, 11, 2, 23), date(2026, 11, 3, 1))
    #expect(late.overlaps(day: date(2026, 11, 2), calendar: utc))
    #expect(late.overlaps(day: date(2026, 11, 3), calendar: utc))
    #expect(!late.overlaps(day: date(2026, 11, 4), calendar: utc))
}

@Test func anEventEndingExactlyAtMidnightDoesNotSpillIntoTheNextDay() {
    let evening = event("e", "Film", date(2026, 11, 2, 22), date(2026, 11, 3))
    #expect(evening.overlaps(day: date(2026, 11, 2), calendar: utc))
    #expect(!evening.overlaps(day: date(2026, 11, 3), calendar: utc))
}

@Test func aMultiDayAllDayEventBelongsToEveryDayInBetween() {
    let trip = event("t", "Trip", date(2026, 11, 2), date(2026, 11, 4, 23, 59), allDay: true)
    for day in 2...4 { #expect(trip.overlaps(day: date(2026, 11, day, 12), calendar: utc)) }
    #expect(!trip.overlaps(day: date(2026, 11, 1), calendar: utc))
    #expect(!trip.overlaps(day: date(2026, 11, 5), calendar: utc))
}

@Test func aZeroLengthEventAtMidnightBelongsToThatDayNotTheDayBefore() {
    let marker = event("z", "Deadline", date(2026, 11, 3), date(2026, 11, 3))
    #expect(marker.overlaps(day: date(2026, 11, 3), calendar: utc))
    #expect(!marker.overlaps(day: date(2026, 11, 2), calendar: utc))
}

@Test func theDayIsJudgedInTheCalendarsTimeZone() {
    var tokyo = utc
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    // 20:00 UTC on Nov 2 is already 05:00 on Nov 3 in Tokyo.
    let meeting = event("m", "Meeting", date(2026, 11, 2, 20), date(2026, 11, 2, 21))
    #expect(!meeting.overlaps(day: date(2026, 11, 2, 12), calendar: tokyo))
    #expect(meeting.overlaps(day: date(2026, 11, 3, 12), calendar: tokyo))
}

@Test func eventsAreIdentifiableByTheirID() {
    #expect(event("abc", "x", date(2026, 11, 2)).id == "abc")
}
