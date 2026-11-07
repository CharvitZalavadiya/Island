import Testing
import Foundation
@testable import IslandCore

private func summary(_ text: String, use24Hour: Bool = true) -> String {
    switch CronExpression.parse(text) {
    case .success(let expression): return expression.summary(use24Hour: use24Hour)
    case .failure(let problem): return "ERROR: \(problem.message)"
    }
}

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    utc().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

@Test(arguments: [
    ("30 14 * * *", "At 14:30 every day"),
    ("* * * * *", "Every minute"),
    ("*/5 * * * *", "Every 5 minutes"),
    ("*/1 * * * *", "Every minute"),
    ("0 * * * *", "Every hour, on the hour"),
    ("15 * * * *", "At minute 15 past every hour"),
    ("0,30 * * * *", "At minutes 0 and 30 past every hour"),
    ("0 */2 * * *", "Every 2 hours"),
    ("30 */2 * * *", "At minute 30 past every 2 hours"),
    ("0 9,17 * * *", "At 09:00 and 17:00 every day"),
    ("0,30 9 * * *", "At 09:00 and 09:30 every day"),
    ("0 9 * * 1-5", "At 09:00 on Monday through Friday"),
    ("0 22 * * mon-fri", "At 22:00 on Monday through Friday"),
    ("0 0 * * 0", "At 00:00 on Sunday"),
    ("0 0 * * 7", "At 00:00 on Sunday"),
    ("0 10 * * 6,0", "At 10:00 on Saturday and Sunday"),
    ("0 0 1 * *", "At 00:00 on day 1 of the month"),
    ("0 0 1,15 * *", "At 00:00 on days 1 and 15 of the month"),
    ("0 0 1 1 *", "At 00:00 on day 1 of the month, in January"),
    ("0 0 1 JAN,JUL *", "At 00:00 on day 1 of the month, in January and July"),
    ("0 0 * 3-5 *", "At 00:00 every day, in March through May"),
    ("0 0 1 */3 *", "At 00:00 on day 1 of the month, every 3 months"),
    ("0 0 13 * 5", "At 00:00 on day 13 of the month and on Friday"),
    ("0 0 29 2 *", "At 00:00 on day 29 of the month, in February"),
    ("*/15 9-17 * * *", "Every 15 minutes, between 09:00 and 17:59"),
    ("* 9 * * *", "Every minute, between 09:00 and 09:59"),
    ("0 9-17 * * *", "At minute 0 past every hour from 09:00 through 17:00"),
    ("*/10 * * * 1-5", "Every 10 minutes, on Monday through Friday"),
])
func readsCommonSchedulesInPlainEnglish(_ expression: String, _ expected: String) {
    #expect(summary(expression) == expected)
}

@Test func theShortcutsAreUnderstood() {
    #expect(summary("@daily") == "At 00:00 every day")
    #expect(summary("@midnight") == "At 00:00 every day")
    #expect(summary("@hourly") == "Every hour, on the hour")
    #expect(summary("@weekly") == "At 00:00 on Sunday")
    #expect(summary("@monthly") == "At 00:00 on day 1 of the month")
    #expect(summary("@yearly") == "At 00:00 on day 1 of the month, in January")
    #expect(summary("@annually") == summary("@yearly"))
    #expect(summary("@reboot") == "Once, each time the system starts up")
    #expect(summary("@sometimes").hasPrefix("ERROR: Unknown shortcut"))
}

@Test func theClockFollowsTheMacsHourSetting() {
    #expect(summary("30 14 * * *", use24Hour: false) == "At 2:30 PM every day")
    #expect(summary("0 0 * * *", use24Hour: false) == "At 12:00 AM every day")
    #expect(summary("0 12 * * *", use24Hour: false) == "At 12:00 PM every day")
    #expect(summary("0 9,17 * * *", use24Hour: false) == "At 9:00 AM and 5:00 PM every day")
    #expect(summary("*/15 9-17 * * *", use24Hour: false) == "Every 15 minutes, between 9:00 AM and 5:59 PM")
}

