import Testing
@testable import IslandCore

@Test func countdownRoundsUpSoItNeverShowsZeroBeforeTheEnd() {
    #expect(ClockFormat.countdown(1500) == "25:00")
    #expect(ClockFormat.countdown(0.2) == "00:01")
    #expect(ClockFormat.countdown(59.01) == "01:00")
    #expect(ClockFormat.countdown(0) == "00:00")
}

@Test func countdownKeepsCountingMinutesPastAnHour() {
    #expect(ClockFormat.countdown(5400) == "90:00")
}

@Test func negativeDurationsShowAsZero() {
    #expect(ClockFormat.countdown(-5) == "00:00")
    #expect(ClockFormat.stopwatch(-5) == "00:00")
}

@Test func stopwatchRoundsDownAndShowsHoursWhenNeeded() {
    #expect(ClockFormat.stopwatch(0) == "00:00")
    #expect(ClockFormat.stopwatch(61.9) == "01:01")
    #expect(ClockFormat.stopwatch(3599) == "59:59")
    #expect(ClockFormat.stopwatch(3661) == "1:01:01")
}
