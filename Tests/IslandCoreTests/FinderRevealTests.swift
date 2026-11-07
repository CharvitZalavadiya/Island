import Testing
import Foundation
@testable import IslandCore

private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

@Test func aFileThatIsThereIsRevealedInFinder() {
    let file = URL(fileURLWithPath: "/Users/someone/Documents/report.pdf")
    let target = FinderReveal.target(resolved: file, lastKnownPath: file.path, fileExists: { _ in true }, home: home)
    #expect(target == .reveal(file))
}

@Test func aFileThatIsGoneOpensTheFolderItWasIn() {
    let file = URL(fileURLWithPath: "/Users/someone/Documents/report.pdf")
    let existing: Set<String> = ["/Users/someone/Documents"]
    let target = FinderReveal.target(resolved: nil, lastKnownPath: file.path, fileExists: { existing.contains($0) }, home: home)
    #expect(target == .openFolder(URL(fileURLWithPath: "/Users/someone/Documents")))
}

@Test func aResolvedPathThatNoLongerExistsFallsBackToItsFolder() {
    let file = URL(fileURLWithPath: "/Users/someone/Desktop/old.png")
    let existing: Set<String> = ["/Users/someone/Desktop"]
    let target = FinderReveal.target(resolved: file, lastKnownPath: nil, fileExists: { existing.contains($0) }, home: home)
    #expect(target == .openFolder(URL(fileURLWithPath: "/Users/someone/Desktop")))
}

@Test func whenTheFolderIsGoneTooFinderOpensTheHomeFolder() {
    let target = FinderReveal.target(
        resolved: nil, lastKnownPath: "/Volumes/Unplugged/Stuff/file.txt", fileExists: { _ in false }, home: home)
    #expect(target == .openFolder(home))
}

@Test func whenNothingIsKnownFinderOpensTheHomeFolder() {
    let target = FinderReveal.target(resolved: nil, lastKnownPath: nil, fileExists: { _ in false }, home: home)
    #expect(target == .openFolder(home))
}

@Test func aFolderOnTheShelfIsRevealedLikeAFile() {
    let folder = URL(fileURLWithPath: "/Users/someone/Projects/Island", isDirectory: true)
    let target = FinderReveal.target(resolved: folder, lastKnownPath: folder.path, fileExists: { _ in true }, home: home)
    #expect(target == .reveal(folder))
}
