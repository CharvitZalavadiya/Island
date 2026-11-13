import Foundation
import Testing
@testable import IslandCore

private let width = 121.94, height = 74.08
private let double3 = TrackpadTapTrigger(fingers: 3, taps: 2)
private let triple3 = TrackpadTapTrigger(fingers: 3, taps: 3)
private let double4 = TrackpadTapTrigger(fingers: 4, taps: 2)
private let hold3 = TrackpadTapTrigger.hold(fingers: 3)
private let hold4 = TrackpadTapTrigger.hold(fingers: 4)
private let triple4 = TrackpadTapTrigger(fingers: 4, taps: 3)

/// `count` fingers in the middle of the pad, 15 mm apart, all moved `shift` millimetres to the right.
private func fingers(_ count: Int, shift: Double = 0) -> TrackpadFrame {
    TrackpadFrame(
        touches: (0..<count).map { TrackpadTouch(id: $0 + 1, x: (30 + 15 * Double($0) + shift) / width, y: 37 / height) },
        widthMM: width, heightMM: height)
}

private let lifted = TrackpadFrame(touches: [], widthMM: width, heightMM: height)

/// Someone tapping, with the time passing.
private struct Hand {
    var engine = TrackpadTapEngine()
    var time: TimeInterval = 1
    var wanted: Set<TrackpadTapTrigger>
    var events: [TrackpadTapEvent] = []
    /// When the last finger lifted.
    var lastLift: TimeInterval = 0

    init(wanted: Set<TrackpadTapTrigger>) { self.wanted = wanted }

    mutating func feed(_ frame: TrackpadFrame, after seconds: TimeInterval = 0) {
        time += seconds
        events += engine.process(frame, wanted: wanted, at: time)
    }

    /// One tap: the fingers land (together, or spread over `spread` seconds), stay `hold` seconds (sliding `slide` mm), lift, and
    /// `gap` seconds pass.
    mutating func tap(_ count: Int, spread: Double = 0, hold: Double = 0.12, slide: Double = 0, then gap: Double = 0.1) {
        for landed in 1...count {
            feed(fingers(landed), after: landed == 1 ? 0 : spread / Double(max(count - 1, 1)))
        }
        feed(fingers(count, shift: slide / 2), after: hold / 2)
        feed(fingers(count, shift: slide), after: hold / 2)
        feed(lifted, after: 0.001)
        lastLift = time
        time += gap
    }

    var fired: [TrackpadTapTrigger] { events.map { if case .tapped(let t) = $0 { t } else { fatalError() } } }
}

// MARK: Double and triple taps

@Test func aDoubleTapWithThreeFingersIsReportedAtTheSecondTapWhenNoTripleTapIsWanted() {
    var hand = Hand(wanted: [double3])
    hand.tap(3)
    #expect(hand.events.isEmpty)                                             // one tap is only the start
    hand.tap(3)
    #expect(hand.fired == [double3])                                         // no waiting to see about a third
    #expect(hand.engine.deadline == nil)
}

@Test func whenATripleTapIsWantedTooTheDoubleWaitsToSeeIfAThirdComesThenIsReported() {
    var hand = Hand(wanted: [double3, triple3])
    hand.tap(3)
    hand.tap(3)
    #expect(hand.events.isEmpty)                                             // might still be a triple tap
    let deadline = try! #require(hand.engine.deadline)
    #expect(abs(deadline - (hand.lastLift + TrackpadTapEngine.gapSeconds)) < 1e-9)
    #expect(hand.engine.expire(wanted: hand.wanted, at: deadline - 0.05).isEmpty)           // not yet
    #expect(hand.engine.expire(wanted: hand.wanted, at: deadline) == [.tapped(double3)])    // nothing came: it was a double
    #expect(hand.engine.deadline == nil)
}

@Test func aTripleTapIsReportedAtTheThirdTapAndNotAlsoAsADouble() {
    var hand = Hand(wanted: [double3, triple3])
    hand.tap(3)
    hand.tap(3)
    hand.tap(3)
    #expect(hand.fired == [triple3])
    #expect(hand.engine.deadline == nil)
}

@Test func fourFingersWorkTheSameWayAndNeverCountForThree() {
    var four = Hand(wanted: [double4, triple4])
    four.tap(4)
    four.tap(4)
    four.tap(4)
    #expect(four.fired == [triple4])

    var mixed = Hand(wanted: [double3, double4])
    mixed.tap(3)
    mixed.tap(4)                                                             // different fingers: not a double tap of either
    mixed.tap(3)
    #expect(mixed.fired.isEmpty)
}

