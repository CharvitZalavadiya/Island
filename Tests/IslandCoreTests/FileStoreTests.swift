import Testing
import Foundation
@testable import IslandCore

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("island-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct Sample: Codable, Equatable {
    var name: String
    var count: Int
}

private let sampleDefault = Sample(name: "default", count: 0)

@Test func saveThenLoadRoundTrips() throws {
    let url = makeTempDirectory().appendingPathComponent("sample.json")
    let store = FileStore(url: url, defaultValue: sampleDefault)
    try store.save(Sample(name: "x", count: 3))
    #expect(store.load() == Sample(name: "x", count: 3))
}

@Test func missingFileReturnsDefault() {
    let url = makeTempDirectory().appendingPathComponent("missing.json")
    let store = FileStore(url: url, defaultValue: sampleDefault)
    #expect(store.load() == sampleDefault)
}

@Test func corruptFileReturnsDefaultAndKeepsBackup() throws {
    let url = makeTempDirectory().appendingPathComponent("sample.json")
    try "{not json".write(to: url, atomically: true, encoding: .utf8)
    let store = FileStore(url: url, defaultValue: sampleDefault)

    #expect(store.load() == sampleDefault)
    let backup = url.appendingPathExtension("corrupt")
    #expect(FileManager.default.fileExists(atPath: backup.path))
    #expect(try String(contentsOf: backup, encoding: .utf8) == "{not json")
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func saveCreatesMissingParentDirectories() throws {
    let url = makeTempDirectory().appendingPathComponent("a/b/sample.json")
    let store = FileStore(url: url, defaultValue: sampleDefault)
    try store.save(Sample(name: "deep", count: 1))
    #expect(store.load() == Sample(name: "deep", count: 1))
}

@Test func supportDirectoryCreatesIslandFolderUnderBase() {
    let base = makeTempDirectory()
    let dir = AppPaths.supportDirectory(base: base)
    #expect(dir.lastPathComponent == "Island")
    #expect(dir.deletingLastPathComponent().standardizedFileURL == base.standardizedFileURL)
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) && isDirectory.boolValue)
}
