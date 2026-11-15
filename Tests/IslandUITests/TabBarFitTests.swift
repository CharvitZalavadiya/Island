import AppKit
import Foundation
import SwiftUI
import Testing
import IslandCore
@testable import IslandUI

// The tab bar has to fit the usual island with every tab on and all of its buttons, now that Focus mode has one too.

@MainActor
private func makeModel() -> IslandModel {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("island-ui-tests-\(UUID().uuidString)/settings.json")
    return IslandModel(settings: SettingsStore(store: FileStore(url: url, defaultValue: Settings())))
}

/// The width the tab bar has inside the usual open island: the island's width less its side padding (18 and the shape's ear).
private let availableWidth = IslandMetrics.expandedSize.width - 2 * (18 + NotchShape.expanded.top)

@MainActor
private func naturalWidth(of model: IslandModel) -> CGFloat {
    NSHostingView(rootView: TabBar(model: model)).fittingSize.width
}

@Test @MainActor func theTabBarWithEveryTabAndEveryButtonFitsTheUsualIsland() {
    let model = makeModel()
    #expect(model.orderedTabs.count == IslandTab.allCases.count)
    let width = naturalWidth(of: model)
    #expect(width > 400)                                                  // it measured the real bar, not an empty one
    #expect(width <= availableWidth, "needs \(width) pt, has \(availableWidth) pt")
}

@Test @MainActor func inFocusModeTheBarLosesMaxAndPinSoItIsNarrower() {
    let model = makeModel()
    let usual = naturalWidth(of: model)
    model.isFocusView = true
    let focus = naturalWidth(of: model)
    #expect(focus < usual - 40)
}

@Test @MainActor func theFocusCardHoldsItsContentAtTheCardSize() {
    let size = CGSize(width: 900, height: 500)
    let host = NSHostingView(rootView: FocusCard(size: size) { Color.clear })
    #expect(host.fittingSize == size)
}
