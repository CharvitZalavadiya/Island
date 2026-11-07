import AppKit
import CoreGraphics
import IslandCore

/// The live Mission Control check. Island calls it only at the moment it is about to open (and on a short timer while it
/// is open), so nothing polls while the island is idle.
enum MissionControl {
    static func isActive() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let windows: [WindowInfo] = list.compactMap { entry in
            guard let owner = entry[kCGWindowOwnerName as String] as? String,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return nil }
            return WindowInfo(owner: owner, layer: layer, isOnScreen: true, bounds: bounds)
        }
        // The Spaces bar spans the whole width of its own display, so compare against the narrowest display.
        let narrowest = NSScreen.screens.map(\.frame.size).min { $0.width < $1.width }
        return MissionControlDetector.isActive(windows: windows, screenSize: narrowest ?? CGSize(width: 1440, height: 900))
    }
}
