import Testing
import AppKit
import Foundation
import IslandCore
@testable import IslandUI

private final class Clock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Timers the test fires by hand.
@MainActor
private final class FakeTimers {
    final class Entry {
        let date: Date
        let action: @MainActor () -> Void
        var cancelled = false
        var fired = false
        init(date: Date, action: @escaping @MainActor () -> Void) { self.date = date; self.action = action }
    }
    private(set) var entries: [Entry] = []

    func schedule(_ date: Date, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let entry = Entry(date: date, action: action)
        entries.append(entry)
        return { entry.cancelled = true }
    }

    var active: [Entry] { entries.filter { !$0.cancelled && !$0.fired } }

    /// Fires the entry (it must still be active).
    func fire(_ entry: Entry) {
        guard !entry.cancelled, !entry.fired else { return }
        entry.fired = true
        entry.action()
    }

    /// The active timer that is due at `date`.
    func timer(at date: Date) -> Entry? { active.first { $0.date == date } }
}

@MainActor
private struct Rig {
    let clock = Clock()
    let timers = FakeTimers()
    let source: FakeCalendarSource
    let model: IslandModel
    let scheduler: AlertScheduler
    let wake = NotificationCenter()
    let missionControl: MissionControlFlag

    final class MissionControlFlag { var active = false }

    init(access: CalendarAccess = .authorized, events: [CalendarEvent] = []) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-ui-tests-\(UUID().uuidString)")
        let settings = SettingsStore(store: FileStore(url: directory.appendingPathComponent("settings.json"), defaultValue: Settings()))
        model = IslandModel(settings: settings)
        source = FakeCalendarSource(access, events: events)
        let flag = MissionControlFlag()
        missionControl = flag
        let clock = self.clock
        let timers = self.timers
        scheduler = AlertScheduler(
            source: source, model: model, now: { clock.now },
            isMissionControlActive: { flag.active }, dismissAfter: 10,
            schedule: { date, action in timers.schedule(date, action) },
            wakeNotifications: wake)
    }

    func event(_ id: String, minutesAway: Double, title: String? = nil, allDay: Bool = false, color: UInt32? = nil) -> CalendarEvent {
        fakeEvent(
            id, title ?? "Event \(id)", start: clock.now.addingTimeInterval(minutesAway * 60), allDay: allDay, colorHex: color)
    }

    func at(_ minutes: Double) -> Date { clock.now.addingTimeInterval(minutes * 60) }
}

private func waitUntil(timeout: TimeInterval = 30, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

// MARK: Planning

@Test @MainActor func anUpcomingEventSchedulesOneAlertTenMinutesBeforeItStarts() {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 20)]
    rig.scheduler.start()
    #expect(rig.timers.active.count == 1)
    #expect(rig.timers.active.first?.date == rig.at(10))
    rig.scheduler.stop()
}

@Test @MainActor func onlyTheNextTwentyFourHoursAreLookedAt() {
    let rig = Rig()
    rig.scheduler.start()
    #expect(rig.source.fetches.first?.from == rig.clock.now)
    #expect(rig.source.fetches.first?.to == rig.clock.now.addingTimeInterval(24 * 3600))
    rig.scheduler.stop()
}

@Test @MainActor func theAlertShowsTitleStartAndColourAtTheFireTime() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 20, title: "Design review", color: 0xFF8800)]
    rig.scheduler.start()
    #expect(rig.model.alert == nil)

    rig.clock.advance(10 * 60)
    rig.timers.fire(try #require(rig.timers.timer(at: rig.at(0))))
    let alert = try #require(rig.model.alert)
    #expect(alert.eventID == "a")
    #expect(alert.title == "Design review")
    #expect(alert.start == rig.at(10))
    #expect(alert.colorHex == 0xFF8800)
    rig.scheduler.stop()
}

@Test @MainActor func anEventLessThanTenMinutesAwayAlertsAtOnce() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.scheduler.start()
    let timer = try #require(rig.timers.active.first)
    #expect(timer.date == rig.clock.now)
    rig.timers.fire(timer)
    #expect(rig.model.alert?.eventID == "a")
    rig.scheduler.stop()
}

@Test @MainActor func anAlertedEventNeverAlertsAgain() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    rig.scheduler.reschedule()
    rig.scheduler.reschedule()
    // Only the banner's own ten-second countdown is due soon: nothing is planned for "a" any more.
    let soon = rig.timers.active.filter { $0.date < rig.at(60) }
    #expect(soon.count == 1)
    #expect(soon.first?.date == rig.at(10.0 / 60))
    rig.scheduler.stop()
}

@Test @MainActor func allDayAndPastEventsNeverScheduleAnAlert() {
    let rig = Rig()
    rig.source.events = [rig.event("allday", minutesAway: 30, allDay: true), rig.event("past", minutesAway: -20)]
    rig.scheduler.start()
    #expect(rig.timers.active.allSatisfy { $0.date >= rig.at(60) })   // at most the slow re-plan
    rig.scheduler.stop()
}

