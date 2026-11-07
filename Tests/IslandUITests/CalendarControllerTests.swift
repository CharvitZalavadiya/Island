import Testing
import Foundation
import IslandCore
@testable import IslandUI

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// "Now" in these tests: Monday 2 November 2026, 09:30.
private let now = date(2026, 11, 2, 9, 30)

@MainActor
private func makeController(_ source: FakeCalendarSource) -> CalendarController {
    CalendarController(source: source, calendar: utc, now: { now })
}

@MainActor
private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

// MARK: Access

@Test @MainActor func theFirstVisitAsksForAccessThenLoadsToday() async {
    let source = FakeCalendarSource(.notDetermined, events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    #expect(source.accessRequests == 1)
    #expect(controller.access == .authorized)
    #expect(controller.selectedDay == date(2026, 11, 2))
    #expect(controller.visibleMonth == date(2026, 11, 1))
    #expect(controller.eventsForSelectedDay.map(\.id) == ["a"])
    controller.stop()
}

@Test @MainActor func anAuthorizedCalendarIsNotAskedAgain() async {
    let source = FakeCalendarSource(.authorized)
    let controller = makeController(source)
    await controller.start()
    #expect(source.accessRequests == 0)
    controller.stop()
}

@Test @MainActor func deniedAccessShowsDeniedAndLoadsNothing() async {
    let source = FakeCalendarSource(.denied, events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.access == .denied)
    #expect(controller.eventsForSelectedDay.isEmpty)
    #expect(controller.daysWithEvents.isEmpty)
    #expect(source.fetches.isEmpty)
    #expect(source.accessRequests == 0)
    #expect(source.subscriptions == 0)
}

@Test @MainActor func refusingThePromptMeansDeniedAndNothingIsLoaded() async {
    let source = FakeCalendarSource(.notDetermined, events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    source.grantsWhenAsked = false
    let controller = makeController(source)
    await controller.start()
    #expect(controller.access == .denied)
    #expect(source.fetches.isEmpty)
}

@Test @MainActor func restrictedAccessLoadsNothing() async {
    let source = FakeCalendarSource(.restricted, events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.access == .restricted)
    #expect(controller.eventsForSelectedDay.isEmpty)
    #expect(source.fetches.isEmpty)
}

@Test @MainActor func accessGrantedLaterInSystemSettingsWorksOnTheNextVisit() async {
    let source = FakeCalendarSource(.denied, events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.eventsForSelectedDay.isEmpty)

    source.access = .authorized
    await controller.start()
    #expect(controller.access == .authorized)
    #expect(controller.eventsForSelectedDay.count == 1)
    controller.stop()
}

@Test @MainActor func leavingTheTabWhileThePromptIsOpenLoadsNothing() async {
    let source = FakeCalendarSource(.notDetermined, events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    source.duringPrompt = { controller.stop() }
    await controller.start()
    #expect(source.fetches.isEmpty)
    #expect(source.subscriptions == 0)
}

// MARK: Today and the selected day

@Test @MainActor func todaysEventsAreSortedAllDayFirst() async {
    let source = FakeCalendarSource(events: [
        fakeEvent("late", "Dinner", start: date(2026, 11, 2, 19)),
        fakeEvent("early", "Standup", start: date(2026, 11, 2, 9)),
        fakeEvent("holiday", "Holiday", start: date(2026, 11, 2), end: date(2026, 11, 2, 23, 59), allDay: true),
    ])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.eventsForSelectedDay.map(\.id) == ["holiday", "early", "late"])
    controller.stop()
}

@Test @MainActor func selectingADayLoadsItsEventsAndKeepsTheMonth() async {
    let source = FakeCalendarSource(events: [
        fakeEvent("today", start: date(2026, 11, 2, 14)), fakeEvent("friday", start: date(2026, 11, 6, 10)),
    ])
    let controller = makeController(source)
    await controller.start()
    controller.selectDay(date(2026, 11, 6, 15, 45))
    #expect(controller.selectedDay == date(2026, 11, 6))
    #expect(controller.eventsForSelectedDay.map(\.id) == ["friday"])
    #expect(controller.visibleMonth == date(2026, 11, 1))
    controller.stop()
}

@Test @MainActor func selectingADayInTheVisibleMonthDoesNotAskTheCalendarAgain() async {
    let source = FakeCalendarSource(events: [fakeEvent("friday", start: date(2026, 11, 6, 10))])
    let controller = makeController(source)
    await controller.start()
    let fetchesAfterStart = source.fetches.count
    controller.selectDay(date(2026, 11, 6))
    controller.selectDay(date(2026, 11, 9))
    #expect(source.fetches.count == fetchesAfterStart)
    controller.stop()
}

@Test @MainActor func aDayWithNothingOnShowsNoEvents() async {
    let source = FakeCalendarSource(events: [fakeEvent("today", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    controller.selectDay(date(2026, 11, 3))
    #expect(controller.eventsForSelectedDay.isEmpty)
    controller.stop()
}

// MARK: Months

@Test @MainActor func theVisibleMonthIsWhatIsFetched() async {
    let source = FakeCalendarSource()
    let controller = makeController(source)
    await controller.start()
    #expect(source.fetches.first?.from == date(2026, 11, 1))
    #expect(source.fetches.first?.to == date(2026, 12, 1))
    controller.stop()
}

@Test @MainActor func changingMonthMarksDaysWithEvents() async {
    let source = FakeCalendarSource(events: [
        fakeEvent("nov", start: date(2026, 11, 2, 14)), fakeEvent("dec", start: date(2026, 12, 10, 9)),
    ])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.daysWithEvents == [date(2026, 11, 2)])

    controller.showMonth(byAdding: 1)
    #expect(controller.visibleMonth == date(2026, 12, 1))
    #expect(controller.daysWithEvents == [date(2026, 12, 10)])
    // The selected day does not move just because the month did.
    #expect(controller.selectedDay == date(2026, 11, 2))
    #expect(controller.eventsForSelectedDay.map(\.id) == ["nov"])

    controller.showMonth(byAdding: -2)
    #expect(controller.visibleMonth == date(2026, 10, 1))
    #expect(controller.daysWithEvents.isEmpty)
    controller.stop()
}

@Test @MainActor func aMultiDayEventMarksEveryDayItCovers() async {
    let source = FakeCalendarSource(events: [
        fakeEvent("trip", "Trip", start: date(2026, 11, 10), end: date(2026, 11, 12, 23, 59), allDay: true)
    ])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.daysWithEvents == [date(2026, 11, 10), date(2026, 11, 11), date(2026, 11, 12)])
    controller.stop()
}

@Test @MainActor func anEventSpanningMidnightAppearsOnBothDays() async {
    let source = FakeCalendarSource(events: [fakeEvent("late", start: date(2026, 11, 2, 23), end: date(2026, 11, 3, 1))])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.eventsForSelectedDay.map(\.id) == ["late"])
    controller.selectDay(date(2026, 11, 3))
    #expect(controller.eventsForSelectedDay.map(\.id) == ["late"])
    #expect(controller.daysWithEvents == [date(2026, 11, 2), date(2026, 11, 3)])
    controller.stop()
}

@Test @MainActor func aSelectedDayOutsideTheVisibleMonthStillShowsItsEvents() async {
    let source = FakeCalendarSource(events: [fakeEvent("end", start: date(2026, 11, 28, 10))])
    let controller = makeController(source)
    await controller.start()
    controller.selectDay(date(2026, 11, 28))
    controller.showMonth(byAdding: 1)
    #expect(controller.eventsForSelectedDay.map(\.id) == ["end"])
    #expect(controller.daysWithEvents.isEmpty)
    controller.stop()
}

@Test @MainActor func goToTodayReturnsToTodayAndItsMonth() async {
    let source = FakeCalendarSource(events: [fakeEvent("today", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    controller.showMonth(byAdding: 3)
    controller.selectDay(date(2027, 2, 14))
    controller.goToToday()
    #expect(controller.visibleMonth == date(2026, 11, 1))
    #expect(controller.selectedDay == date(2026, 11, 2))
    #expect(controller.eventsForSelectedDay.map(\.id) == ["today"])
    controller.stop()
}

@Test @MainActor func comingBackToTheTabStartsOnTodayAgain() async {
    let source = FakeCalendarSource()
    let controller = makeController(source)
    await controller.start()
    controller.showMonth(byAdding: 4)
    controller.stop()
    await controller.start()
    #expect(controller.visibleMonth == date(2026, 11, 1))
    #expect(controller.selectedDay == date(2026, 11, 2))
    controller.stop()
}

@Test @MainActor func todayIsTheStartOfTheCurrentDay() {
    #expect(makeController(FakeCalendarSource()).today == date(2026, 11, 2))
}

// MARK: Changes in the calendar

@Test @MainActor func aStoreChangeRefreshesTheList() async {
    let source = FakeCalendarSource(events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    #expect(controller.eventsForSelectedDay.count == 1)

    source.events.append(fakeEvent("b", start: date(2026, 11, 2, 16)))
    source.announceChange()
    #expect(await waitUntil { controller.eventsForSelectedDay.count == 2 })
    controller.stop()
}

@Test @MainActor func startingTwiceListensOnlyOnce() async {
    let source = FakeCalendarSource()
    let controller = makeController(source)
    await controller.start()
    await controller.start()
    #expect(source.subscriptions == 1)
    controller.stop()
}

@Test @MainActor func leavingTheTabStopsListening() async throws {
    let source = FakeCalendarSource(events: [fakeEvent("a", start: date(2026, 11, 2, 14))])
    let controller = makeController(source)
    await controller.start()
    controller.stop()
    let before = source.fetches.count
    source.announceChange()
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(source.fetches.count == before)
}

// MARK: Telling the alerts that access has been allowed

@Test @MainActor func theAlertsAreToldWhenAccessIsAllowed() async {
    let source = FakeCalendarSource(.notDetermined)
    let controller = makeController(source)
    var told = 0
    controller.onAuthorized = { told += 1 }
    await controller.start()
    #expect(told == 1)
    controller.stop()
}

@Test @MainActor func theAlertsAreNotToldWhenAccessIsDenied() async {
    let source = FakeCalendarSource(.notDetermined)
    source.grantsWhenAsked = false
    let controller = makeController(source)
    var told = 0
    controller.onAuthorized = { told += 1 }
    await controller.start()
    #expect(told == 0)
}

@Test @MainActor func leavingWhileThePromptIsOpenDoesNotTellTheAlerts() async {
    let source = FakeCalendarSource(.notDetermined)
    let controller = makeController(source)
    var told = 0
    controller.onAuthorized = { told += 1 }
    source.duringPrompt = { controller.stop() }
    await controller.start()
    #expect(told == 0)
}
