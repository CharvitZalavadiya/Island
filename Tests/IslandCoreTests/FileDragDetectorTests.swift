import Testing
import CoreGraphics
@testable import IslandCore

private let zone = CGRect(x: 600, y: 900, width: 500, height: 212)   // around a notch at the top of a screen
private let near = CGPoint(x: 850, y: 1000)
private let far = CGPoint(x: 850, y: 300)

private func poll(
    _ detector: inout FileDragDetector, held: Bool = true, count: Int, files: Bool = true, at pointer: CGPoint
) -> FileDragDetector.Result {
    detector.poll(buttonHeld: held, pasteboardChangeCount: count, pasteboardHasFiles: { files }, pointer: pointer, zone: zone)
}

@Test func aDragOfFilesNearTheNotchOpensTheShelf() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 5)
    #expect(poll(&detector, count: 6, at: far) == .nothing)
    #expect(poll(&detector, count: 6, at: near) == .nearNotch)
}

@Test func filesLeftOnTheDragPasteboardByAnOlderDragDoNotCount() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 5)
    // The pasteboard still holds files, but nothing was dragged since the button went down.
    #expect(poll(&detector, count: 5, files: true, at: near) == .nothing)
}

@Test func aDragOfSomethingThatIsNotFilesNeverCounts() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 5)
    #expect(poll(&detector, count: 6, files: false, at: near) == .nothing)
    #expect(!detector.isFileDrag)
}

@Test func theFilesQuestionIsAskedOnlyOncePerChange() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 5)
    var asked = 0
    for _ in 0..<10 {
        _ = detector.poll(buttonHeld: true, pasteboardChangeCount: 6, pasteboardHasFiles: { asked += 1; return false }, pointer: near, zone: zone)
    }
    #expect(asked == 1)
}

@Test func aFileDragFarFromTheNotchDoesNothingUntilItGetsNear() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 1)
    for _ in 0..<5 { #expect(poll(&detector, count: 2, at: far) == .nothing) }
    #expect(detector.isFileDrag)
    #expect(poll(&detector, count: 2, at: near) == .nearNotch)
}

@Test func letGoAfterAFileDragEndsIt() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 1)
    _ = poll(&detector, count: 2, at: near)
    #expect(poll(&detector, held: false, count: 2, at: near) == .ended)
    #expect(!detector.isFileDrag)
    #expect(poll(&detector, held: false, count: 2, at: near) == .nothing)
}

@Test func letGoAfterAnOrdinaryClickEndsNothing() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 1)
    #expect(poll(&detector, held: false, count: 1, at: near) == .nothing)
}

@Test func theNextPressStartsFresh() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 1)
    _ = poll(&detector, count: 2, at: near)
    _ = poll(&detector, held: false, count: 2, at: near)
    // A new press while the pasteboard is as it was: the old drag must not carry over.
    detector.buttonWentDown(pasteboardChangeCount: 2)
    #expect(poll(&detector, count: 2, at: near) == .nothing)
}

@Test func theEdgeOfTheZoneCountsAsInside() {
    var detector = FileDragDetector()
    detector.buttonWentDown(pasteboardChangeCount: 1)
    #expect(poll(&detector, count: 2, at: CGPoint(x: zone.minX, y: zone.minY)) == .nearNotch)
}
