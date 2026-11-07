import AppKit
import SwiftUI

/// Makes a shelf tile draggable as a file, and only ever as a copy. A press that is released without turning into a
/// drag is a click (it selects the tile), which is also why this view covers the whole tile.
///
/// Island promises never to move a user's original file. SwiftUI's own `onDrag` leaves the allowed operations to the
/// system (Finder moves a file dropped on the same disk unless told otherwise), so the drag is started here with an
/// explicit "copy only" mask, which every receiver, Finder included, has to respect.
struct FileDragSource: NSViewRepresentable {
    static let allowedOperations: NSDragOperation = [.copy]

    /// Nil for a file that has vanished: the tile can still be clicked, but there is nothing to drag.
    let url: URL?
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView()
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.fileURL = url
        view.onClick = onClick
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var fileURL: URL?
    /// Called when a press is released without having become a drag.
    var onClick: (() -> Void)?
    private var mouseDownPoint: CGPoint?
    private var sessionStarted = false

    /// The file as a drag item, shown with its Finder icon.
    static func draggingItem(for url: URL, size: CGSize) -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(CGRect(origin: .zero, size: size), contents: NSWorkspace.shared.icon(forFile: url.path))
        return item
    }

    /// A press that wobbles by a few points is a click, not the start of a drag.
    static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > 4
    }

    // The island is a non-activating panel, so the first press must already count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginPress(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard shouldStartDrag(at: event.locationInWindow), let url = fileURL else { return }
        // The file's icon is square; stretching it over a wider tile would distort it.
        let side = min(bounds.width, bounds.height)
        beginDraggingSession(with: [Self.draggingItem(for: url, size: CGSize(width: side, height: side))], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        finishPress()
    }

    func beginPress(at point: CGPoint) {
        mouseDownPoint = point
        sessionStarted = false
    }

    /// True exactly once per press: when the pointer has moved far enough for it to be a drag, and there is a file.
    func shouldStartDrag(at point: CGPoint) -> Bool {
        guard !sessionStarted, fileURL != nil, let start = mouseDownPoint, Self.isDrag(from: start, to: point) else {
            return false
        }
        sessionStarted = true
        return true
    }

    /// The press is over: it was a click if it never turned into a drag.
    func finishPress() {
        defer { mouseDownPoint = nil }
        if mouseDownPoint != nil, !sessionStarted { onClick?() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        FileDragSource.allowedOperations
    }
}
