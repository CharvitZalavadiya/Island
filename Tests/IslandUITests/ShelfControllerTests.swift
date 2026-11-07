import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import IslandCore
@testable import IslandUI

@MainActor
private final class FinderSpy: FinderOpening {
    private(set) var revealed: [URL] = []
    private(set) var openedFolders: [URL] = []
    func reveal(_ url: URL) { revealed.append(url) }
    func openFolder(_ url: URL) { openedFolders.append(url) }
}

@MainActor
private struct Rig {
    let model: IslandModel
    let controller: ShelfController
    let directory: URL
    let finder = FinderSpy()

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = SettingsStore(
            store: FileStore(url: directory.appendingPathComponent("settings.json"), defaultValue: Settings()))
        model = IslandModel(settings: settings)
        let store = ShelfStore(store: FileStore(url: directory.appendingPathComponent("shelf.json"), defaultValue: []))
        controller = ShelfController(store: store, model: model, finder: finder)
    }

    func makeFile(_ name: String, contents: String = "data") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func makePNG(_ name: String = "pic.png") throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0.6, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }
}

@Test @MainActor func droppedFilesAppearOnTheShelf() throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt"), try rig.makeFile("b.txt")])
    #expect(rig.controller.items.map(\.displayName) == ["b.txt", "a.txt"])
}

@Test @MainActor func droppedFoldersAreAccepted() throws {
    let rig = Rig()
    let folder = rig.directory.appendingPathComponent("A Folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    rig.controller.add(urls: [folder])
    #expect(rig.controller.items.map(\.displayName) == ["A Folder"])
}

@Test @MainActor func removingAnItemKeepsTheFile() throws {
    let rig = Rig()
    let file = try rig.makeFile("keep.txt")
    rig.controller.add(urls: [file])
    rig.controller.remove(rig.controller.items[0])
    #expect(rig.controller.items.isEmpty)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test @MainActor func convertingAddsTheResultToTheShelfAndKeepsTheOriginal() async throws {
    let rig = Rig()
    let png = try rig.makePNG()
    rig.controller.add(urls: [png])
    await rig.controller.convert(rig.controller.items[0], to: .jpeg)

    #expect(rig.controller.items.map(\.displayName) == ["pic.jpg", "pic.png"])
    #expect(FileManager.default.fileExists(atPath: png.path))
    #expect(rig.controller.message?.contains("pic.jpg") == true)
}

@Test @MainActor func convertingToTheSameFormatKeepsBothFiles() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makePNG()])
    await rig.controller.convert(rig.controller.items[0], to: .png)
    #expect(rig.controller.items.map(\.displayName) == ["pic 2.png", "pic.png"])
}

@Test @MainActor func aFileThatIsNotAnImageGivesAMessageInsteadOfACrash() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("bad.png", contents: "not an image")])
    await rig.controller.convert(rig.controller.items[0], to: .jpeg)
    #expect(rig.controller.message != nil)
    #expect(rig.controller.items.count == 1)
}

@Test @MainActor func zippingAddsTheArchiveAndUnzippingAddsTheResult() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("notes.txt", contents: "hello")])
    await rig.controller.zip(rig.controller.items[0])
    #expect(rig.controller.items.map(\.displayName) == ["notes.txt.zip", "notes.txt"])

    let archive = rig.controller.items[0]
    await rig.controller.unzip(archive)
    // The original notes.txt still exists, so the extracted copy is numbered.
    #expect(rig.controller.items.map(\.displayName) == ["notes 2.txt", "notes.txt.zip", "notes.txt"])
}

@Test @MainActor func actionsOnAFileThatVanishedGiveAMessage() async throws {
    let rig = Rig()
    let file = try rig.makeFile("gone.txt")
    rig.controller.add(urls: [file])
    try FileManager.default.removeItem(at: file)
    await rig.controller.zip(rig.controller.items[0])
    #expect(rig.controller.message != nil)
    #expect(rig.controller.items.count == 1)
    #expect(rig.controller.isMissing(rig.controller.items[0]))
}

@Test @MainActor func aNewScreenshotIsAddedAndFlagged() throws {
    let rig = Rig()
    let shot = try rig.makePNG("Screenshot 2026-10-31.png")
    rig.controller.handleScreenshot(shot)
    #expect(rig.controller.items[0].isScreenshot)
    #expect(rig.model.activities.isEmpty)   // nothing is shown beside the notch for a screenshot
}

