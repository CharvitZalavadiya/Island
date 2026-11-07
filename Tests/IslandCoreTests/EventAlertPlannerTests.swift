import Testing
import Foundation
@testable import IslandCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func event(_ id: String, minutesAway: Double, allDay: Bool = false) -> CalendarEvent {
    let start = now.addingTimeInterval(minutesAway * 60)
    return CalendarEvent(
        id: id, title: "Event \(id)", start: start, end: start.addingTimeInterval(1800), isAllDay: allDay,
        colorHex: nil, calendarTitle: "Work")
}

@Test func theLeadTimeIsTenMinutes() {
    #expect(EventAlertPlanner.leadTime == 600)
}

@Test func anEventTwentyMinutesAwayFiresInTen() throws {
    let plan = try #require(EventAlertPlanner.next(events: [event("a", minutesAway: 20)], now: now, alerted: []))
    #expect(plan.event.id == "a")
    #expect(plan.fireDate == now.addingTimeInterval(600))
}

@Test func anEventSevenMinutesAwayFiresNow() throws {
    let plan = try #require(EventAlertPlanner.next(events: [event("a", minutesAway: 7)], now: now, alerted: []))
    #expect(plan.fireDate == now)
}

@Test func anEventExactlyTenMinutesAwayFiresNow() throws {
    let plan = try #require(EventAlertPlanner.next(events: [event("a", minutesAway: 10)], now: now, alerted: []))
    #expect(plan.fireDate == now)
}

@Test func anAllDayEventNeverAlerts() {
    #expect(EventAlertPlanner.next(events: [event("a", minutesAway: 30, allDay: true)], now: now, alerted: []) == nil)
}

@Test func anEventThatAlreadyStartedNeverAlerts() {
    #expect(EventAlertPlanner.next(events: [event("a", minutesAway: -5)], now: now, alerted: []) == nil)
}

@Test func anEventStartingExactlyNowDoesNotAlert() {
    #expect(EventAlertPlanner.next(events: [event("a", minutesAway: 0)], now: now, alerted: []) == nil)
}

@Test func anAlertedEventIsSkippedAndTheNextOneIsChosen() throws {
    let events = [event("a", minutesAway: 5), event("b", minutesAway: 30)]
    let plan = try #require(EventAlertPlanner.next(events: events, now: now, alerted: ["a"]))
    #expect(plan.event.id == "b")
    #expect(plan.fireDate == now.addingTimeInterval(20 * 60))
}

@Test func theEarliestUpcomingEventWinsWhateverTheOrderGiven() throws {
    let events = [event("late", minutesAway: 90), event("soon", minutesAway: 25), event("mid", minutesAway: 40)]
    #expect(try #require(EventAlertPlanner.next(events: events, now: now, alerted: [])).event.id == "soon")
}

@Test func pastAndAllDayEventsDoNotHideALaterRealOne() throws {
    let events = [
        event("past", minutesAway: -30), event("allday", minutesAway: 5, allDay: true), event("real", minutesAway: 45),
    ]
    #expect(try #require(EventAlertPlanner.next(events: events, now: now, alerted: [])).event.id == "real")
}

@Test func noEventsGivesNil() {
    #expect(EventAlertPlanner.next(events: [], now: now, alerted: []) == nil)
}

@Test func everyEventAlertedGivesNil() {
    #expect(EventAlertPlanner.next(events: [event("a", minutesAway: 20)], now: now, alerted: ["a"]) == nil)
}

@Test func twoEventsAtTheSameTimeAlertOneAtATime() throws {
    let events = [event("b", minutesAway: 20), event("a", minutesAway: 20)]
    let first = try #require(EventAlertPlanner.next(events: events, now: now, alerted: []))
    #expect(first.event.id == "a")   // a stable choice: the lower id
    let second = try #require(EventAlertPlanner.next(events: events, now: now, alerted: ["a"]))
    #expect(second.event.id == "b")
}
