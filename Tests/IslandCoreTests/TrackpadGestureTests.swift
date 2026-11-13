import Foundation
import Testing
@testable import IslandCore

// The pad of a MacBook Air: 122 x 74 mm. Touches are given in millimetres from the bottom-left corner.
private let width = 121.94, height = 74.08
private let allEdges = Set(TrackpadEdge.allCases)

private func frame(_ fingers: (id: Int, x: Double, y: Double)...) -> TrackpadFrame {
    TrackpadFrame(
        touches: fingers.map { TrackpadTouch(id: $0.id, x: $0.x / width, y: $0.y / height) }, widthMM: width, heightMM: height)
}

private let lifted = TrackpadFrame(touches: [], widthMM: width, heightMM: height)

/// Feeds frames one after another (a hundredth of a second apart unless told) and collects everything that happened.
private struct Pad {
    var engine = TrackpadGestureEngine()
    var time: TimeInterval = 0
    var events: [TrackpadGestureEvent] = []

    @discardableResult
    mutating func feed(_ frame: TrackpadFrame, edges: Set<TrackpadEdge> = allEdges, after seconds: TimeInterval = 0.01, edgeMM: Double = 9) -> [TrackpadGestureEvent] {
        time += seconds
        let new = engine.process(frame, activeEdges: edges, edgeMM: edgeMM, at: time)
        events += new
        return new
    }

    /// Everything moved so far on this edge, as a fraction of the edge.
    func movedTotal(_ edge: TrackpadEdge) -> Double {
        events.reduce(0) { sum, event in
            if case .moved(edge, let delta) = event { return sum + delta }
            return sum
        }
    }

    var began: [TrackpadEdge] { events.compactMap { if case .began(let e) = $0 { e } else { nil } } }
    var ended: [TrackpadEdge] { events.compactMap { if case .ended(let e) = $0 { e } else { nil } } }
    var cancelled: [TrackpadEdge] { events.compactMap { if case .cancelled(let e) = $0 { e } else { nil } } }
}

// MARK: A clean slide

@Test func slidingUpTheRightEdgeBeginsAfterAFewMillimetresAndReportsHowFarItWent() {
    var pad = Pad()
    #expect(pad.feed(frame((1, 118, 20))) == [.candidateStarted(.right)])    // touched down in the strip: nothing yet
    #expect(pad.feed(frame((1, 118, 21))).isEmpty)                            // 1 mm: still not a gesture
    #expect(pad.feed(frame((1, 118, 23))) == [.began(.right)])                // 3 mm along the edge: it is one
    pad.feed(frame((1, 118, 57)))                                             // up to 37 mm from the start: half the pad's height
    #expect(abs(pad.movedTotal(.right) - (57 - 23) / height) < 1e-9)          // counted from where it began
    #expect(pad.feed(lifted) == [.ended(.right)])
}

@Test func slidingDownIsNegativeAndSlidingRightAlongTheTopIsPositive() {
    var down = Pad()
    down.feed(frame((1, 3, 50)))
    down.feed(frame((1, 3, 46)))
    down.feed(frame((1, 3, 30)))
    #expect(down.began == [.left] && down.movedTotal(.left) < 0)

    var right = Pad()
    right.feed(frame((1, 30, 71)))
    right.feed(frame((1, 34, 71)))
    right.feed(frame((1, 94, 71)))
    #expect(right.began == [.top])
    #expect(abs(right.movedTotal(.top) - (94 - 34) / width) < 1e-9)           // a horizontal edge is measured against the width
}

@Test func theGestureFollowsTheFingerBackAndForthAndEndsWhenItLifts() {
    var pad = Pad()
    pad.feed(frame((1, 118, 20)))
    pad.feed(frame((1, 118, 30)))
    pad.feed(frame((1, 118, 50)))
    pad.feed(frame((1, 118, 40)))                                            // back down 10 mm
    #expect(pad.movedTotal(.right) > 0 && pad.movedTotal(.right) < (50 - 30) / height)
    pad.feed(lifted)
    #expect(pad.ended == [.right])
}

@Test func driftingIntoThePadWhileSlidingDoesNotStopAGestureThatAlreadyBegan() {
    var pad = Pad()
    pad.feed(frame((1, 118, 20)))
    pad.feed(frame((1, 118, 30)))
    pad.feed(frame((1, 105, 45)))                                            // 13 mm sideways: the finger wandered, still sliding
    #expect(pad.cancelled.isEmpty && pad.movedTotal(.right) > 0)
}

// MARK: Not a gesture: moving the pointer, tapping, resting

