import Testing
import Foundation
@testable import IslandCore

private func calendar(firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, calendar: Calendar = calendar()) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func leadingNils(_ week: [Date?]) -> Int { week.prefix { $0 == nil }.count }
private func trailingNils(_ week: [Date?]) -> Int { week.reversed().prefix { $0 == nil }.count }
private func days(_ weeks: [[Date?]]) -> [Date] { weeks.flatMap { $0 }.compactMap { $0 } }

@Test func octoberTwentyTwentySixStartsOnThursday() {
    let weeks = MonthGrid.weeks(containing: date(2026, 10, 15), calendar: calendar())
    // Sunday-first: Sun, Mon, Tue, Wed come before Thursday the 1st.
    #expect(leadingNils(weeks[0]) == 4)
    #expect(weeks.count == 5)
    #expect(days(weeks).count == 31)
    #expect(trailingNils(weeks[4]) == 0)   // the 31st is a Saturday
}

@Test func mondayFirstShiftsThePadding() {
    let weeks = MonthGrid.weeks(containing: date(2026, 10, 15), calendar: calendar(firstWeekday: 2))
    #expect(leadingNils(weeks[0]) == 3)
    #expect(weeks.count == 5)
    #expect(trailingNils(weeks[4]) == 1)
}

@Test func everyRowHasSevenCells() {
    for month in 1...12 {
        for week in MonthGrid.weeks(containing: date(2026, month, 10), calendar: calendar()) {
            #expect(week.count == 7, "month \(month)")
        }
    }
}

@Test func februaryInALeapYearHas29Days() {
    #expect(days(MonthGrid.weeks(containing: date(2028, 2, 10), calendar: calendar())).count == 29)
    #expect(days(MonthGrid.weeks(containing: date(2027, 2, 10), calendar: calendar())).count == 28)
}

@Test func aMonthCanNeedSixRows() {
    // August 2026 starts on a Saturday: six blanks plus 31 days is 37 cells.
    let weeks = MonthGrid.weeks(containing: date(2026, 8, 1), calendar: calendar())
    #expect(weeks.count == 6)
    #expect(leadingNils(weeks[0]) == 6)
}

@Test func aFebruaryOfExactlyFourRows() {
    // February 2026 starts on a Sunday and has 28 days.
    let weeks = MonthGrid.weeks(containing: date(2026, 2, 14), calendar: calendar())
    #expect(weeks.count == 4)
    #expect(leadingNils(weeks[0]) == 0)
    #expect(trailingNils(weeks[3]) == 0)
}

@Test func cellsAreStartOfDayDatesInOrderAndAnyDateOfTheMonthWorks() {
    let cal = calendar()
    let fromMiddle = MonthGrid.weeks(containing: date(2026, 10, 17, 15), calendar: cal)
    let fromEnd = MonthGrid.weeks(containing: date(2026, 10, 31, 23), calendar: cal)
    #expect(fromMiddle == fromEnd)
    let all = days(fromMiddle)
    #expect(all.first == date(2026, 10, 1))
    #expect(all.last == date(2026, 10, 31))
    #expect(all.map { cal.component(.day, from: $0) } == Array(1...31))
    #expect(all.allSatisfy { cal.startOfDay(for: $0) == $0 })
}

@Test func theFirstOfTheMonthLandsInTheRightColumn() {
    let cal = calendar()
    let weeks = MonthGrid.weeks(containing: date(2026, 10, 1), calendar: cal)
    let column = weeks[0].firstIndex { $0 != nil }!
    #expect(cal.component(.weekday, from: weeks[0][column]!) == 5)   // Thursday
    #expect(column == 4)
}

@Test func titleAndLetters() {
    #expect(MonthGrid.title(for: date(2026, 10, 15), calendar: calendar()) == "October 2026")
    #expect(MonthGrid.weekdayLetters(calendar: calendar()) == ["S", "M", "T", "W", "T", "F", "S"])
    #expect(MonthGrid.weekdayLetters(calendar: calendar(firstWeekday: 2)) == ["M", "T", "W", "T", "F", "S", "S"])
}

@Test func monthArithmeticCrossesYearsAndLandsOnTheFirst() {
    let cal = calendar()
    #expect(MonthGrid.month(byAdding: 1, to: date(2026, 10, 31), calendar: cal) == date(2026, 11, 1))
    #expect(MonthGrid.month(byAdding: 3, to: date(2026, 11, 15), calendar: cal) == date(2027, 2, 1))
    #expect(MonthGrid.month(byAdding: -10, to: date(2026, 8, 15), calendar: cal) == date(2025, 10, 1))
    #expect(MonthGrid.month(byAdding: 0, to: date(2026, 10, 17, 12), calendar: cal) == date(2026, 10, 1))
    // Adding a month to the 31st must not skip a short month.
    #expect(MonthGrid.month(byAdding: 1, to: date(2026, 1, 31), calendar: cal) == date(2026, 2, 1))
}

// MARK: weekends (Sunday and Saturday are shown in red)

@Test func saturdayAndSundayAreWeekendsWhateverTheFirstWeekday() {
    let cal = calendar()
    #expect(MonthGrid.isWeekend(date(2026, 10, 31), calendar: cal))    // Saturday
    #expect(MonthGrid.isWeekend(date(2026, 11, 1), calendar: cal))     // Sunday
    #expect(!MonthGrid.isWeekend(date(2026, 10, 30), calendar: cal))   // Friday
    #expect(!MonthGrid.isWeekend(date(2026, 11, 2), calendar: cal))    // Monday
    #expect(MonthGrid.isWeekend(date(2026, 11, 1), calendar: calendar(firstWeekday: 2)))
}

@Test func theHeaderMarksTheWeekendColumns() {
    #expect(MonthGrid.weekendColumns(calendar: calendar()) == [true, false, false, false, false, false, true])
    #expect(MonthGrid.weekendColumns(calendar: calendar(firstWeekday: 2)) == [false, false, false, false, false, true, true])
}

@Test func theGridAndTheHeaderAgreeOnWhichColumnsAreWeekends() {
    for firstWeekday in [1, 2, 7] {
        let cal = calendar(firstWeekday: firstWeekday)
        let columns = MonthGrid.weekendColumns(calendar: cal)
        for week in MonthGrid.weeks(containing: date(2026, 10, 10), calendar: cal) {
            for (column, day) in week.enumerated() {
                if let day { #expect(MonthGrid.isWeekend(day, calendar: cal) == columns[column]) }
            }
        }
    }
}