@Test func fingersMayLandAFewMomentsApartAndStillMakeATap() {
    var hand = Hand(wanted: [double3])
    hand.tap(3, spread: 0.08)
    hand.tap(3, spread: 0.08)
    #expect(hand.fired == [double3])
}

@Test func aTapReportedLaterOnlyCountsIfItIsOneOfTheWantedOnes() {
    var hand = Hand(wanted: [double4])
    hand.tap(3)
    hand.tap(3)
    #expect(hand.events.isEmpty)
}

// MARK: Not a tap

@Test func oneTwoOrFiveFingersAreNeverATap() {
    for count in [1, 2, 5] {
        var hand = Hand(wanted: Set(TrackpadTapTrigger.all))
        hand.tap(count)
        hand.tap(count)
        hand.tap(count)
        #expect(hand.events.isEmpty && hand.engine.deadline == nil, "\(count) fingers")
    }
}

@Test func fingersThatSlideAreASwipeNotATap() {
    var hand = Hand(wanted: [double3])
    hand.tap(3, slide: 8)                                                    // 8 mm sideways
    hand.tap(3, slide: 8)
    #expect(hand.events.isEmpty)
    var still = Hand(wanted: [double3])
    still.tap(3, slide: 2)                                                   // a little wobble is fine
    still.tap(3, slide: 2)
    #expect(still.fired == [double3])
}

@Test func fingersThatStayDownTooLongAreRestingNotTapping() {
    var hand = Hand(wanted: [double3])
    hand.tap(3, hold: 0.6)
    hand.tap(3, hold: 0.6)
    #expect(hand.events.isEmpty)
}

@Test func fingersThatLandOneAfterAnotherAreNotATap() {
    var hand = Hand(wanted: [double3])
    hand.tap(3, spread: 0.24)                                                // the last one lands 0.24 s after the first
    hand.tap(3, spread: 0.24)
    #expect(hand.events.isEmpty)
}

@Test func aSecondTapThatComesTooLateStartsAgainInsteadOfMakingADouble() {
    var hand = Hand(wanted: [double3])
    hand.tap(3, then: 0.6)                                                   // far longer than the gap
    hand.tap(3)
    #expect(hand.events.isEmpty)
    hand.tap(3)                                                              // but this one, soon after, does make a double
    #expect(hand.fired == [double3])
}

@Test func aDoubleTapIsReportedEvenIfSomethingElseBeginsRightAfter() {
    var hand = Hand(wanted: [double3, triple3])
    hand.tap(3)
    hand.tap(3, then: 0.05)
    #expect(hand.events.isEmpty)                                             // waiting to see about a third
    hand.feed(fingers(3), after: 0)
    hand.feed(fingers(3, shift: 9), after: 0.05)                             // three fingers that slide: a swipe, not a third tap
    #expect(hand.fired == [double3])
}

@Test func expiringWaitsForATouchThatIsStillCouldBeTheNextTap() {
    var hand = Hand(wanted: [double3, triple3])
    hand.tap(3)
    hand.tap(3, then: 0)
    let deadline = try! #require(hand.engine.deadline)
    hand.feed(fingers(3), after: 0.30)                                       // a third tap lands, just inside the gap...
    #expect(hand.engine.expire(wanted: hand.wanted, at: deadline + 0.01).isEmpty)   // ...so the deadline passes quietly
    hand.feed(fingers(3), after: 0.06)
    hand.feed(lifted, after: 0.03)                                           // and it lifts: a triple tap
    #expect(hand.fired == [triple3])
}

@Test func fingersAlreadyDownBeforeTheEngineLookedAreNeverATap() {
    var engine = TrackpadTapEngine()
    var events: [TrackpadTapEvent] = []
    // Three fingers present from the start with a lone finger first, then lifting: counts from the first landing.
    events += engine.process(fingers(1), wanted: [double3], at: 1)
    events += engine.process(fingers(3), wanted: [double3], at: 1.5)          // the others land half a second later: too late
    events += engine.process(lifted, wanted: [double3], at: 1.55)
    #expect(events.isEmpty && engine.deadline == nil)
}

// MARK: The triggers and the settings

@Test func thereAreSixWaysToTapAndEachHasItsOwnNameAndSavedKey() {
    #expect(TrackpadTapTrigger.all.count == 6)
    #expect(Set(TrackpadTapTrigger.all.map(\.id)) == ["3-2", "3-3", "3-hold", "4-2", "4-3", "4-hold"])
    #expect(double3.title == "Three fingers, double tap" && triple4.title == "Four fingers, triple tap")
    #expect(double3.tapsTitle == "Double tap" && triple3.tapsTitle == "Triple tap" && double4.fingersTitle == "Four fingers")
    #expect(hold3.title == "Three fingers, tap and hold" && hold4.title == "Four fingers, tap and hold")
    #expect(hold3.tapsTitle == "Tap and hold" && hold3.isHold && hold4.isHold && !double3.isHold && !triple4.isHold)
}

