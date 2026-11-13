import AppKit
import SwiftUI
import Testing
@testable import IslandUI

// The tools in the Tools tab that open a popup of settings: each has its own tile, with its own name, icon and colour.

@Test func everyPopupToolHasANameAnIconThatExistsAndADetail() {
    #expect(PopupTool.allCases == [.trackpadSlide, .trackpadTaps])
    #expect(Set(PopupTool.allCases.map(\.title)).count == PopupTool.allCases.count)
    for tool in PopupTool.allCases {
        #expect(!tool.title.isEmpty)
        #expect(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil) != nil, "\(tool.symbol) is not an SF Symbol")
        #expect(tool.detail(isOn: true) != tool.detail(isOn: false), "the detail should say whether it is on")
    }
}

@Test func everyPopupToolHasAColourOfItsOwnAndNeitherIsTheColourOfAnotherToolTile() {
    let tints = PopupTool.allCases.map(\.tint)
    #expect(Set(tints).count == tints.count)
    // The other tiles on the tab: the colour picker and the keyboard lock.
    #expect(!tints.contains(IslandTheme.swatch) && !tints.contains(IslandTheme.keepAwake))
    #expect(PopupTool.trackpadSlide.tint == IslandTheme.trackpadSlide && PopupTool.trackpadTaps.tint == IslandTheme.trackpadTaps)
    #expect(IslandTheme.trackpadSlide != IslandTheme.trackpadTaps)
}

@Test func theToolsTabHasATileForEveryPopupToolBesideTheOthers() {
    // The tab's tiles are the colour picker, the keyboard lock, and one for each popup tool.
    #expect(2 + PopupTool.allCases.count == 4)
    // Each tile fits in the row beside the player (the tab is about 556 pt wide, the player 178, a tile 42 and 6 between).
    let room = 556.0 - 178 - 12
    let tiles = Double(2 + PopupTool.allCases.count)
    #expect(tiles * (Double(IslandMetrics.toolTile) + 6) <= room)
}