@Test func sixFieldsStartWithSecondsAndSevenEndWithAYear() {
    #expect(summary("0 30 14 * * *") == "At 14:30 every day")                    // seconds 0 are not worth saying
    #expect(summary("*/10 * * * * *") == "Every 10 seconds")
    #expect(summary("* * * * * *") == "Every second")
    #expect(summary("30 0 12 * * *") == "At second 30, at 12:00 every day")
    #expect(summary("0 0 8 15 6 * 2027") == "At 08:00 on day 15 of the month, in June, in 2027")
}

@Test func namesAndQuestionMarksAreAccepted() {
    #expect(summary("15 10 ? * MON-FRI") == "At 10:15 on Monday through Friday")
    #expect(summary("0 0 ? JAN SUN") == "At 00:00 on Sunday, in January")
    #expect(summary("0 0 1 feb *") == "At 00:00 on day 1 of the month, in February")
}

@Test func tooFewFieldsIsIncompleteNotAnError() {
    for text in ["30", "30 14", "30 14 * *"] {
        guard case .failure(let problem) = CronExpression.parse(text) else { Issue.record("\(text) parsed"); return }
        #expect(problem.isIncomplete)
    }
}

@Test(arguments: [
    ("61 * * * *", "Minute: 61 is out of range (0–59)."),
    ("* 24 * * *", "Hour: 24 is out of range (0–23)."),
    ("* * 0 * *", "Day of month: 0 is out of range (1–31)."),
    ("* * * 13 *", "Month: 13 is out of range (1–12)."),
    ("* * * * 8", "Day of week: 8 is out of range (0–7)."),
    ("*/0 * * * *", "Minute: the step in \"*/0\" must be a positive number."),
    ("30-10 * * * *", "Minute: the range \"30-10\" ends before it starts."),
    ("* * * foo *", "Month: \"foo\" isn't a value Island understands."),
    ("* * L * *", "Day of month: \"L\" isn't a value Island understands (the special symbols L, W and # aren't supported)."),
    ("1,,2 * * * *", "Minute: there is an empty entry in the list."),
])
func explainsWhatIsWrong(_ expression: String, _ message: String) {
    guard case .failure(let problem) = CronExpression.parse(expression) else { Issue.record("\(expression) parsed"); return }
    #expect(!problem.isIncomplete)
    #expect(problem.message == message)
}

@Test func tooManyFieldsIsAnError() {
    guard case .failure(let problem) = CronExpression.parse("* * * * * * * *") else { Issue.record("parsed"); return }
    #expect(!problem.isIncomplete && problem.message.hasPrefix("Too many fields"))
}

// MARK: Next runs

@Test func nextRunsAreStrictlyAfterNowAndInOrder() {
    let expression = try! CronExpression.parse("30 14 * * *").get()
    let runs = expression.nextRuns(count: 3, after: date(2026, 11, 7, 10), calendar: utc())
    #expect(runs == [date(2026, 11, 7, 14, 30), date(2026, 11, 8, 14, 30), date(2026, 11, 9, 14, 30)])
    // Exactly on a run time: that run has happened, the next one is tomorrow.
    let onTime = expression.nextRuns(count: 1, after: date(2026, 11, 7, 14, 30), calendar: utc())
    #expect(onTime == [date(2026, 11, 8, 14, 30)])
}

@Test func weekdaysSkipTheWeekend() {
    let expression = try! CronExpression.parse("0 9 * * 1-5").get()
    // 7 November 2026 is a Saturday.
    let runs = expression.nextRuns(count: 3, after: date(2026, 11, 7, 10), calendar: utc())
    #expect(runs == [date(2026, 11, 9, 9), date(2026, 11, 10, 9), date(2026, 11, 11, 9)])
}