@Test func tapsAreOnFromTheStartWithNothingAssignedSoNothingHappensByAccident() {
    let settings = Settings()
    #expect(settings.trackpadTapsEnabled)
    #expect(TrackpadTapTrigger.all.allSatisfy { settings.trackpadTapAction(for: $0) == .none })
    #expect(settings.trackpadWantedTaps.isEmpty)
}

@Test func theChosenTapsAreSavedAndOnlyTheOnesThatDoSomethingAreWanted() throws {
    var settings = Settings()
    settings.trackpadTapActions = ["3-2": "mute", "4-3": "openApp", "3-3": "nonsense"]
    settings.trackpadTapApps = ["4-3": "/System/Applications/Notes.app"]
    settings.trackpadTapShortcuts = ["3-2": "", "4-2": "Focus on"]
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(back == settings)
    #expect(back.trackpadTapAction(for: double3) == .mute && back.trackpadTapAction(for: triple4) == .openApp)
    #expect(back.trackpadTapAction(for: triple3) == .none)                  // an unknown name means nothing
    #expect(back.trackpadTapApp(for: triple4) == "/System/Applications/Notes.app" && back.trackpadTapApp(for: double3) == nil)
    #expect(back.trackpadTapShortcut(for: double3) == nil && back.trackpadTapShortcut(for: double4) == "Focus on")
    #expect(back.trackpadWantedTaps == [double3, triple4])
    var off = back
    off.trackpadTapsEnabled = false
    #expect(off.trackpadWantedTaps.isEmpty)
}

@Test func anOldSettingsFileGetsTapsSwitchedOnWithNothingAssigned() throws {
    let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"focusMinutes":40}"#.utf8))
    #expect(old.trackpadTapsEnabled && old.trackpadWantedTaps.isEmpty)
}

@Test func everyActionHasANameASymbolAndOnlyCopyAndPasteNeedAccessibility() {
    #expect(TrackpadTapAction.allCases.count == 12)
    #expect(TrackpadTapAction.allCases.allSatisfy { !$0.title.isEmpty && !$0.shortTitle.isEmpty && !$0.symbol.isEmpty })
    #expect(Set(TrackpadTapAction.allCases.map(\.title)).count == 12)
    #expect(TrackpadTapAction.allCases.filter(\.needsAccessibility) == [.copy, .paste])
}

@Test func aSavedChoiceThatNoLongerExistsMeansNothingSoAnOptionCanBeTakenOut() throws {
    // "spotlight" was once a choice; settings that still say so now simply do nothing for that tap.
    let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"trackpadTapActions":{"3-2":"spotlight","4-2":"mute"}}"#.utf8))
    #expect(old.trackpadTapAction(for: double3) == .none)
    #expect(old.trackpadTapAction(for: double4) == .mute)
    #expect(old.trackpadWantedTaps == [double4])
}

// MARK: Tap and hold

extension Hand {
    /// Puts `count` fingers down together and keeps them there for `seconds` (a frame every `step`), without lifting.
    fileprivate mutating func putDownAndHold(_ count: Int, for seconds: TimeInterval, step: TimeInterval = 0.1) {
        feed(fingers(count))
        var elapsed = 0.0
        while elapsed + step <= seconds + 1e-9 {
            feed(fingers(count), after: step)
            elapsed += step
        }
    }
}

@Test func threeFingersHeldStillAreAHoldReportedOnceWhileTheyAreStillDownAndNotBefore() {
    var hand = Hand(wanted: [hold3])
    hand.putDownAndHold(3, for: 1.4)
    #expect(hand.events.isEmpty)                                             // not yet: the hold time is a second and a half
    hand.feed(fingers(3), after: 0.2)
    #expect(hand.fired == [hold3])                                           // reported while the fingers are still down
    hand.feed(fingers(3), after: 0.5)
    hand.feed(fingers(3), after: 1.0)
    #expect(hand.fired == [hold3])                                           // once only, however long they stay
    hand.feed(lifted, after: 0.05)
    #expect(hand.fired == [hold3])                                           // and nothing more when they lift
}

@Test func fourFingersHeldStillAreAHoldToo() {
    var hand = Hand(wanted: [hold4])
    hand.putDownAndHold(4, for: 1.7)
    #expect(hand.fired == [hold4])
}

