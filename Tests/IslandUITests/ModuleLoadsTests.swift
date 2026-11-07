import Testing
@testable import IslandUI

@Test func uiModuleLoads() {
    #expect(String(describing: IslandAppDelegate.self) == "IslandAppDelegate")
}