@Test func stepsAndSeveralTimesADay() {
    let every20 = try! CronExpression.parse("*/20 * * * *").get()
    #expect(every20.nextRuns(count: 3, after: date(2026, 11, 7, 10, 5), calendar: utc())
        == [date(2026, 11, 7, 10, 20), date(2026, 11, 7, 10, 40), date(2026, 11, 7, 11, 0)])
    let twice = try! CronExpression.parse("0 9,17 * * *").get()
    #expect(twice.nextRuns(count: 3, after: date(2026, 11, 7, 12), calendar: utc())
        == [date(2026, 11, 7, 17), date(2026, 11, 8, 9), date(2026, 11, 8, 17)])
}

@Test func aLeapDayWaitsForTheNextLeapYear() {
    let expression = try! CronExpression.parse("0 0 29 2 *").get()
    #expect(expression.nextRuns(count: 2, after: date(2026, 11, 7), calendar: utc()) == [date(2028, 2, 29), date(2032, 2, 29)])
}

@Test func theDayOfMonthAndTheDayOfWeekEitherCount() {
    let expression = try! CronExpression.parse("0 0 13 * 5").get()   // the 13th, and every Friday
    let runs = expression.nextRuns(count: 3, after: date(2026, 11, 7, 10), calendar: utc())
    #expect(runs == [date(2026, 11, 13), date(2026, 11, 20), date(2026, 11, 27)])   // the 13th is a Friday this month
    let more = expression.nextRuns(count: 5, after: date(2026, 11, 27, 12), calendar: utc())
    #expect(more.contains(date(2026, 12, 13)) && more.contains(date(2026, 12, 4)))
}

@Test func secondsAndYearsAndRebootAndImpossibleDates() {
    let seconds = try! CronExpression.parse("*/20 * * * * *").get()
    #expect(seconds.nextRuns(count: 2, after: date(2026, 11, 7, 10, 0, 5), calendar: utc())
        == [date(2026, 11, 7, 10, 0, 20), date(2026, 11, 7, 10, 0, 40)])
    let year = try! CronExpression.parse("0 0 0 1 1 * 2030").get()
    #expect(year.nextRuns(count: 3, after: date(2026, 11, 7), calendar: utc()) == [date(2030, 1, 1)])
    let reboot = try! CronExpression.parse("@reboot").get()
    #expect(reboot.nextRuns(count: 3, after: date(2026, 11, 7), calendar: utc()).isEmpty)
    let impossible = try! CronExpression.parse("0 0 30 2 *").get()
    #expect(impossible.nextRuns(count: 1, after: date(2026, 11, 7), calendar: utc()).isEmpty)
}

// MARK: What the box shows

@Test func theToolAnswersWhateverWasTyped() {
    let now = date(2026, 11, 7, 10)
    #expect(CronTool.evaluate("   ", use24Hour: true, now: now, calendar: utc()) == .empty)
    #expect(CronTool.evaluate("30 14", use24Hour: true, now: now, calendar: utc())
        == .incomplete("A cron expression has 5 fields: minute, hour, day of month, month, day of week."))
    #expect(CronTool.evaluate("99 * * * *", use24Hour: true, now: now, calendar: utc()) == .invalid("Minute: 99 is out of range (0–59)."))
    guard case .described(let summary, let runs) = CronTool.evaluate("30 14 * * *", use24Hour: true, now: now, calendar: utc(), nextRunCount: 2) else {
        Issue.record("not described"); return
    }
    #expect(summary == "At 14:30 every day" && runs.count == 2)
}

@Test func aValidScheduleThatNeverFiresSaysSo() {
    guard case .described(let summary, let runs) = CronTool.evaluate("0 0 30 2 *", use24Hour: true, now: date(2026, 11, 7), calendar: utc()) else {
        Issue.record("not described"); return
    }
    #expect(runs.isEmpty)
    #expect(summary == "At 00:00 on day 30 of the month, in February. No date matches, so this never runs")
    // @reboot has no run times either, but that is not a mistake.
    guard case .described(let reboot, _) = CronTool.evaluate("@reboot", use24Hour: true, now: date(2026, 11, 7), calendar: utc()) else {
        Issue.record("not described"); return
    }
    #expect(reboot == "Once, each time the system starts up")
}
