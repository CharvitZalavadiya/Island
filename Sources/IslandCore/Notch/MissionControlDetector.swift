import CoreGraphics

/// The few facts about a screen window that Mission Control detection needs.
public struct WindowInfo: Equatable, Sendable {
    public var owner: String
    public var layer: Int
    public var isOnScreen: Bool
    public var bounds: CGRect

    public init(owner: String, layer: Int, isOnScreen: Bool, bounds: CGRect) {
        self.owner = owner
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.bounds = bounds
    }
}

/// Tells from the list of windows whether Mission Control is on screen.
///
/// macOS offers no public "Mission Control is open" signal. A spike on macOS 27 found that while it is open there is an
/// on-screen window owned by `WindowManager` at layer 14 along the top of the screen, as wide as the screen: the Spaces
/// bar. None exists otherwise. Stage Manager's strip is also drawn by `WindowManager` but is narrow and at the side, so
/// the width and top-edge checks keep it from counting.
public enum MissionControlDetector {
    public static func isActive(windows: [WindowInfo], screenSize: CGSize) -> Bool {
        windows.contains { window in
            window.owner == "WindowManager"
                && window.isOnScreen
                && window.layer == 14
                && window.bounds.width >= screenSize.width * 0.6
                && window.bounds.minY <= 1
        }
    }
}
