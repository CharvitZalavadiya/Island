import Testing
import CoreGraphics
@testable import IslandCore

private let screen = CGSize(width: 1710, height: 1112)

private func window(
    _ owner: String, layer: Int, onScreen: Bool = true, x: CGFloat = 0, y: CGFloat = 0, w: CGFloat, h: CGFloat
) -> WindowInfo {
    WindowInfo(owner: owner, layer: layer, isOnScreen: onScreen, bounds: CGRect(x: x, y: y, width: w, height: h))
}

private let wallpaperLayer = -2_147_483_624
private let hiddenWallpaperLayer = -2_147_483_622

/// What the window list looked like on this Mac with Mission Control closed (captured in the spike).
private func makeQuietDesktop() -> [WindowInfo] {
    var windows: [WindowInfo] = []
    windows.append(window("WindowManager", layer: wallpaperLayer, w: 1710, h: 1112))  // wallpaper
    windows.append(window("WindowManager", layer: hiddenWallpaperLayer, onScreen: false, w: 1710, h: 1112))
    windows.append(window("Dock", layer: 20, w: 1710, h: 1112))
    windows.append(window("Brave Browser", layer: 0, w: 1710, h: 1012))
    windows.append(window("Island", layer: 25, x: 751, w: 208, h: 38))
    return windows
}

private let quietDesktop = makeQuietDesktop()

/// The same Mac with Mission Control open (captured in the spike).
private func makeMissionControlOpen() -> [WindowInfo] {
    var windows = makeQuietDesktop()
    windows.append(window("WindowManager", layer: 14, w: 1710, h: 250))  // the Spaces bar
    windows.append(window("WindowManager", layer: 15, x: 600, y: 60, w: 169, h: 130))
    windows.append(window("WindowManager", layer: 15, x: 800, y: 60, w: 170, h: 130))
    windows.append(window("WindowManager", layer: 19, onScreen: false, w: 1710, h: 1112))
    return windows
}

private let missionControlOpen = makeMissionControlOpen()

@Test func aQuietDesktopIsNotMissionControl() {
    #expect(!MissionControlDetector.isActive(windows: quietDesktop, screenSize: screen))
}

@Test func theSpacesBarMeansMissionControlIsOpen() {
    #expect(MissionControlDetector.isActive(windows: missionControlOpen, screenSize: screen))
}

@Test func aSpacesBarThatIsNotOnScreenDoesNotCount() {
    let hidden = quietDesktop + [window("WindowManager", layer: 14, onScreen: false, w: 1710, h: 250)]
    #expect(!MissionControlDetector.isActive(windows: hidden, screenSize: screen))
}

@Test func aNarrowTallWindowManagerStripIsNotMissionControl() {
    // Stage Manager keeps a thin strip of recent apps down the side.
    let stageManager = quietDesktop + [window("WindowManager", layer: 14, w: 120, h: 900)]
    #expect(!MissionControlDetector.isActive(windows: stageManager, screenSize: screen))
}

@Test func aWideWindowThatIsNotAtTheTopIsNotTheSpacesBar() {
    let lowered = quietDesktop + [window("WindowManager", layer: 14, y: 500, w: 1710, h: 250)]
    #expect(!MissionControlDetector.isActive(windows: lowered, screenSize: screen))
}

@Test func otherAppsAtTheSameLayerAreIgnored() {
    let imposter = quietDesktop + [window("SomeOtherApp", layer: 14, w: 1710, h: 250)]
    #expect(!MissionControlDetector.isActive(windows: imposter, screenSize: screen))
}

@Test func theThumbnailsAloneAtLayerFifteenDoNotCount() {
    let thumbnails = quietDesktop + [window("WindowManager", layer: 15, x: 600, y: 60, w: 169, h: 130)]
    #expect(!MissionControlDetector.isActive(windows: thumbnails, screenSize: screen))
}

@Test func noWindowsMeansNotActive() {
    #expect(!MissionControlDetector.isActive(windows: [], screenSize: screen))
}
