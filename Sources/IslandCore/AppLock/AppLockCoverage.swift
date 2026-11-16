import CoreGraphics

/// Which screens the lock covers, and which one carries the box to type the password in.
public struct AppLockCoverPlan: Equatable, Sendable {
    public var covered: [CGRect]
    public var card: CGRect
}

public enum AppLockCoverage {
    /// An app's window that only reaches a little over the edge of a screen does not count as being on that screen.
    public static let minimumOverlap: CGFloat = 40

    /// Covers the screens the locked app's windows are on, so what is open on the person's other screens stays usable. When it
    /// cannot tell (no window was found, or none reaches a screen) it covers EVERY screen: when unsure, it hides more, not less.
    /// The box goes on the screen with most of the windows, or else on the first screen (the main one).
    public static func plan(windows: [CGRect], screens: [CGRect]) -> AppLockCoverPlan? {
        guard let first = screens.first else { return nil }
        var overlaps: [(screen: CGRect, area: CGFloat)] = []
        for screen in screens {
            var area: CGFloat = 0
            for window in windows {
                let shared = screen.intersection(window)
                if !shared.isNull, shared.width >= minimumOverlap, shared.height >= minimumOverlap { area += shared.width * shared.height }
            }
            if area > 0 { overlaps.append((screen, area)) }
        }
        guard let biggest = overlaps.max(by: { $0.area < $1.area }) else { return AppLockCoverPlan(covered: screens, card: first) }
        return AppLockCoverPlan(covered: overlaps.map(\.screen), card: biggest.screen)
    }
}
