import Testing
import Foundation
import IslandCore
@testable import IslandUI

@MainActor
private func makeModel() -> IslandModel {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("island-ui-tests-\(UUID().uuidString)/settings.json")
    return IslandModel(settings: SettingsStore(store: FileStore(url: url, defaultValue: Settings())))
}

@Test @MainActor func modelStartsCollapsedOnTheFocusTabWithNothingLive() {
    let model = makeModel()
    #expect(model.mode == .collapsed)
    #expect(model.selectedTab == .focus)
    #expect(model.activities.isEmpty)
}

@Test @MainActor func setActivityAddsAndRemoves() {
    let model = makeModel()
    model.setActivity(.pomodoro, active: true)
    model.setActivity(.keepAwake, active: true)
    #expect(model.activities == [.pomodoro, .keepAwake])
    model.setActivity(.pomodoro, active: false)
    #expect(model.activities == [.keepAwake])
    model.setActivity(.pomodoro, active: false)
    #expect(model.activities == [.keepAwake])
}

@Test @MainActor func tabsAreInTheDefaultOrderWithCalendarLast() {
    #expect(makeModel().orderedTabs == [.focus, .awake, .clipboard, .shelf, .stats, .camera, .calendar, .tasks, .base64, .tools, .github, .teams, .browser])
}

@Test @MainActor func theModelFollowsTheSavedOrder() {
    let model = makeModel()
    model.settings.update { $0.tabOrder = ["camera", "focus"] }
    #expect(model.orderedTabs == [.camera, .focus, .awake, .clipboard, .shelf, .stats, .calendar, .tasks, .base64, .tools, .github, .teams, .browser])
}

@Test @MainActor func aSavedOrderWithMissingTabsStillShowsEveryTab() {
    let model = makeModel()
    model.settings.update { $0.tabOrder = ["stats"] }
    #expect(model.orderedTabs.count == IslandTab.allCases.count)
    #expect(Set(model.orderedTabs) == Set(IslandTab.allCases))
    #expect(model.orderedTabs.first == .stats)
}

@Test @MainActor func aSavedOrderWithUnknownTabsIgnoresThem() {
    let model = makeModel()
    model.settings.update { $0.tabOrder = ["apps", "shelf", "nonsense"] }
    #expect(model.orderedTabs.first == .shelf)
    #expect(model.orderedTabs.count == IslandTab.allCases.count)
}

@Test @MainActor func swipingFollowsTheSavedOrderAndClampsAtTheEnds() {
    let model = makeModel()
    model.settings.update { $0.tabOrder = ["stats", "focus", "calendar"] }
    model.selectedTab = .stats
    model.selectAdjacentTab(1)
    #expect(model.selectedTab == .focus)
    model.selectAdjacentTab(1)
    #expect(model.selectedTab == .calendar)
    model.selectAdjacentTab(-5)
    #expect(model.selectedTab == .stats)
    model.selectAdjacentTab(-1)
    #expect(model.selectedTab == .stats)
}

@Test @MainActor func swipingFromAnUnknownPositionLandsOnTheFirstTab() {
    let model = makeModel()
    model.settings.update { $0.tabOrder = ["camera"] }
    model.selectedTab = .focus
    model.selectAdjacentTab(0)
    #expect(model.orderedTabs.contains(model.selectedTab))
}

@Test func nothingLiveMeansNoWings() {
    let widths = WingLayout.widths(for: [])
    #expect(widths.left == 0)
    #expect(widths.right == 0)
}

@Test func pomodoroUsesBothWings() {
    let widths = WingLayout.widths(for: [.pomodoro])
    #expect(widths.left == 34 + WingLayout.edgeInset)
    #expect(widths.right == 48 + WingLayout.edgeInset)
}

@Test func wingsWidenWithEachActivityOnTheirSide() {
    let widths = WingLayout.widths(for: [.keepAwake, .focusMode])
    let expectedRight: CGFloat = 56 + 18 + WingLayout.edgeInset
    #expect(widths.left == 34 + WingLayout.edgeInset)       // the cup in its ring
    #expect(widths.right == expectedRight)
}

