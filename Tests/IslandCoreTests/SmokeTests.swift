import Testing
@testable import IslandCore

@Test func versionIsSemver() {
    #expect(islandVersion.split(separator: ".").count == 3)
}
