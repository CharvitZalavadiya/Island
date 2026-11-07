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
