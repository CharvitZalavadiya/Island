import CoreGraphics

/// Decides whether files are being dragged towards the notch, from facts the app reads while a mouse button is held.
///
/// A drag of files is recognised the way drop-zone apps do it: the system's drag pasteboard has changed since the button
/// went down, and now holds file URLs. (The drag pasteboard keeps the files of an older drag, so what it holds cannot
/// be looked at on its own.)
public struct FileDragDetector {
    public enum Result: Equatable {
        case nothing
        /// Files are being dragged and the pointer is within reach of the notch: open the Shelf.
        case nearNotch
        /// The button came up after a drag of files.
        case ended
    }

    private var changeCountAtMouseDown = 0
    private var lastCheckedChangeCount = -1
    public private(set) var isFileDrag = false

    public init() {}

    public mutating func buttonWentDown(pasteboardChangeCount: Int) {
        changeCountAtMouseDown = pasteboardChangeCount
        lastCheckedChangeCount = -1
        isFileDrag = false
    }

    /// Called every few hundredths of a second while a button is held, and once more when it has come up.
    /// `pasteboardHasFiles` is only asked when the pasteboard has changed since the button went down, and only once per
    /// change.
    public mutating func poll(
        buttonHeld: Bool, pasteboardChangeCount: Int, pasteboardHasFiles: () -> Bool, pointer: CGPoint, zone: CGRect
    ) -> Result {
        guard buttonHeld else {
            let wasFileDrag = isFileDrag
            isFileDrag = false
            return wasFileDrag ? .ended : .nothing
        }
        if !isFileDrag {
            guard pasteboardChangeCount != changeCountAtMouseDown, pasteboardChangeCount != lastCheckedChangeCount else {
                return .nothing
            }
            lastCheckedChangeCount = pasteboardChangeCount
            guard pasteboardHasFiles() else { return .nothing }
            isFileDrag = true
        }
        return zone.contains(pointer) ? .nearNotch : .nothing
    }
}
