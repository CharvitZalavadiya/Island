import CoreGraphics

/// Pure frame math for the island panel. All rects use AppKit's bottom-left origin.
public enum NotchGeometry {
    public static let maxWingWidth: CGFloat = 160
    /// The island while it announces an event: wide enough for a title, tall enough to clear the notch and show it.
    public static let alertSize = CGSize(width: 380, height: 104)
    /// How wide a real notch is, give or take (they run from about 160 to 200 points): the look-alike is made this wide.
    public static let artificialNotchWidth: CGFloat = 190
    static let fallbackPillSize = CGSize(width: artificialNotchWidth, height: 24)

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

    /// The look-alike notch for a screen that has none (an Intel Mac, an older MacBook, an external display): about as wide as
    /// a real one, as tall as the menu bar (as a real notch is), centered on the screen and flush with its top edge. A
    /// menu bar that is hidden or reports nothing gives 24 points; nothing is made smaller than 22 or taller than 40.
    public static func artificialNotch(screenFrame: CGRect, menuBarHeight: CGFloat) -> CGRect {
        let height = menuBarHeight > 0 ? min(max(menuBarHeight, 22), 40) : 24
        return CGRect(
            x: screenFrame.midX - artificialNotchWidth / 2, y: screenFrame.maxY - height,
            width: artificialNotchWidth, height: height)
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

    /// The island in Max mode: `fraction` of the screen each way, never smaller than the usual island (`minimum`).
    public static func maxSize(screenFrame: CGRect, fraction: CGFloat = 0.8, minimum: CGSize) -> CGSize {
        CGSize(width: max(screenFrame.width * fraction, minimum.width), height: max(screenFrame.height * fraction, minimum.height))
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
