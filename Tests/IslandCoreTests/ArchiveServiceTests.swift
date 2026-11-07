import Testing
import Foundation
@testable import IslandCore

private func makeNotesFolder(in directory: URL, name: String = "Café Notes") throws -> URL {
    let folder = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub dir"), withIntermediateDirectories: true)
    try "first".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "second ✓".write(to: folder.appendingPathComponent("sub dir/b é.txt"), atomically: true, encoding: .utf8)
    return folder
}

/// Every file under `folder` as relative path → contents.
private func snapshot(_ folder: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    let base = folder.resolvingSymlinksInPath().path
    let enumerator = try #require(FileManager.default.enumerator(at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey]))
    for case let url as URL in enumerator {
        guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
        let relative = String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))
        result[relative] = try String(contentsOf: url, encoding: .utf8)
    }
    return result
}

@Test func aFolderWithSpacesAndAccentsZipsNextToItself() throws {
    let directory = makeTempDirectory()
    let folder = try makeNotesFolder(in: directory)
    let archive = try ArchiveService.zip(folder)
    #expect(archive.lastPathComponent == "Café Notes.zip")
    #expect(archive.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
    #expect(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize! > 0)
}

@Test func aFileKeepsItsFullNameInFrontOfZip() throws {
    let directory = makeTempDirectory()
    let file = directory.appendingPathComponent("my report.txt")
    try "hello".write(to: file, atomically: true, encoding: .utf8)
    #expect(try ArchiveService.zip(file).lastPathComponent == "my report.txt.zip")
}

@Test func aZippedFileComesBackAsTheFileNotInsideAnEnclosingFolder() throws {
    let directory = makeTempDirectory()
    let file = directory.appendingPathComponent("my report.txt")
    try "hello".write(to: file, atomically: true, encoding: .utf8)
    let archive = try ArchiveService.zip(file)
    let extracted = try ArchiveService.unzip(archive)

    var isDirectory: ObjCBool = true
    #expect(FileManager.default.fileExists(atPath: extracted.path, isDirectory: &isDirectory))
    #expect(!isDirectory.boolValue)
    // The original is still there, so the extracted copy is numbered.
    #expect(extracted.lastPathComponent == "my report 2.txt")
    #expect(try String(contentsOf: extracted, encoding: .utf8) == "hello")
}

@Test func zippingTwiceNeverOverwritesTheFirstArchive() throws {
    let directory = makeTempDirectory()
    let folder = try makeNotesFolder(in: directory)
    let first = try ArchiveService.zip(folder)
    let firstBytes = try Data(contentsOf: first)
    let second = try ArchiveService.zip(folder)
    #expect(second.lastPathComponent == "Café Notes 2.zip")
    #expect(try Data(contentsOf: first) == firstBytes)
}

@Test func unzippingRebuildsTheSameFilesWithoutExtraNesting() throws {
    let directory = makeTempDirectory()
    let folder = try makeNotesFolder(in: directory)
    let original = try snapshot(folder)
    let archive = try ArchiveService.zip(folder)

    let extracted = try ArchiveService.unzip(archive)
    // The original folder is still there, so the result gets a number instead of replacing it.
    #expect(extracted.lastPathComponent == "Café Notes 2")
    #expect(try snapshot(extracted) == original)
    #expect(try snapshot(folder) == original)
}

@Test func unzippingTwiceKeepsBothResults() throws {
    let directory = makeTempDirectory()
    let archive = try ArchiveService.zip(try makeNotesFolder(in: directory))
    let first = try ArchiveService.unzip(archive)
    let second = try ArchiveService.unzip(archive)
    #expect(first != second)
    #expect(FileManager.default.fileExists(atPath: first.path))
    #expect(FileManager.default.fileExists(atPath: second.path))
}