@Test func aTouchInTheMiddleOfThePadIsNeverAGestureEvenIfItSlidesIntoAStrip() {
    var pad = Pad()
    pad.feed(frame((1, 60, 30)))
    pad.feed(frame((1, 100, 30)))
    pad.feed(frame((1, 118, 31)))
    pad.feed(frame((1, 118, 60)))
    #expect(pad.events.isEmpty)
}

@Test func aTouchInACornerIsIgnored() {
    for corner in [(2.0, 2.0), (120.0, 2.0), (2.0, 72.0), (120.0, 72.0), (118.0, 6.0), (4.0, 70.0)] {
        var pad = Pad()
        pad.feed(frame((1, corner.0, corner.1)))
        pad.feed(frame((1, corner.0, corner.1 > 37 ? corner.1 - 20 : corner.1 + 20)))
        pad.feed(frame((1, corner.0 > 60 ? corner.0 - 20 : corner.0 + 20, corner.1)))
        #expect(pad.events.isEmpty, "corner \(corner)")
    }
}

@Test func anEdgeThatDoesNothingNeverStartsAGesture() {
    var pad = Pad()
    let edges: Set<TrackpadEdge> = [.left]                                   // the right edge is off
    pad.feed(frame((1, 118, 20)), edges: edges)
    pad.feed(frame((1, 118, 30)), edges: edges)
    pad.feed(frame((1, 118, 50)), edges: edges)
    #expect(pad.events.isEmpty)
}

@Test func aFingerMovingIntoThePadFromTheEdgeIsMovingThePointerAndNeverBecomesAGesture() {
    var pad = Pad()
    pad.feed(frame((1, 118, 30)))                                            // starts in the strip...
    pad.feed(frame((1, 110, 31)))                                            // ...and heads into the pad
    pad.feed(frame((1, 100, 32)))
    pad.feed(frame((1, 100, 60)))                                            // sliding up later, but it is too late
    #expect(pad.events == [.candidateStarted(.right)])
    pad.feed(lifted)
    pad.feed(frame((1, 118, 20)))                                            // a fresh touch can start one
    pad.feed(frame((1, 118, 40)))
    #expect(pad.began == [.right])
}

@Test func aTapOnTheEdgeDoesNothing() {
    var pad = Pad()
    pad.feed(frame((1, 118, 30)))
    pad.feed(lifted, after: 0.08)
    #expect(pad.events == [.candidateStarted(.right)])
}

@Test func aFingerThatRestsOnTheEdgeFirstNeverBecomesAGestureWhenItMovesLater() {
    var pad = Pad()
    pad.feed(frame((1, 118, 20)))
    pad.feed(frame((1, 118, 20.5)), after: 0.9)                              // a long rest
    pad.feed(frame((1, 118, 30)))
    pad.feed(frame((1, 118, 50)))
    #expect(pad.began.isEmpty)
}

@Test func aSlantedSlideCountsOnceItIsStraightEnoughAndNotBefore() {
    var pad = Pad()
    pad.feed(frame((1, 116, 20)))
    pad.feed(frame((1, 118.8, 23)))                                          // 3 mm along but 2.8 across: too slanted
    #expect(pad.began.isEmpty)
    pad.feed(frame((1, 118.8, 28)))                                          // 8 along, 2.8 across: straight enough
    #expect(pad.began == [.right])
}

// MARK: Fingers that are not alone

@Test func aSecondFingerCancelsTheGestureAndNothingStartsAgainUntilEveryFingerHasLifted() {
    var pad = Pad()
    pad.feed(frame((1, 118, 20)))
    pad.feed(frame((1, 118, 30)))
    pad.feed(frame((1, 118, 40)))
    pad.feed(frame((1, 118, 41), (2, 60, 30)))                               // a second finger comes down
    #expect(pad.cancelled == [.right])
    pad.feed(frame((1, 118, 60)))                                            // the second one lifts, the first keeps sliding
    pad.feed(frame((1, 118, 70)))
    #expect(pad.began == [.right] && pad.ended.isEmpty)                      // nothing new: it began before
    let before = pad.events.count
    pad.feed(lifted)
    pad.feed(frame((1, 118, 20)))
    pad.feed(frame((1, 118, 40)))
    #expect(pad.events.count == before + 2 && pad.events.contains(.began(.right)))
}

@Test func twoFingersFromTheStartNeverMakeAGestureEvenWhenOneLeaves() {
    var pad = Pad()
    pad.feed(frame((1, 118, 20), (2, 60, 30)))
    pad.feed(frame((1, 118, 25)))                                            // the other one lifted: this is not a fresh touch
    pad.feed(frame((1, 118, 45)))
    #expect(pad.events.isEmpty)
}