@Test func mediaTakesTheIconSlotOnTheLeftAndTheEqualizerSlotOnTheRight() {
    let widths = WingLayout.widths(for: [.media])
    #expect(widths.left == 34 + WingLayout.edgeInset)       // the app icon in its ring
    #expect(widths.right == 30 + WingLayout.edgeInset)      // the equalizer bars
}

@Test func everyActivityAtOnceStillFitsTheWingCap() {
    let widths = WingLayout.widths(for: Set(LiveActivityKind.allCases))
    let expectedLeft: CGFloat = 34 + 34 + 34 + WingLayout.edgeInset
    let expectedRight: CGFloat = 48 + 56 + 18 + 30 + WingLayout.edgeInset
    #expect(widths.left == expectedLeft)
    #expect(widths.right == expectedRight)
    #expect(widths.left <= NotchGeometry.maxWingWidth)
    #expect(widths.right <= NotchGeometry.maxWingWidth)
}

@Test @MainActor func theIslandStartsUnpinnedAndThePinToggles() {
    let model = makeModel()
    #expect(!model.isPinned)
    model.isPinned.toggle()
    #expect(model.isPinned)
    model.isPinned.toggle()
    #expect(!model.isPinned)
}

// MARK: Dragging files toward the island

@Test @MainActor func draggingFilesToACollapsedIslandSelectsTheShelf() {
    let model = makeModel()
    model.selectedTab = .stats
    model.fileDragEntered()
    #expect(model.selectedTab == .shelf)
}

@Test @MainActor func draggingFilesToAnOpenIslandSwitchesToTheShelfWhateverTabItWasOn() {
    let model = makeModel()
    for tab in IslandTab.allCases {
        model.mode = .expanded
        model.selectedTab = tab
        model.fileDragEntered()
        #expect(model.selectedTab == .shelf, "from \(tab)")
    }
}

@Test @MainActor func draggingFilesToAPinnedIslandSwitchesToTheShelfAndKeepsItPinned() {
    let model = makeModel()
    model.isPinned = true
    model.mode = .expanded
    model.selectedTab = .camera
    model.fileDragEntered()
    #expect(model.selectedTab == .shelf)
    #expect(model.isPinned)
}

// MARK: The wings follow what is live, not whether the island is open

@Test @MainActor func collapsingTheIslandKeepsItsLiveActivitiesSoTheWingsStayDuringMissionControl() {
    let model = makeModel()
    model.setActivity(.pomodoro, active: true)
    model.setActivity(.keepAwake, active: true)
    model.mode = .expanded
    model.mode = .collapsed     // what Mission Control does to an open island
    #expect(model.activities == [.pomodoro, .keepAwake])
}

// MARK: Event alerts

@Test @MainActor func showAndDismissAlert() {
    let model = makeModel()
    #expect(model.alert == nil)
    let alert = EventAlert(eventID: "e1", title: "Design review", start: Date(timeIntervalSince1970: 5_000), colorHex: 0xFF8800)
    model.showAlert(alert)
    #expect(model.alert == alert)
    model.dismissAlert()
    #expect(model.alert == nil)
}

@Test @MainActor func aNewAlertReplacesTheOldOne() {
    let model = makeModel()
    model.showAlert(EventAlert(eventID: "a", title: "A", start: Date(timeIntervalSince1970: 1), colorHex: nil))
    let second = EventAlert(eventID: "b", title: "B", start: Date(timeIntervalSince1970: 2), colorHex: nil)
    model.showAlert(second)
    #expect(model.alert == second)
}

@Test @MainActor func dismissingWithNoAlertIsHarmlessAndLeavesTheActivitiesAlone() {
    let model = makeModel()
    model.setActivity(.pomodoro, active: true)
    model.dismissAlert()
    #expect(model.alert == nil)
    #expect(model.activities == [.pomodoro])
}