@Test @MainActor func nothingToAlertAboutKeepsOnlyASlowReplanTimer() throws {
    let rig = Rig()
    rig.scheduler.start()
    let timer = try #require(rig.timers.active.first)
    #expect(rig.timers.active.count == 1)
    #expect(timer.date == rig.at(12 * 60))     // an event added tomorrow must not be missed on a Mac left running
    rig.scheduler.stop()
    #expect(rig.timers.active.isEmpty)
}

@Test @MainActor func theSlowReplanFindsAnEventThatCameWithinReach() throws {
    let rig = Rig()
    let eventStart = rig.at(30 * 60)    // 30 hours away: out of reach for now
    rig.source.events = [rig.event("later", minutesAway: 30 * 60)]
    rig.scheduler.start()
    let replan = try #require(rig.timers.active.first)
    #expect(replan.date == rig.at(12 * 60))

    rig.clock.advance(12 * 3600)
    rig.timers.fire(replan)
    // Now it is 18 hours away: within reach, so it is planned for 10 minutes before it starts.
    #expect(rig.timers.timer(at: eventStart.addingTimeInterval(-600)) != nil)
    rig.scheduler.stop()
}

// MARK: Changes

@Test @MainActor func aStoreChangeReplans() async throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 20)]
    rig.scheduler.start()
    let first = try #require(rig.timers.active.first)
    #expect(first.date == rig.at(10))

    // The meeting is moved from 20 to 50 minutes away.
    rig.source.events = [rig.event("a", minutesAway: 50)]
    rig.source.announceChange()
    #expect(await waitUntil { rig.timers.active.contains { $0.date == rig.at(40) } })
    #expect(first.cancelled)
    #expect(rig.timers.active.count == 1)
    rig.scheduler.stop()
}

@Test @MainActor func aDeletedEventNoLongerAlerts() async throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 20)]
    rig.scheduler.start()
    let first = try #require(rig.timers.active.first)
    rig.source.events = []
    rig.source.announceChange()
    #expect(await waitUntil { first.cancelled })
    #expect(rig.timers.active.allSatisfy { $0.date >= rig.at(60) })
    rig.scheduler.stop()
}

@Test @MainActor func sleepingPastTheFireTimeAlertsOnceOnWake() async throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 20)]
    rig.scheduler.start()
    let original = try #require(rig.timers.active.first)

    // The Mac sleeps for 15 minutes: the timer did not fire, the event is 5 minutes away.
    rig.clock.advance(15 * 60)
    rig.wake.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(await waitUntil { rig.timers.active.contains { $0.date == rig.clock.now } })
    #expect(original.cancelled)
    let now = try #require(rig.timers.timer(at: rig.clock.now))
    rig.timers.fire(now)
    #expect(rig.model.alert?.eventID == "a")

    // The old timer, if it had somehow still fired, must not alert a second time.
    var secondAlertCount = 0
    rig.model.dismissAlert()
    original.action()
    if rig.model.alert != nil { secondAlertCount += 1 }
    #expect(secondAlertCount == 0)
    rig.scheduler.stop()
}

@Test @MainActor func sleepingPastTheStartOfAnEventNeverAlertsForIt() async throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 20)]
    rig.scheduler.start()
    let original = try #require(rig.timers.active.first)

    rig.clock.advance(25 * 60)     // the meeting began while the Mac slept
    rig.wake.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(await waitUntil { original.cancelled })
    #expect(rig.model.alert == nil)
    #expect(rig.timers.active.allSatisfy { $0.date >= rig.clock.now.addingTimeInterval(60 * 60) })
    rig.scheduler.stop()
}

// MARK: Permission

@Test @MainActor func noPermissionSchedulesNothingAndReadsNothing() {
    for access in [CalendarAccess.denied, .restricted, .notDetermined] {
        let rig = Rig(access: access)
        rig.source.events = [rig.event("a", minutesAway: 20)]
        rig.scheduler.start()
        #expect(rig.timers.active.isEmpty, "\(access)")
        #expect(rig.source.fetches.isEmpty, "\(access)")
        #expect(rig.source.subscriptions == 0, "\(access)")
    }
}

@Test @MainActor func permissionGrantedLaterIsPickedUpByReschedule() {
    let rig = Rig(access: .notDetermined)
    rig.source.events = [rig.event("a", minutesAway: 20)]
    rig.scheduler.start()
    #expect(rig.timers.active.isEmpty)

    rig.source.access = .authorized
    rig.scheduler.start()
    #expect(rig.timers.timer(at: rig.at(10)) != nil)
    rig.scheduler.stop()
}

@Test @MainActor func startingTwiceListensOnlyOnce() {
    let rig = Rig()
    rig.scheduler.start()
    rig.scheduler.start()
    #expect(rig.source.subscriptions == 1)
    rig.scheduler.stop()
}

// MARK: Mission Control