// MARK: Selecting tiles

@Test @MainActor func clickingATileSelectsItAndClickingAgainDeselects() throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt")])
    let item = rig.controller.items[0]
    rig.controller.toggleSelection(item)
    #expect(rig.controller.selectedIDs == [item.id])
    #expect(rig.controller.selectedItems == [item])
    rig.controller.toggleSelection(item)
    #expect(rig.controller.selectedIDs.isEmpty)
}

@Test @MainActor func clearSelectionDeselectsEverything() throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt"), try rig.makeFile("b.txt")])
    rig.controller.items.forEach(rig.controller.toggleSelection)
    #expect(rig.controller.selectedIDs.count == 2)
    rig.controller.clearSelection()
    #expect(rig.controller.selectedIDs.isEmpty)
}

@Test @MainActor func selectingSeveralEnablesZip() throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt"), try rig.makeFile("b.txt")])
    #expect(rig.controller.actions == ShelfActions())
    rig.controller.toggleSelection(rig.controller.items[0])
    #expect(!rig.controller.actions.canZip)
    #expect(rig.controller.actions.canShowInFinder)
    rig.controller.toggleSelection(rig.controller.items[1])
    #expect(rig.controller.actions.canZip)
    #expect(!rig.controller.actions.canShowInFinder)
}

@Test @MainActor func missingItemsAreLeftOutOfTheActions() throws {
    let rig = Rig()
    let present = try rig.makeFile("here.txt")
    let gone = try rig.makeFile("gone.txt")
    rig.controller.add(urls: [present, gone])
    try FileManager.default.removeItem(at: gone)
    rig.controller.items.forEach(rig.controller.toggleSelection)

    // Only one of the two can still be used, so there is nothing to zip, but the file that is there can be sent.
    #expect(!rig.controller.actions.canZip)
    #expect(rig.controller.actions.canAirDrop)
    #expect(rig.controller.actions.canRemove)

    // A vanished file on its own can still be taken off the shelf and its folder opened, but not sent anywhere.
    rig.controller.clearSelection()
    rig.controller.toggleSelection(rig.controller.items.first { $0.displayName == "gone.txt" }!)
    #expect(!rig.controller.actions.canAirDrop)
    #expect(rig.controller.actions.canRemove)
    #expect(rig.controller.actions.canShowInFinder)
}

@Test @MainActor func selectionIsPrunedWhenItemsVanish() throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt"), try rig.makeFile("b.txt")])
    rig.controller.items.forEach(rig.controller.toggleSelection)
    let kept = rig.controller.items[0]
    rig.controller.remove(rig.controller.items[1])
    #expect(rig.controller.selectedIDs == [kept.id])
}

// MARK: Acting on the selection

@Test @MainActor func zipSelectedMakesOneArchiveAndSelectsNothingNew() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt", contents: "A"), try rig.makeFile("b.txt", contents: "B")])
    rig.controller.items.forEach(rig.controller.toggleSelection)
    let selectedBefore = rig.controller.selectedIDs

    await rig.controller.zipSelected()
    #expect(rig.controller.items.map(\.displayName) == ["Archive.zip", "b.txt", "a.txt"])
    #expect(rig.controller.selectedIDs == selectedBefore)
    #expect(rig.controller.message?.contains("Archive.zip") == true)
    #expect(FileManager.default.fileExists(atPath: rig.directory.appendingPathComponent("Archive.zip").path))
}

@Test @MainActor func zipSelectedWithASingleFileKeepsTheFilesOwnName() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("notes.txt")])
    rig.controller.toggleSelection(rig.controller.items[0])
    await rig.controller.zipSelected()
    #expect(rig.controller.items.map(\.displayName) == ["notes.txt.zip", "notes.txt"])
}

@Test @MainActor func zipSelectedWithNothingSelectedSaysSo() async {
    let rig = Rig()
    await rig.controller.zipSelected()
    #expect(rig.controller.message != nil)
    #expect(rig.controller.items.isEmpty)
}

@Test @MainActor func convertSelectedConvertsEveryImageAndSkipsOthers() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makePNG("a.png"), try rig.makePNG("b.png"), try rig.makeFile("notes.txt")])
    rig.controller.items.forEach(rig.controller.toggleSelection)

    await rig.controller.convertSelected(to: .jpeg)
    #expect(Set(rig.controller.items.map(\.displayName)) == ["a.png", "b.png", "notes.txt", "a.jpg", "b.jpg"])
    #expect(rig.controller.message?.contains("Skipped 1") == true)
    #expect(FileManager.default.fileExists(atPath: rig.directory.appendingPathComponent("a.png").path))
}

