import Testing
import Foundation
@testable import IslandCore

private func makeStore(at url: URL? = nil) -> (ShelfStore, URL) {
    let file = url ?? makeTempDirectory().appendingPathComponent("shelf.json")
    return (ShelfStore(store: FileStore(url: file, defaultValue: [])), file)
}

private func makeFile(_ name: String, in directory: URL, contents: String = "data") throws -> URL {
    let url = directory.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func available(_ resolved: ResolvedShelfItem) -> URL? {
    if case .available(let url) = resolved { url.resolvingSymlinksInPath() } else { nil }
}

@Test func addedFilesAppearNewestFirstWithTheirNames() throws {
    let directory = makeTempDirectory()
    let (store, _) = makeStore()
    store.add(urls: [try makeFile("one.txt", in: directory), try makeFile("two.txt", in: directory)])
    #expect(store.items.map(\.displayName) == ["two.txt", "one.txt"])
    #expect(store.items.allSatisfy { !$0.isScreenshot })
}

@Test func screenshotsAreFlagged() throws {
    let directory = makeTempDirectory()
    let (store, _) = makeStore()
    store.add(urls: [try makeFile("Screenshot.png", in: directory)], isScreenshot: true)
    #expect(store.items[0].isScreenshot)
}

@Test func addingTheSameFileTwiceKeepsOneItem() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("same.txt", in: directory)
    let (store, _) = makeStore()
    store.add(urls: [file])
    store.add(urls: [file])
    #expect(store.items.count == 1)
}

@Test func filesThatDoNotExistAreSkipped() {
    let (store, _) = makeStore()
    store.add(urls: [URL(fileURLWithPath: "/definitely/not/here.txt")])
    #expect(store.items.isEmpty)
}

@Test func removingAnItemNeverDeletesTheFile() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("keep.txt", in: directory)
    let (store, _) = makeStore()
    store.add(urls: [file])
    store.remove(store.items[0].id)
    #expect(store.items.isEmpty)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func anItemResolvesToItsFile() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("here.txt", in: directory)
    let (store, _) = makeStore()
    store.add(urls: [file])
    #expect(available(store.resolve(store.items[0])) == file.resolvingSymlinksInPath())
}

@Test func aDeletedOriginalResolvesAsMissingButStaysOnTheShelf() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("gone.txt", in: directory)
    let (store, _) = makeStore()
    store.add(urls: [file])
    try FileManager.default.removeItem(at: file)
    #expect(store.resolve(store.items[0]) == .missing)
    #expect(store.items.count == 1)
}

@Test func aMovedFileIsStillFoundThroughItsBookmark() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("moving.txt", in: directory)
    let (store, _) = makeStore()
    store.add(urls: [file])
    let destination = directory.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: destination)
    #expect(available(store.resolve(store.items[0])) == destination.resolvingSymlinksInPath())
}

@Test func aFileInTheTrashCountsAsMissing() {
    #expect(ShelfStore.isTrashed(URL(fileURLWithPath: "/Users/someone/.Trash/old.txt")))
    #expect(ShelfStore.isTrashed(URL(fileURLWithPath: "/Volumes/Disk/.Trashes/501/old.txt")))
    #expect(!ShelfStore.isTrashed(URL(fileURLWithPath: "/Users/someone/Documents/old.txt")))
}

@Test func theShelfSurvivesARestart() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("persist.txt", in: directory)
    let (first, storeFile) = makeStore()
    first.add(urls: [file], isScreenshot: true)

    let (second, _) = makeStore(at: storeFile)
    #expect(second.items.map(\.displayName) == ["persist.txt"])
    #expect(second.items[0].isScreenshot)
    #expect(available(second.resolve(second.items[0])) == file.resolvingSymlinksInPath())
}

// MARK: The last known path (so Show in Finder can still open the right folder if the file is gone)

@Test func theLastKnownPathIsRecordedWhenAFileIsAdded() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("here.txt", in: directory)
    let (store, _) = makeStore()
    store.add(urls: [file])
    #expect(store.items[0].lastKnownPath == file.path)
}

@Test func aMovedFileUpdatesItsLastKnownPathWhenResolved() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("moving.txt", in: directory)
    let (store, storeFile) = makeStore()
    store.add(urls: [file])
    let destination = directory.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: destination)
    _ = store.resolve(store.items[0])
    #expect(store.items[0].lastKnownPath?.hasSuffix("renamed.txt") == true)
    // ...and it is saved.
    let (reloaded, _) = makeStore(at: storeFile)
    #expect(reloaded.items[0].lastKnownPath?.hasSuffix("renamed.txt") == true)
}

@Test func aDeletedFileKeepsItsLastKnownPath() throws {
    let directory = makeTempDirectory()
    let file = try makeFile("gone.txt", in: directory)
    let (store, _) = makeStore()
    store.add(urls: [file])
    try FileManager.default.removeItem(at: file)
    #expect(store.resolve(store.items[0]) == .missing)
    #expect(store.items[0].lastKnownPath == file.path)
}

@Test func aShelfFileWrittenBeforeThePathExistedStillLoads() throws {
    let url = makeTempDirectory().appendingPathComponent("shelf.json")
    let old = """
        [{"id":"6F1D2C3B-0000-4000-8000-000000000001","bookmark":"AAAA","displayName":"old.txt","addedAt":0,"isScreenshot":false}]
        """
    try old.write(to: url, atomically: true, encoding: .utf8)
    let store = ShelfStore(store: FileStore(url: url, defaultValue: []))
    #expect(store.items.map(\.displayName) == ["old.txt"])
    #expect(store.items[0].lastKnownPath == nil)
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
}