@Test func theHoldIsReportedFromTheTimerEvenIfNoFramesArriveWhileTheFingersAreStill() {
    var hand = Hand(wanted: [hold3])
    let landed = hand.time
    hand.feed(fingers(3))
    let deadline = try! #require(hand.engine.deadline)
    #expect(abs(deadline - (landed + TrackpadTapEngine.holdSeconds)) < 1e-9)
    #expect(hand.engine.expire(wanted: hand.wanted, at: deadline - 0.05).isEmpty)
    #expect(hand.engine.expire(wanted: hand.wanted, at: deadline) == [.tapped(hold3)])
    #expect(hand.engine.expire(wanted: hand.wanted, at: deadline + 0.5).isEmpty)       // once only
    #expect(hand.engine.deadline == nil)
}

@Test func fingersThatWanderArriveLateOrAreTheWrongNumberAreNotAHold() {
    // Fingers that slide partway through.
    var slide = Hand(wanted: [hold3, hold4])
    slide.feed(fingers(3))
    slide.feed(fingers(3), after: 0.5)
    slide.feed(fingers(3, shift: 6), after: 0.1)
    slide.feed(fingers(3, shift: 6), after: 1.5)
    #expect(slide.events.isEmpty)

    // The third finger lands half a second after the first two.
    var late = Hand(wanted: [hold3, hold4])
    late.feed(fingers(2))
    late.feed(fingers(3), after: 0.5)
    late.feed(fingers(3), after: 1.6)
    #expect(late.events.isEmpty)

    // Two fingers, five fingers.
    for count in [1, 2, 5] {
        var wrong = Hand(wanted: [hold3, hold4])
        wrong.putDownAndHold(count, for: 2.0)
        #expect(wrong.events.isEmpty, "\(count) fingers")
    }

    // One of the three lifts before the time is up.
    var lifting = Hand(wanted: [hold3, hold4])
    lifting.feed(fingers(3))
    lifting.feed(fingers(2), after: 1.0)
    lifting.feed(fingers(2), after: 1.0)
    #expect(lifting.events.isEmpty)
}

@Test func aHoldIsOnlyForTheNumberOfFingersThatWasSet() {
    var threeAsked = Hand(wanted: [hold3])
    threeAsked.putDownAndHold(4, for: 2.0)
    #expect(threeAsked.events.isEmpty)
    var fourAsked = Hand(wanted: [hold4])
    fourAsked.putDownAndHold(3, for: 2.0)
    #expect(fourAsked.events.isEmpty)
    var none = Hand(wanted: [double3])
    none.putDownAndHold(3, for: 2.0)
    #expect(none.events.isEmpty && none.engine.deadline == nil)             // no hold wanted: nothing is waited for
}

@Test func aHoldIsNotAlsoATapWhenTheFingersLiftAndTapsStillWorkAfterwards() {
    var hand = Hand(wanted: [hold3, double3])
    hand.putDownAndHold(3, for: 1.7)
    hand.feed(lifted, after: 0.05)
    #expect(hand.fired == [hold3])
    hand.time += 0.5
    hand.tap(3)
    hand.tap(3)
    #expect(hand.fired == [hold3, double3])
}

@Test func tapsAreReportedAtOnceWhenAHoldIsWantedToo() {
    var hand = Hand(wanted: [hold3, double3])
    hand.tap(3)
    hand.tap(3)
    #expect(hand.fired == [double3])                                         // a hold is not a longer run of taps: no waiting
}

@Test func aHoldThatFollowsTapsDoesNotSwallowThemButCountsAfterThem() {
    var hand = Hand(wanted: [double3, triple3, hold3])
    hand.tap(3)
    hand.tap(3, then: 0.05)
    #expect(hand.events.isEmpty)                                             // a third tap might still come
    hand.putDownAndHold(3, for: 1.7)                                         // but this is a hold: the double tap is complete
    #expect(hand.fired == [double3, hold3])
}

@Test func theHoldsAreSavedUnderTheirOwnNamesAndAreWantedOnlyWhenAssigned() throws {
    var settings = Settings()
    #expect(settings.trackpadWantedTaps.isEmpty)
    settings.trackpadTapActions = ["3-hold": "mute", "4-hold": "lockScreen", "4-2": "none"]
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(back.trackpadTapAction(for: hold3) == .mute && back.trackpadTapAction(for: hold4) == .lockScreen)
    #expect(back.trackpadWantedTaps == [hold3, hold4])
    #expect(back.trackpadTapAction(for: double4) == .none)
}
