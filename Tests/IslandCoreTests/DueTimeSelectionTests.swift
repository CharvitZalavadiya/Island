import Testing
import Foundation
@testable import IslandCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

private func date(_ d: Int, _ h: Int, _ m: Int, _ s: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m, second: s))!
}

@Test func aSelectionTurnsIntoTheDateItNames() {
    let selection = DueTimeSelection(day: date(4, 0, 0), hour24: 17, minute: 30)
    #expect(selection.date(calendar: utc) == date(4, 17, 30))
}

@Test func aDateIsRoundedUpToTheNextFiveMinutes() {
    #expect(DueTimeSelection(rounding: date(2, 9, 31), calendar: utc).minute == 35)
    #expect(DueTimeSelection(rounding: date(2, 9, 30), calendar: utc).minute == 30)
    #expect(DueTimeSelection(rounding: date(2, 9, 30, 20), calendar: utc).minute == 35)   // seconds count as past
    let late = DueTimeSelection(rounding: date(2, 23, 58), calendar: utc)
    #expect(late.hour24 == 0 && late.minute == 0)
    #expect(late.day == date(3, 0, 0))                                                      // into the next day
}

@Test func twelveHourClockMappingWorksAtNoonAndMidnight() {
    var selection = DueTimeSelection(day: date(2, 0, 0), hour24: 0, minute: 0)
    #expect(selection.hour12 == 12 && !selection.isPM)           // 12 AM
    selection.setHour12(12, isPM: true)
    #expect(selection.hour24 == 12)                              // 12 PM
    selection.setHour12(5, isPM: true)
    #expect(selection.hour24 == 17 && selection.hour12 == 5 && selection.isPM)
    selection.setHour12(12, isPM: false)
    #expect(selection.hour24 == 0)
}

@Test func theDayChipsStartTodayAndTomorrow() {
    let options = TaskDue.dayOptions(now: date(2, 9, 30), calendar: utc)
    #expect(options.count == 6)
    #expect(options[0].title == "Today" && options[0].day == date(2, 0, 0))
    #expect(options[1].title == "Tomorrow" && options[1].day == date(3, 0, 0))
    #expect(options[2].title == "Wed 4")
    #expect(options[5].day == date(7, 0, 0))
}
