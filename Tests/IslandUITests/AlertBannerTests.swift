import Testing
import Foundation
@testable import IslandUI

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Test func theBannerSaysHowLongIsLeftToTheNearestMinute() {
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-600)) == "Starts in 10 min")
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-60)) == "Starts in 1 min")
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-552)) == "Starts in 9 min")
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-90)) == "Starts in 2 min")
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-89)) == "Starts in 1 min")
}

@Test func aBrandNewAlertStillSaysTenMinutesEvenIfItAppearsAFewMillisecondsLate() {
    // The alert fires exactly ten minutes ahead; the first draw happens a little later and must not say 9.
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-599.95)) == "Starts in 10 min")
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-597)) == "Starts in 10 min")
}

@Test func underAMinuteItSaysSoAndAtTheStartItSaysNow() {
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-59)) == "Starts in under a minute")
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(-1)) == "Starts in under a minute")
    #expect(AlertBanner.countdown(start: start, now: start) == "Starting now")
}

@Test func afterTheStartItStillSaysNowRatherThanANegativeTime() {
    #expect(AlertBanner.countdown(start: start, now: start.addingTimeInterval(120)) == "Starting now")
}
