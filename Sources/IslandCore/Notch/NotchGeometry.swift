import CoreGraphics

/// Pure frame math for the island panel. All rects use AppKit's bottom-left origin.
public enum NotchGeometry {
    public static let maxWingWidth: CGFloat = 160
    /// The island while it announces an event: wide enough for a title, tall enough to clear the notch and show it.
    public static let alertSize = CGSize(width: 380, height: 104)
    static let fallbackPillSize = CGSize(width: 120, height: 32)

    /// The notch's rect, or nil when the screen has no notch (`safeAreaTop == 0`).
    public static func notchRect(
        screenFrame: CGRect, safeAreaTop: CGFloat, auxLeftWidth: CGFloat, auxRightWidth: CGFloat
    ) -> CGRect? {
        guard safeAreaTop > 0 else { return nil }
        let width = screenFrame.width - auxLeftWidth - auxRightWidth
        guard width > 0 else { return nil }
        return CGRect(
            x: screenFrame.minX + auxLeftWidth, y: screenFrame.maxY - safeAreaTop,
            width: width, height: safeAreaTop)
    }

    /// The notch (or a top-center pill when there is none), widened by wings of at most `maxWingWidth` per side.
    public static func collapsedFrame(
        notch: CGRect?, screenFrame: CGRect, leftWing: CGFloat, rightWing: CGFloat
    ) -> CGRect {
        let base = notch ?? fallbackPill(in: screenFrame)
        let left = clampedWing(leftWing)
        let right = clampedWing(rightWing)
        return CGRect(x: base.minX - left, y: base.minY, width: base.width + left + right, height: base.height)
    }

    /// An island of `size` centered on the notch (or screen), flush with the top edge and kept on screen.
    public static func expandedFrame(notch: CGRect?, screenFrame: CGRect, size: CGSize) -> CGRect {
        let width = min(size.width, screenFrame.width)
        let height = min(size.height, screenFrame.height)
        let centerX = notch?.midX ?? screenFrame.midX
        let x = min(max(centerX - width / 2, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// The banner for an event alert: centered on the notch (or screen), flush with the top edge and kept on screen.
    public static func alertFrame(notch: CGRect?, screenFrame: CGRect, size: CGSize) -> CGRect {
        expandedFrame(notch: notch, screenFrame: screenFrame, size: size)
    }

    private static func fallbackPill(in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - fallbackPillSize.width / 2,
            y: screenFrame.maxY - fallbackPillSize.height,
            width: fallbackPillSize.width, height: fallbackPillSize.height)
    }

    private static func clampedWing(_ width: CGFloat) -> CGFloat {
        min(max(width, 0), maxWingWidth)
    }
}
