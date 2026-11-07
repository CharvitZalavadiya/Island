import Testing
import Foundation
@testable import IslandCore

@Test func aFreeNameIsKeptAsIs() {
    let desired = URL(fileURLWithPath: "/tmp/a.png")
    #expect(OutputNamer.uniqueURL(for: desired, fileExists: { _ in false }) == desired)
}

@Test func aNumberIsAddedUntilTheNameIsFree() {
    let taken: Set<String> = ["/tmp/a.png"]
    #expect(OutputNamer.uniqueURL(for: URL(fileURLWithPath: "/tmp/a.png"), fileExists: { taken.contains($0.path) })
        == URL(fileURLWithPath: "/tmp/a 2.png"))

    let moreTaken: Set<String> = ["/tmp/a.png", "/tmp/a 2.png"]
    #expect(OutputNamer.uniqueURL(for: URL(fileURLWithPath: "/tmp/a.png"), fileExists: { moreTaken.contains($0.path) })
        == URL(fileURLWithPath: "/tmp/a 3.png"))
}

@Test func namesWithoutAnExtensionGetTheNumberAtTheEnd() {
    let taken: Set<String> = ["/tmp/notes"]
    #expect(OutputNamer.uniqueURL(for: URL(fileURLWithPath: "/tmp/notes"), fileExists: { taken.contains($0.path) })
        == URL(fileURLWithPath: "/tmp/notes 2"))
}

@Test func spacesAndUnicodeInNamesAreKept() {
    let taken: Set<String> = ["/tmp/Café Notes.zip"]
    #expect(OutputNamer.uniqueURL(for: URL(fileURLWithPath: "/tmp/Café Notes.zip"), fileExists: { taken.contains($0.path) })
        == URL(fileURLWithPath: "/tmp/Café Notes 2.zip"))
}

@Test func theDefaultCheckLooksAtTheRealFileSystem() throws {
    let directory = makeTempDirectory()
    let file = directory.appendingPathComponent("real.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)
    #expect(OutputNamer.uniqueURL(for: file) == directory.appendingPathComponent("real 2.txt"))
}