@Test func aSecondFingerBeforeTheGestureBeginsStopsItBeingOne() {
    var pad = Pad()
    pad.feed(frame((1, 118, 20)))
    pad.feed(frame((1, 118, 21), (2, 60, 30)))
    pad.feed(frame((1, 118, 50)))
    #expect(pad.began.isEmpty && pad.cancelled.isEmpty)
}

@Test func aFingerThatIsOnlyHoveringIsNotATouch() {
    var pad = Pad()
    let hover = TrackpadFrame(touches: [TrackpadTouch(id: 1, x: 118 / width, y: 20 / height, isDown: false)], widthMM: width, heightMM: height)
    pad.feed(hover)
    pad.feed(frame((1, 118, 20)))
    #expect(pad.events == [.candidateStarted(.right)])                      // it counts from when it touches
}

// MARK: The strips

@Test func theStripsAreAsWideAsAskedAndStopShortOfTheCorners() {
    func edge(_ x: Double, _ y: Double, mm: Double = 9) -> TrackpadEdge? {
        TrackpadGestureEngine.edge(
            of: TrackpadTouch(id: 1, x: x / width, y: y / height), in: frame(), edgeMM: mm, activeEdges: allEdges)
    }
    func frame() -> TrackpadFrame { TrackpadFrame(touches: [], widthMM: width, heightMM: height) }
    #expect(edge(8, 37) == .left && edge(10, 37) == nil)
    #expect(edge(114, 37) == .right && edge(112, 37) == nil)
    #expect(edge(60, 70) == .top && edge(60, 64) == nil)
    #expect(edge(60, 4) == .bottom && edge(60, 10) == nil)
    #expect(edge(112, 37, mm: 12) == .right)                                // a wider strip
    #expect(edge(3, 8) == nil && edge(3, 66) == nil && edge(119, 8) == nil)  // the corners
}

@Test func theWidthAndTheEdgeBeingInUseAreReported() {
    var pad = Pad()
    #expect(pad.engine.edgeInUse == nil)
    pad.feed(frame((1, 118, 20)))
    #expect(pad.engine.edgeInUse == nil)                                     // only a candidate yet
    pad.feed(frame((1, 118, 30)))
    #expect(pad.engine.edgeInUse == .right)
    pad.feed(lifted)
    #expect(pad.engine.edgeInUse == nil)
}

// MARK: The settings

@Test func trackpadGesturesAreOnByDefaultWithTheEdgesDoingTheUsualThings() {
    let settings = Settings()
    #expect(settings.trackpadEnabled)
    #expect(settings.trackpadAction(for: .right) == .volume && settings.trackpadAction(for: .left) == .brightness)
    #expect(settings.trackpadAction(for: .top) == .seek && settings.trackpadAction(for: .bottom) == .off)
    #expect(settings.trackpadActiveEdges == [.right, .left, .top])
    #expect(!TrackpadEdge.allCases.contains { settings.trackpadIsReversed($0) })
    #expect(settings.trackpadEdgeMM == 9 && settings.trackpadSensitivity == 1)
}

@Test func theChosenActionsAndDirectionsAreSavedAndAnUnknownOneFallsBackToTheDefault() throws {
    var settings = Settings()
    settings.trackpadEnabled = false                                          // a person who switched them off keeps them off
    settings.trackpadActions = ["right": "brightness", "left": "volume", "bottom": "seek", "top": "nonsense"]
    settings.trackpadReversedEdges = ["left"]
    let data = try JSONEncoder().encode(settings)
    let back = try JSONDecoder().decode(Settings.self, from: data)
    #expect(back == settings && !back.trackpadEnabled)
    #expect(back.trackpadAction(for: .right) == .brightness && back.trackpadAction(for: .left) == .volume)
    #expect(back.trackpadAction(for: .bottom) == .seek)
    #expect(back.trackpadAction(for: .top) == .seek)                         // "nonsense" means the default for the top edge
    #expect(back.trackpadIsReversed(.left) && !back.trackpadIsReversed(.right))
}

@Test func anOldSettingsFileGetsTrackpadGesturesSwitchedOnAndValuesOutOfRangeArePulledIn() throws {
    let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"focusMinutes":40}"#.utf8))
    #expect(old.trackpadEnabled && old.focusMinutes == 40 && old.trackpadActiveEdges == [.right, .left, .top])
    let wild = try JSONDecoder().decode(Settings.self, from: Data(#"{"trackpadEdgeMM":500,"trackpadSensitivity":0}"#.utf8))
    #expect(wild.trackpadEdgeMM == 20 && wild.trackpadSensitivity == 0.4)
}
