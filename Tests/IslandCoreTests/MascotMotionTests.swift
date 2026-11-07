import Testing
import CoreGraphics
@testable import IslandCore

private let times = (0..<10_000).map { Double($0) * 0.1 }   // 1,000 seconds in 0.1 s steps

@Test func theDriftStaysWithinItsLimits() {
    for time in times {
        let offset = MascotMotion.offset(at: time, celebrating: false)
        #expect(abs(offset.width) <= 3.0001)
        #expect(abs(offset.height) <= 2.4001)
    }
}

@Test func theDriftReallyMovesInBothDirections() {
    let offsets = times.map { MascotMotion.offset(at: $0, celebrating: false) }
    #expect(offsets.map(\.width).min()! < -1)
    #expect(offsets.map(\.width).max()! > 1)
    #expect(offsets.map(\.height).min()! < -1)
    #expect(offsets.map(\.height).max()! > 1)
}

@Test func theDriftIsNeverStuckInOnePlace() {
    let a = MascotMotion.offset(at: 0, celebrating: false)
    let b = MascotMotion.offset(at: 1.3, celebrating: false)
    let c = MascotMotion.offset(at: 2.9, celebrating: false)
    #expect(a != b && b != c && a != c)
}

@Test func celebratingHopsHigherThanTheNormalDrift() {
    let hop = times.map { MascotMotion.offset(at: $0, celebrating: true).height }
    #expect(hop.map { abs($0) }.max()! > 2.4)
    #expect(hop.map { abs($0) }.max()! <= 5.0001)
    // A hop goes up (negative y is up in screen space), it never dips below the resting line by more than the drift.
    #expect(hop.min()! < -3)
}

@Test func timeBeforeTheStartOfTheEpochIsHandled() {
    let offset = MascotMotion.offset(at: -12345.6, celebrating: false)
    #expect(abs(offset.width) <= 3.0001 && abs(offset.height) <= 2.4001)
}

// The motion is handed to Core Animation as one closed loop, so the app itself does no work while it plays.

@Test func theDriftIsAClosedLoop() {
    let start = MascotMotion.offset(at: 0, celebrating: false)
    let end = MascotMotion.offset(at: MascotMotion.driftLoopSeconds, celebrating: false)
    #expect(abs(start.width - end.width) < 0.0001)
    #expect(abs(start.height - end.height) < 0.0001)
    // ...and repeats exactly one loop later.
    let a = MascotMotion.offset(at: 7.3, celebrating: false)
    let b = MascotMotion.offset(at: 7.3 + MascotMotion.driftLoopSeconds, celebrating: false)
    #expect(abs(a.width - b.width) < 0.0001 && abs(a.height - b.height) < 0.0001)
}

@Test func theHopIsAClosedLoopToo() {
    let a = MascotMotion.offset(at: 0.1, celebrating: true)
    let b = MascotMotion.offset(at: 0.1 + MascotMotion.hopLoopSeconds, celebrating: true)
    #expect(abs(a.width - b.width) < 0.0001 && abs(a.height - b.height) < 0.0001)
}

@Test func theKeyframesCoverOneFullLoopAndEndWhereTheyStarted() {
    for celebrating in [false, true] {
        let frames = MascotMotion.keyframes(celebrating: celebrating, count: 120)
        #expect(frames.count == 121)
        #expect(abs(frames.first!.width - frames.last!.width) < 0.0001)
        #expect(abs(frames.first!.height - frames.last!.height) < 0.0001)
    }
}

@Test func theKeyframesStayWithinTheLimits() {
    let drift = MascotMotion.keyframes(celebrating: false, count: 480)
    #expect(drift.allSatisfy { abs($0.width) <= 3.0001 && abs($0.height) <= 2.4001 })
    let hop = MascotMotion.keyframes(celebrating: true, count: 48)
    #expect(hop.allSatisfy { abs($0.height) <= 5.0001 })
}

@Test func theKeyframesAreSmoothEnoughForALinearPlayback() {
    // Between neighbouring keyframes the mascot moves well under a drawing unit, so straight lines between them look curved.
    let frames = MascotMotion.keyframes(celebrating: false, count: 480)
    var largest: CGFloat = 0
    for (a, b) in zip(frames, frames.dropFirst()) { largest = max(largest, hypot(b.width - a.width, b.height - a.height)) }
    #expect(largest < 0.35)
    let hop = MascotMotion.keyframes(celebrating: true, count: 48)
    var largestHop: CGFloat = 0
    for (a, b) in zip(hop, hop.dropFirst()) { largestHop = max(largestHop, hypot(b.width - a.width, b.height - a.height)) }
    #expect(largestHop < 0.9)
}

@Test func theLoopLengthDependsOnWhetherTheMascotIsHopping() {
    #expect(MascotMotion.loopSeconds(celebrating: false) == MascotMotion.driftLoopSeconds)
    #expect(MascotMotion.loopSeconds(celebrating: true) == MascotMotion.hopLoopSeconds)
}
