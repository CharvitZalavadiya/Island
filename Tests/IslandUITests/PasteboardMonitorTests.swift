import Testing
import AppKit
import IslandCore
@testable import IslandUI

/// A pretend pasteboard the tests can fill, so nothing touches the real clipboard.
final class FakePasteboard: PasteboardAccess {
    private(set) var changeCount = 1
    private(set) var snapshotCalls = 0
    private(set) var written: [ClipboardContent] = []
    private var current = PasteboardSnapshot()

    func copy(string: String? = nil, imagePNG: Data? = nil, files: [URL] = [], types: [String] = []) {
        changeCount += 1
        current = PasteboardSnapshot(types: types, string: string, imagePNGData: imagePNG, fileURLs: files)
    }

    func snapshot() -> PasteboardSnapshot {
        snapshotCalls += 1
        return current
    }

    func write(_ content: ClipboardContent, imagesDirectory: URL) -> Int {
        written.append(content)
        changeCount += 1
        return changeCount
    }
}

func makePNG() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
struct MonitorRig {
    let pasteboard = FakePasteboard()
    let history: ClipboardHistory
    let imagesDirectory: URL
    let monitor: PasteboardMonitor

    init(ocr: @escaping @Sendable (CGImage) async -> String = { _ in "" }) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-ui-tests-\(UUID().uuidString)", isDirectory: true)
        history = ClipboardHistory(store: FileStore(url: directory.appendingPathComponent("clip.json"), defaultValue: []))
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        monitor = PasteboardMonitor(history: history, imagesDirectory: imagesDirectory, pasteboard: pasteboard, ocr: ocr)
        monitor.start()
    }
}

@Test @MainActor func copiedTextIsRecorded() {
    let rig = MonitorRig()
    rig.pasteboard.copy(string: "hello", types: ["public.utf8-plain-text"])
    rig.monitor.poll()
    #expect(rig.history.entries.map(\.content) == [.text("hello")])
}

@Test @MainActor func aCopiedWebAddressIsRecordedAsALink() {
    let rig = MonitorRig()
    rig.pasteboard.copy(string: "https://example.com/a", types: ["public.utf8-plain-text"])
    rig.monitor.poll()
    #expect(rig.history.entries.map(\.content) == [.link(URL(string: "https://example.com/a")!)])
}

@Test @MainActor func secretCopiesAreNeverRecorded() {
    let rig = MonitorRig()
    rig.pasteboard.copy(string: "hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
    rig.monitor.poll()
    #expect(rig.history.entries.isEmpty)
}

@Test @MainActor func blankCopiesAreNotRecorded() {
    let rig = MonitorRig()
    rig.pasteboard.copy(string: "   ", types: ["public.utf8-plain-text"])
    rig.monitor.poll()
    #expect(rig.history.entries.isEmpty)
}

@Test @MainActor func copiedFilesWinOverTheirNames() {
    let rig = MonitorRig()
    let file = URL(fileURLWithPath: "/tmp/report.pdf")
    rig.pasteboard.copy(string: "report.pdf", files: [file], types: ["public.file-url", "public.utf8-plain-text"])
    rig.monitor.poll()
    #expect(rig.history.entries.map(\.content) == [.files([file])])
}

@Test @MainActor func aCopiedImageIsSavedAsAPNGInIslandsOwnFolderAndItsTextIsRecognised() async throws {
    let rig = MonitorRig(ocr: { _ in "Total 42" })
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.monitor.markCurrentAsSeen()   // process() is called directly, so the poll timer must not record the same copy again
    let ocrTask = try #require(rig.monitor.process(rig.pasteboard.snapshot()))
    await ocrTask.value

    guard case .image(let fileName) = rig.history.entries[0].content else {
        Issue.record("expected an image entry")
        return
    }
    #expect(fileName.hasSuffix(".png"))
    #expect(FileManager.default.fileExists(atPath: rig.imagesDirectory.appendingPathComponent(fileName).path))
    #expect(rig.history.entries[0].ocrText == "Total 42")
}

@Test @MainActor func recognisedEmptyTextIsNotStored() async throws {
    let rig = MonitorRig(ocr: { _ in "" })
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.monitor.markCurrentAsSeen()   // process() is called directly, so the poll timer must not record the same copy again
    let ocrTask = try #require(rig.monitor.process(rig.pasteboard.snapshot()))
    await ocrTask.value
    #expect(rig.history.entries[0].ocrText == nil)
}

@Test @MainActor func textWinsOverAnImageThatComesWithIt() {
    let rig = MonitorRig()
    rig.pasteboard.copy(string: "caption", imagePNG: makePNG(), types: ["public.utf8-plain-text", "public.png"])
    rig.monitor.poll()
    #expect(rig.history.entries.map(\.content) == [.text("caption")])
}

@Test @MainActor func anUnchangedPasteboardIsNotReadAgain() {
    let rig = MonitorRig()
    rig.pasteboard.copy(string: "once", types: ["public.utf8-plain-text"])
    rig.monitor.poll()
    let readsAfterFirstPoll = rig.pasteboard.snapshotCalls
    rig.monitor.poll()
    rig.monitor.poll()
    #expect(rig.pasteboard.snapshotCalls == readsAfterFirstPoll)
    #expect(rig.history.entries.count == 1)
}

@Test @MainActor func whateverWasOnTheClipboardWhenIslandStartedIsNotRecorded() {
    let pasteboard = FakePasteboard()
    pasteboard.copy(string: "already there", types: ["public.utf8-plain-text"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-ui-tests-\(UUID().uuidString)")
    let history = ClipboardHistory(store: FileStore(url: directory.appendingPathComponent("c.json"), defaultValue: []))
    let monitor = PasteboardMonitor(
        history: history, imagesDirectory: directory, pasteboard: pasteboard, ocr: { _ in "" })
    monitor.start()
    monitor.poll()
    #expect(history.entries.isEmpty)
}

@Test @MainActor func aChangeIslandMadeItselfCanBeMarkedAsSeen() {
    let rig = MonitorRig()
    _ = rig.pasteboard.write(.text("copied back"), imagesDirectory: rig.imagesDirectory)
    rig.monitor.markCurrentAsSeen()
    rig.monitor.poll()
    #expect(rig.history.entries.isEmpty)
}

@Test @MainActor func theChangeHandlerFiresWhenSomethingIsRecorded() {
    let rig = MonitorRig()
    var changes = 0
    rig.monitor.onChange = { changes += 1 }
    rig.pasteboard.copy(string: "x", types: ["public.utf8-plain-text"])
    rig.monitor.poll()
    #expect(changes == 1)
}
