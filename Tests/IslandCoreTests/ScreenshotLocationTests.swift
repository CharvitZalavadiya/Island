import Testing
import Foundation
@testable import IslandCore

private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

@Test func noSettingMeansTheDesktop() {
    #expect(ScreenshotLocation.resolve(defaultsValue: nil, home: home) == home.appendingPathComponent("Desktop"))
    #expect(ScreenshotLocation.resolve(defaultsValue: "", home: home) == home.appendingPathComponent("Desktop"))
    #expect(ScreenshotLocation.resolve(defaultsValue: "   ", home: home) == home.appendingPathComponent("Desktop"))
}

@Test func aLeadingTildeIsExpanded() {
    #expect(ScreenshotLocation.resolve(defaultsValue: "~/Pictures/Shots", home: home).path == "/Users/someone/Pictures/Shots")
    #expect(ScreenshotLocation.resolve(defaultsValue: "~", home: home).path == "/Users/someone")
}

@Test func anAbsolutePathIsUsedAsIs() {
    #expect(ScreenshotLocation.resolve(defaultsValue: "/Volumes/Work/Shots", home: home).path == "/Volumes/Work/Shots")
}

@Test func aRelativePathIsTakenFromHome() {
    #expect(ScreenshotLocation.resolve(defaultsValue: "Screens", home: home).path == "/Users/someone/Screens")
}
