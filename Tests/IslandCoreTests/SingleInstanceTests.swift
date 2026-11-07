import Testing
@testable import IslandCore

@Test func aLoneProcessHasNoOtherInstance() {
    #expect(SingleInstance.otherProcessID(among: [], current: 100) == nil)
    #expect(SingleInstance.otherProcessID(among: [100], current: 100) == nil)
}

@Test func anotherProcessIsFoundWhetherOrNotTheListIncludesThisOne() {
    #expect(SingleInstance.otherProcessID(among: [100, 200], current: 100) == 200)
    #expect(SingleInstance.otherProcessID(among: [200], current: 100) == 200)
}
