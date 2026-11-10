import Testing
@testable import IslandCore

private let all = ["focus", "clipboard", "shelf", "stats", "camera", "calendar"]

@Test func anEmptySavedOrderGivesTheDefaultOrder() {
    #expect(TabOrder.normalized(saved: [], all: all) == all)
}

@Test func savedIdsComeFirstInTheirOrderAndMissingOnesFollowInTheDefaultOrder() {
    #expect(TabOrder.normalized(saved: ["camera", "focus"], all: all)
        == ["camera", "focus", "clipboard", "shelf", "stats", "calendar"])
}

@Test func unknownAndDuplicateIdsAreDropped() {
    #expect(TabOrder.normalized(saved: ["stats", "apps", "stats", "focus", ""], all: all)
        == ["stats", "focus", "clipboard", "shelf", "camera", "calendar"])
}

@Test func aFullSavedOrderIsKeptAsIs() {
    let reversed = Array(all.reversed())
    #expect(TabOrder.normalized(saved: reversed, all: all) == reversed)
}

@Test func movingShiftsOneTabAndClampsAtTheEnds() {
    #expect(TabOrder.moved(all, id: "stats", by: -1) == ["focus", "clipboard", "stats", "shelf", "camera", "calendar"])
    #expect(TabOrder.moved(all, id: "stats", by: 1) == ["focus", "clipboard", "shelf", "camera", "stats", "calendar"])
    #expect(TabOrder.moved(all, id: "focus", by: -1) == all)
    #expect(TabOrder.moved(all, id: "calendar", by: 1) == all)
    #expect(TabOrder.moved(all, id: "focus", by: 99).last == "focus")
}

@Test func movingAnUnknownIdChangesNothing() {
    #expect(TabOrder.moved(all, id: "apps", by: 1) == all)
}

// MARK: Dragging a row onto another

@Test func draggingARowDownOntoAnotherPutsItInThatRowsPlace() {
    #expect(TabOrder.moved(all, id: "focus", to: "stats") == ["clipboard", "shelf", "stats", "focus", "camera", "calendar"])
    #expect(TabOrder.moved(all, id: "focus", to: "calendar").last == "focus")
}

@Test func draggingARowUpOntoAnotherPutsItInThatRowsPlace() {
    #expect(TabOrder.moved(all, id: "calendar", to: "shelf") == ["focus", "clipboard", "calendar", "shelf", "stats", "camera"])
    #expect(TabOrder.moved(all, id: "stats", to: "focus").first == "stats")
}

@Test func draggingARowOntoItselfOrOntoSomethingUnknownChangesNothing() {
    #expect(TabOrder.moved(all, id: "stats", to: "stats") == all)
    #expect(TabOrder.moved(all, id: "stats", to: "apps") == all)
    #expect(TabOrder.moved(all, id: "apps", to: "stats") == all)
}

@Test func draggingOneRowOverAnotherAndBackLeavesTheOrderAsItWas() {
    let there = TabOrder.moved(all, id: "focus", to: "stats")
    #expect(TabOrder.moved(there, id: "focus", to: "clipboard") == all)
}

// MARK: Switching tabs off

@Test func noTabIsSwitchedOffByDefault() {
    #expect(TabOrder.shown(all, hidden: []) == all)
}

@Test func switchedOffTabsAreLeftOutAndTheRestKeepTheirOrder() {
    #expect(TabOrder.shown(all, hidden: ["shelf", "focus"]) == ["clipboard", "stats", "camera", "calendar"])
    let reordered = ["calendar", "focus", "stats", "shelf", "camera", "clipboard"]
    #expect(TabOrder.shown(reordered, hidden: ["stats"]) == ["calendar", "focus", "shelf", "camera", "clipboard"])
}

@Test func unknownIdsInTheSwitchedOffListAreIgnored() {
    #expect(TabOrder.shown(all, hidden: ["apps", "", "stats"]) == ["focus", "clipboard", "shelf", "camera", "calendar"])
}

@Test func ifEveryTabWereSwitchedOffAllAreShownSoTheIslandIsNeverEmpty() {
    #expect(TabOrder.shown(all, hidden: all) == all)
    #expect(TabOrder.shown(all, hidden: all + ["apps"]) == all)
}

@Test func switchingATabOffAddsItAndSwitchingItOnTakesItOut() {
    var hidden = TabOrder.settingShown(false, id: "stats", hidden: [], all: all)
    #expect(hidden == ["stats"])
    hidden = TabOrder.settingShown(false, id: "focus", hidden: hidden, all: all)
    #expect(hidden == ["focus", "stats"])                 // always in the default order, whatever order they were switched off in
    hidden = TabOrder.settingShown(true, id: "stats", hidden: hidden, all: all)
    #expect(hidden == ["focus"])
    hidden = TabOrder.settingShown(true, id: "focus", hidden: hidden, all: all)
    #expect(hidden.isEmpty)
}

@Test func switchingOffATabThatIsAlreadyOffOrOnOneThatIsAlreadyOnChangesNothing() {
    #expect(TabOrder.settingShown(false, id: "stats", hidden: ["stats"], all: all) == ["stats"])
    #expect(TabOrder.settingShown(true, id: "stats", hidden: [], all: all).isEmpty)
}

@Test func theLastTabThatIsOnCannotBeSwitchedOff() {
    let allButCalendar = ["focus", "clipboard", "shelf", "stats", "camera"]
    #expect(TabOrder.settingShown(false, id: "calendar", hidden: allButCalendar, all: all) == allButCalendar)
    // With two on, one can still go.
    #expect(TabOrder.settingShown(false, id: "camera", hidden: ["focus", "clipboard", "shelf", "stats"], all: all)
        == ["focus", "clipboard", "shelf", "stats", "camera"])
}

@Test func anUnknownIdOrAnOldListWithUnknownIdsIsTidiedUp() {
    #expect(TabOrder.settingShown(false, id: "apps", hidden: ["stats"], all: all) == ["stats"])
    #expect(TabOrder.settingShown(false, id: "focus", hidden: ["apps", "stats", "stats"], all: all) == ["focus", "stats"])
}