@Test @MainActor func convertSelectedLeavesFilesThatAlreadyAreThatFormat() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makePNG("a.png"), try rig.makeFile("b.jpg", contents: "already a jpeg")])
    rig.controller.items.forEach(rig.controller.toggleSelection)

    await rig.controller.convertSelected(to: .jpeg)
    #expect(Set(rig.controller.items.map(\.displayName)) == ["a.png", "b.jpg", "a.jpg"])
    #expect(rig.controller.message?.contains("Skipped 1") == true)
}

@Test @MainActor func convertSelectedNamesTheFilesItCouldNotConvert() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makePNG("good.png"), try rig.makeFile("bad.png", contents: "not an image")])
    rig.controller.items.forEach(rig.controller.toggleSelection)

    await rig.controller.convertSelected(to: .jpeg)
    #expect(rig.controller.items.map(\.displayName).contains("good.jpg"))
    #expect(rig.controller.message?.contains("good.jpg") == true)
    #expect(rig.controller.message?.contains("bad.png") == true)
}

@Test @MainActor func convertSelectedWithNothingConvertibleSaysSo() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("notes.txt")])
    rig.controller.toggleSelection(rig.controller.items[0])
    await rig.controller.convertSelected(to: .png)
    #expect(rig.controller.items.count == 1)
    #expect(rig.controller.message != nil)
}

@Test @MainActor func unzipSelectedExtractsTheSelectedArchive() async throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("notes.txt", contents: "hello")])
    await rig.controller.zip(rig.controller.items[0])
    let archive = rig.controller.items[0]
    rig.controller.toggleSelection(archive)
    #expect(rig.controller.actions.canUnzip)

    await rig.controller.unzipSelected()
    #expect(rig.controller.items.map(\.displayName) == ["notes 2.txt", "notes.txt.zip", "notes.txt"])
}

@Test @MainActor func removingSelectedKeepsTheFiles() throws {
    let rig = Rig()
    let a = try rig.makeFile("a.txt")
    let b = try rig.makeFile("b.txt")
    rig.controller.add(urls: [a, b])
    rig.controller.items.forEach(rig.controller.toggleSelection)

    rig.controller.removeSelected()
    #expect(rig.controller.items.isEmpty)
    #expect(rig.controller.selectedIDs.isEmpty)
    #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
}

@Test @MainActor func removingSelectedLeavesTheUnselectedItems() throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt"), try rig.makeFile("b.txt")])
    rig.controller.toggleSelection(rig.controller.items[0])   // b.txt
    rig.controller.removeSelected()
    #expect(rig.controller.items.map(\.displayName) == ["a.txt"])
}

// MARK: Show in Finder

@Test @MainActor func showInFinderRevealsTheSelectedFile() throws {
    let rig = Rig()
    let file = try rig.makeFile("report.txt")
    rig.controller.add(urls: [file])
    rig.controller.toggleSelection(rig.controller.items[0])

    rig.controller.showSelectedInFinder()
    #expect(rig.finder.revealed.map { $0.resolvingSymlinksInPath().path } == [file.resolvingSymlinksInPath().path])
    #expect(rig.finder.openedFolders.isEmpty)
}

@Test @MainActor func showInFinderForAVanishedFileOpensTheFolderItWasIn() throws {
    let rig = Rig()
    let file = try rig.makeFile("gone.txt")
    rig.controller.add(urls: [file])
    try FileManager.default.removeItem(at: file)
    rig.controller.toggleSelection(rig.controller.items[0])

    rig.controller.showSelectedInFinder()
    #expect(rig.finder.revealed.isEmpty)
    #expect(rig.finder.openedFolders.map { $0.resolvingSymlinksInPath().path } == [rig.directory.resolvingSymlinksInPath().path])
}

@Test @MainActor func showInFinderDoesNothingForSeveralFilesOrNone() throws {
    let rig = Rig()
    rig.controller.add(urls: [try rig.makeFile("a.txt"), try rig.makeFile("b.txt")])
    rig.controller.showSelectedInFinder()
    rig.controller.items.forEach(rig.controller.toggleSelection)
    rig.controller.showSelectedInFinder()
    #expect(rig.finder.revealed.isEmpty && rig.finder.openedFolders.isEmpty)
}