@Test func anArchiveWithSeveralItemsAtItsRootExtractsIntoAFolderNamedAfterIt() throws {
    let directory = makeTempDirectory()
    let content = directory.appendingPathComponent("content", isDirectory: true)
    try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
    try "1".write(to: content.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "2".write(to: content.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    let archive = directory.appendingPathComponent("bundle.zip")
    let result = try ProcessCommandRunner().run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", content.path, archive.path])
    #expect(result.status == 0)

    let extracted = try ArchiveService.unzip(archive)
    #expect(extracted.lastPathComponent == "bundle")
    #expect(try snapshot(extracted) == ["a.txt": "1", "b.txt": "2"])
}

@Test func unzippingLeavesNoTemporaryFolderBehind() throws {
    let directory = makeTempDirectory()
    let archive = try ArchiveService.zip(try makeNotesFolder(in: directory))
    _ = try ArchiveService.unzip(archive)
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(!names.contains { $0.hasPrefix(".island-unzip") })
}

@Test func zippingSomethingThatDoesNotExistThrows() {
    let missing = makeTempDirectory().appendingPathComponent("ghost")
    #expect(throws: ArchiveError.self) { try ArchiveService.zip(missing) }
}

@Test func unzippingSomethingThatIsNotAnArchiveThrowsAndLeavesNothingBehind() throws {
    let directory = makeTempDirectory()
    let bad = directory.appendingPathComponent("bad.zip")
    try "not a zip".write(to: bad, atomically: true, encoding: .utf8)
    #expect(throws: ArchiveError.self) { try ArchiveService.unzip(bad) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["bad.zip"])
}

// MARK: Zipping several items into one archive

private func makeFile(_ name: String, in directory: URL, contents: String) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func twoFilesFromDifferentFoldersZipIntoArchiveZipWithBothAtTheRoot() throws {
    let base = makeTempDirectory()
    let a = try makeFile("a.txt", in: base.appendingPathComponent("one"), contents: "A")
    let b = try makeFile("b.txt", in: base.appendingPathComponent("two"), contents: "B")

    let archive = try ArchiveService.zip(urls: [a, b])
    #expect(archive.lastPathComponent == "Archive.zip")
    #expect(archive.deletingLastPathComponent().standardizedFileURL == a.deletingLastPathComponent().standardizedFileURL)

    let extracted = try ArchiveService.unzip(archive)
    #expect(extracted.lastPathComponent == "Archive")
    #expect(try snapshot(extracted) == ["a.txt": "A", "b.txt": "B"])
}

@Test func aFolderAndAFileKeepTheFolderNameInsideTheArchive() throws {
    let base = makeTempDirectory()
    let folder = try makeNotesFolder(in: base)
    let file = try makeFile("x.txt", in: base, contents: "X")
    let original = try snapshot(folder)

    let archive = try ArchiveService.zip(urls: [folder, file])
    let extracted = try ArchiveService.unzip(archive)
    var expected: [String: String] = ["x.txt": "X"]
    for (path, text) in original { expected["Café Notes/" + path] = text }
    #expect(try snapshot(extracted) == expected)
}

@Test func sameNamedFilesFromDifferentFoldersAreBothKept() throws {
    let base = makeTempDirectory()
    let first = try makeFile("same.txt", in: base.appendingPathComponent("one"), contents: "from one")
    let second = try makeFile("same.txt", in: base.appendingPathComponent("two"), contents: "from two")
    let archive = try ArchiveService.zip(urls: [first, second])
    let extracted = try ArchiveService.unzip(archive)
    #expect(try snapshot(extracted) == ["same.txt": "from one", "same 2.txt": "from two"])
}

@Test func theOriginalsAreNeverTouchedByAMultiZip() throws {
    let base = makeTempDirectory()
    let a = try makeFile("a.txt", in: base, contents: "A")
    let b = try makeFile("b.txt", in: base, contents: "B")
    _ = try ArchiveService.zip(urls: [a, b])
    #expect(try String(contentsOf: a, encoding: .utf8) == "A")
    #expect(try String(contentsOf: b, encoding: .utf8) == "B")
}

@Test func aSecondMultiZipIsNumberedAndNeverOverwritesTheFirst() throws {
    let base = makeTempDirectory()
    let a = try makeFile("a.txt", in: base, contents: "A")
    let b = try makeFile("b.txt", in: base, contents: "B")
    let first = try ArchiveService.zip(urls: [a, b])
    let firstBytes = try Data(contentsOf: first)
    let second = try ArchiveService.zip(urls: [a, b])
    #expect(second.lastPathComponent == "Archive 2.zip")
    #expect(try Data(contentsOf: first) == firstBytes)
}

@Test func noStagingFolderIsLeftBehindAfterSuccess() throws {
    let base = makeTempDirectory()
    let a = try makeFile("a.txt", in: base, contents: "A")
    let b = try makeFile("b.txt", in: base, contents: "B")
    _ = try ArchiveService.zip(urls: [a, b])
    let names = try FileManager.default.contentsOfDirectory(atPath: base.path)
    #expect(!names.contains { $0.hasPrefix(".island-zip") })
    #expect(Set(names) == ["a.txt", "b.txt", "Archive.zip"])
}

@Test func noStagingFolderIsLeftBehindAfterAFailure() throws {
    let base = makeTempDirectory()
    let readable = try makeFile("a.txt", in: base, contents: "A")
    let locked = try makeFile("locked.txt", in: base, contents: "secret")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

    #expect(throws: (any Error).self) { try ArchiveService.zip(urls: [readable, locked]) }
    let names = try FileManager.default.contentsOfDirectory(atPath: base.path)
    #expect(!names.contains { $0.hasPrefix(".island-zip") })
    #expect(!names.contains("Archive.zip"))
}

@Test func aMissingItemInAMultiZipThrowsBeforeAnythingIsWritten() throws {
    let base = makeTempDirectory()
    let a = try makeFile("a.txt", in: base, contents: "A")
    let ghost = base.appendingPathComponent("ghost.txt")
    #expect(throws: ArchiveError.self) { try ArchiveService.zip(urls: [a, ghost]) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: base.path) == ["a.txt"])
}

@Test func zippingNoItemsThrows() {
    #expect(throws: ArchiveError.self) { try ArchiveService.zip(urls: []) }
}
