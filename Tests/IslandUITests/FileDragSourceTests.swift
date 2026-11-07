import Testing
import AppKit
@testable import IslandUI

@Test @MainActor func dragsOutOfTheShelfOnlyEverCopy() {
    // Island promises never to move a user's original file, so the drag only offers "copy" to whoever receives it.
    #expect(FileDragSource.allowedOperations == [.copy])
}

@Test @MainActor func theDraggedItemIsTheFileItself() {
    let url = URL(fileURLWithPath: "/tmp/report.pdf")
    let item = DragSourceView.draggingItem(for: url, size: CGSize(width: 60, height: 60))
    #expect((item.item as? NSURL) as URL? == url)
    #expect(item.draggingFrame.size == CGSize(width: 60, height: 60))
}

@Test @MainActor func aSmallWobbleIsNotADragButARealMoveIs() {
    #expect(!DragSourceView.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 12)))
    #expect(DragSourceView.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 20)))
}

// MARK: Clicks (a press that never turns into a drag)

@Test @MainActor func aReleaseWithoutMovingCountsAsAClick() {
    let view = DragSourceView()
    var clicks = 0
    view.onClick = { clicks += 1 }
    view.beginPress(at: CGPoint(x: 10, y: 10))
    view.finishPress()
    #expect(clicks == 1)
}

@Test @MainActor func aSmallWobbleBeforeTheReleaseStillCountsAsAClick() {
    let view = DragSourceView()
    view.fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
    var clicks = 0
    view.onClick = { clicks += 1 }
    view.beginPress(at: CGPoint(x: 10, y: 10))
    #expect(!view.shouldStartDrag(at: CGPoint(x: 11, y: 12)))
    view.finishPress()
    #expect(clicks == 1)
}

@Test @MainActor func aPressThatBecomesADragIsNotAClickAndStartsOnlyOneDrag() {
    let view = DragSourceView()
    view.fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
    var clicks = 0
    view.onClick = { clicks += 1 }
    view.beginPress(at: CGPoint(x: 10, y: 10))
    #expect(view.shouldStartDrag(at: CGPoint(x: 10, y: 30)))
    #expect(!view.shouldStartDrag(at: CGPoint(x: 10, y: 60)))
    view.finishPress()
    #expect(clicks == 0)
}

@Test @MainActor func aTileWithoutAFileCanBeClickedButNeverDragged() {
    // A file that has vanished still needs to be selectable so it can be taken off the shelf.
    let view = DragSourceView()
    var clicks = 0
    view.onClick = { clicks += 1 }
    view.beginPress(at: CGPoint(x: 10, y: 10))
    #expect(!view.shouldStartDrag(at: CGPoint(x: 10, y: 60)))
    view.finishPress()
    #expect(clicks == 1)
}

@Test @MainActor func aReleaseWithoutAPressDoesNothing() {
    let view = DragSourceView()
    var clicks = 0
    view.onClick = { clicks += 1 }
    view.finishPress()
    #expect(clicks == 0)
}

@Test @MainActor func twoPressesGiveTwoClicks() {
    let view = DragSourceView()
    var clicks = 0
    view.onClick = { clicks += 1 }
    for _ in 0..<2 {
        view.beginPress(at: .zero)
        view.finishPress()
    }
    #expect(clicks == 2)
}