@Test @MainActor func missionControlDelaysTheAlertUntilItEnds() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.missionControl.active = true
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    #expect(rig.model.alert == nil)

    // It tries again in two seconds, and shows the alert once Mission Control is gone.
    rig.clock.advance(2)
    let retry = try #require(rig.timers.timer(at: rig.clock.now))
    rig.missionControl.active = false
    rig.timers.fire(retry)
    #expect(rig.model.alert?.eventID == "a")
    rig.scheduler.stop()
}

@Test @MainActor func missionControlThatNeverEndsEventuallyGivesUp() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 200)]   // far enough that it never starts during the test
    rig.missionControl.active = true
    rig.scheduler.start()
    rig.clock.advance(190 * 60)
    rig.scheduler.reschedule()
    var fires = 0
    while let timer = rig.timers.timer(at: rig.clock.now) ?? rig.timers.active.filter({ $0.date <= rig.clock.now.addingTimeInterval(2) }).first, fires < 100 {
        rig.clock.advance(2)
        rig.timers.fire(timer)
        fires += 1
    }
    #expect(rig.model.alert == nil)
    #expect(fires <= 61)   // two minutes of two-second tries, then it stops
    rig.scheduler.stop()
}

@Test @MainActor func anEventThatStartedWhileMissionControlWasUpIsNotAnnouncedLate() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.missionControl.active = true
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    rig.clock.advance(8 * 60)   // the event has begun
    rig.missionControl.active = false
    if let retry = rig.timers.active.first(where: { $0.date <= rig.clock.now }) { rig.timers.fire(retry) }
    #expect(rig.model.alert == nil)
    rig.scheduler.stop()
}

// MARK: Showing, replacing, dismissing

@Test @MainActor func theAlertDismissesItselfAfterTenSeconds() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    #expect(rig.model.alert != nil)

    let dismiss = try #require(rig.timers.timer(at: rig.at(10.0 / 60)))   // ten seconds from now
    rig.clock.advance(10)
    rig.timers.fire(dismiss)
    #expect(rig.model.alert == nil)
    rig.scheduler.stop()
}

@Test @MainActor func aNewAlertReplacesTheOldBannerAndRestartsTheCountdown() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7), rig.event("b", minutesAway: 8)]
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    #expect(rig.model.alert?.eventID == "a")
    let firstDismiss = try #require(rig.timers.active.first { $0.date == rig.at(10.0 / 60) })

    rig.clock.advance(5)
    let second = try #require(rig.timers.active.first { $0.date <= rig.clock.now })
    rig.timers.fire(second)
    #expect(rig.model.alert?.eventID == "b")
    #expect(firstDismiss.cancelled)
    // Only the second banner's own countdown is running, ten seconds from when it appeared.
    #expect(rig.timers.active.filter { $0.date == rig.clock.now.addingTimeInterval(10) }.count == 1)
    rig.scheduler.stop()
}

@Test @MainActor func hoveringTheBannerHoldsTheCountdownAndLeavingRestartsIt() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    let countdown = try #require(rig.timers.active.first { $0.date == rig.at(10.0 / 60) })

    rig.scheduler.holdDismiss(true)
    #expect(countdown.cancelled)
    rig.clock.advance(60)
    #expect(rig.model.alert != nil)

    rig.scheduler.holdDismiss(false)
    #expect(rig.timers.active.contains { $0.date == rig.clock.now.addingTimeInterval(10) })
    rig.scheduler.stop()
}

@Test @MainActor func leavingAfterTheAlertWasAlreadyDismissedStartsNoCountdown() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    rig.scheduler.holdDismiss(true)
    rig.scheduler.dismissNow()
    let before = rig.timers.active.count
    rig.scheduler.holdDismiss(false)
    #expect(rig.timers.active.count == before)
    #expect(rig.model.alert == nil)
    rig.scheduler.stop()
}

@Test @MainActor func clickingDismissesTheAlertAtOnceAndStopsItsCountdown() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7)]
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    let countdown = try #require(rig.timers.active.first { $0.date == rig.at(10.0 / 60) })
    rig.scheduler.dismissNow()
    #expect(rig.model.alert == nil)
    #expect(countdown.cancelled)
    rig.scheduler.stop()
}

@Test @MainActor func stoppingClearsTheBannerAndEveryTimer() throws {
    let rig = Rig()
    rig.source.events = [rig.event("a", minutesAway: 7), rig.event("b", minutesAway: 40)]
    rig.scheduler.start()
    rig.timers.fire(try #require(rig.timers.active.first))
    rig.scheduler.stop()
    #expect(rig.timers.active.isEmpty)
}

@Test @MainActor func aSampleAlertCanBeShownForChecking() throws {
    let rig = Rig()
    rig.scheduler.showSample()
    let alert = try #require(rig.model.alert)
    #expect(!alert.title.isEmpty)
    #expect(alert.start > rig.clock.now)
    rig.scheduler.stop()
}
