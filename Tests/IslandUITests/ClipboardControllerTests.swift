import Testing
import Foundation
import IslandCore
@testable import IslandUI

/// Counts how often text recognition ran and answers with a fixed text.
private final class OCRStub: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var text: String
    init(_ text: String) { self.text = text }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func recognise() -> String { lock.lock(); count += 1; lock.unlock(); return text }
}

@MainActor
private struct Rig {
    let pasteboard = FakePasteboard()
    let controller: ClipboardController
    let imagesDirectory: URL
    let ocr: OCRStub

    init(limit: Int = 200, recognisedText: String = "") {
        let stub = OCRStub(recognisedText)
        ocr = stub
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-ui-tests-\(UUID().uuidString)", isDirectory: true)
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        let history = ClipboardHistory(
            store: FileStore(url: directory.appendingPathComponent("clip.json"), defaultValue: []), limit: limit)
        controller = ClipboardController(
            history: history, imagesDirectory: imagesDirectory, pasteboard: pasteboard, ocr: { _ in stub.recognise() })
        controller.start()
    }

    func copy(_ text: String) {
        pasteboard.copy(string: text, types: ["public.utf8-plain-text"])
        controller.poll()
    }
}

private func texts(_ entries: [ClipboardEntry]) -> [String] {
    entries.compactMap { if case .text(let value) = $0.content { value } else { nil } }
}

@Test @MainActor func copiesAppearNewestFirst() {
    let rig = Rig()
    rig.copy("one")
    rig.copy("two")
    #expect(texts(rig.controller.visible(query: "")) == ["two", "one"])
}

@Test @MainActor func pinnedEntriesAreListedFirst() {
    let rig = Rig()
    rig.copy("keep")
    rig.controller.togglePin(rig.controller.entries[0])
    rig.copy("later 1")
    rig.copy("later 2")
    #expect(texts(rig.controller.visible(query: "")) == ["keep", "later 2", "later 1"])
}

@Test @MainActor func searchNarrowsTheList() {
    let rig = Rig()
    rig.copy("alpha report")
    rig.copy("beta")
    #expect(texts(rig.controller.visible(query: "REPORT")) == ["alpha report"])
}

@Test @MainActor func clickingAnEntryCopiesItBackWithoutReRecordingOrReordering() {
    let rig = Rig()
    rig.copy("older")
    rig.copy("newer")
    let older = rig.controller.entries[1]
    rig.controller.copyBack(older)
    rig.controller.poll()

    #expect(rig.pasteboard.written == [.text("older")])
    #expect(texts(rig.controller.visible(query: "")) == ["newer", "older"])
}

@Test @MainActor func clearingDeletesIslandsSavedImageFiles() throws {
    let rig = Rig()
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    guard case .image(let fileName) = rig.controller.entries[0].content else {
        Issue.record("expected an image entry")
        return
    }
    let file = rig.imagesDirectory.appendingPathComponent(fileName)
    #expect(FileManager.default.fileExists(atPath: file.path))

    rig.controller.requestClearAll()
    rig.controller.requestClearAll()
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test @MainActor func imagesDroppedByTheLimitAreDeletedToo() throws {
    let rig = Rig(limit: 1)
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    guard case .image(let fileName) = rig.controller.entries[0].content else {
        Issue.record("expected an image entry")
        return
    }
    rig.copy("pushes the image out")
    #expect(!FileManager.default.fileExists(atPath: rig.imagesDirectory.appendingPathComponent(fileName).path))
}

@Test @MainActor func smartActionsComeFromTheEntryContent() {
    let rig = Rig()
    rig.copy("#FF8800")
    #expect(rig.controller.actions(for: rig.controller.entries[0]) == [.copyRGB("255, 136, 0")])
    rig.pasteboard.copy(string: "https://example.com", types: ["public.utf8-plain-text"])
    rig.controller.poll()
    #expect(rig.controller.actions(for: rig.controller.entries[0]) == [.openLink(URL(string: "https://example.com")!)])
    rig.copy("just words")
    #expect(rig.controller.actions(for: rig.controller.entries[0]).isEmpty)
}

// MARK: Deleting records

@Test @MainActor func deletingATextRecordRemovesOnlyThatRecord() {
    let rig = Rig()
    rig.copy("one")
    rig.copy("two")
    rig.controller.remove(rig.controller.entries[1])
    #expect(texts(rig.controller.visible(query: "")) == ["two"])
}

@Test @MainActor func deletingAnImageRecordDeletesItsSavedFile() {
    let rig = Rig()
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    guard case .image(let fileName) = rig.controller.entries[0].content else {
        Issue.record("expected an image entry")
        return
    }
    let file = rig.imagesDirectory.appendingPathComponent(fileName)
    #expect(FileManager.default.fileExists(atPath: file.path))
    rig.controller.remove(rig.controller.entries[0])
    #expect(rig.controller.entries.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test @MainActor func deletingAPinnedRecordWorks() {
    let rig = Rig()
    rig.copy("pinned")
    rig.controller.togglePin(rig.controller.entries[0])
    rig.controller.remove(rig.controller.entries[0])
    #expect(rig.controller.entries.isEmpty)
}

// MARK: Clear All, with a safety tap

@Test @MainActor func theFirstClearAllTapOnlyArmsIt() {
    let rig = Rig()
    rig.copy("one")
    rig.copy("two")
    rig.controller.requestClearAll()
    #expect(rig.controller.clearArmed)
    #expect(rig.controller.entries.count == 2)
}

@Test @MainActor func theSecondTapClearsEverythingIncludingPins() {
    let rig = Rig()
    rig.copy("pinned one")
    rig.controller.togglePin(rig.controller.entries[0])
    rig.copy("plain")
    rig.controller.requestClearAll()
    rig.controller.requestClearAll()
    #expect(rig.controller.entries.isEmpty)
    #expect(!rig.controller.clearArmed)
}

@Test @MainActor func aStrayFirstTapNeverDeletesAnything() {
    let rig = Rig()
    rig.copy("precious")
    rig.controller.togglePin(rig.controller.entries[0])
    rig.controller.requestClearAll()          // one stray click
    rig.controller.disarmClear()              // ...and the arming runs out
    #expect(rig.controller.entries.count == 1)
    rig.controller.requestClearAll()          // a later single tap only arms again
    #expect(rig.controller.entries.count == 1)
    #expect(rig.controller.clearArmed)
}

@Test @MainActor func clearAllOnAnEmptyHistoryDoesNotArm() {
    let rig = Rig()
    rig.controller.requestClearAll()
    #expect(!rig.controller.clearArmed)
}

// MARK: Scan text

/// Waits (without blocking) until the monitor's own background recognition has stored its text.
@MainActor
private func waitForRecognisedText(_ rig: Rig) async {
    for _ in 0..<100 where rig.controller.entries.first?.ocrText == nil {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@Test @MainActor func scanTextCopiesTheTextFoundInTheImage() async {
    let rig = Rig(recognisedText: "Total due 42")
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    await rig.controller.copyText(of: rig.controller.entries[0])
    #expect(rig.pasteboard.written == [.text("Total due 42")])
    #expect(rig.controller.entries[0].ocrText == "Total due 42")
    #expect(rig.controller.message?.contains("Copied") == true)
}

@Test @MainActor func scanTextUsesTextThatWasAlreadyRecognisedWithoutScanningAgain() async {
    let rig = Rig(recognisedText: "Already known")
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    await waitForRecognisedText(rig)
    let callsSoFar = rig.ocr.calls
    await rig.controller.copyText(of: rig.controller.entries[0])
    #expect(rig.ocr.calls == callsSoFar)
    #expect(rig.pasteboard.written == [.text("Already known")])
}

@Test @MainActor func scanTextOnAnImageWithNoTextSaysSoAndCopiesNothing() async {
    let rig = Rig(recognisedText: "")
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    await rig.controller.copyText(of: rig.controller.entries[0])
    #expect(rig.pasteboard.written.isEmpty)
    #expect(rig.controller.message == "No text found in this image.")
}

@Test @MainActor func copyingScannedTextIsNotRecordedAsANewEntry() async {
    let rig = Rig(recognisedText: "Scanned")
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    await rig.controller.copyText(of: rig.controller.entries[0])
    rig.controller.poll()
    #expect(rig.controller.entries.count == 1)
}

@Test @MainActor func scanTextOnAnEntryThatIsNotAnImageDoesNothing() async {
    let rig = Rig(recognisedText: "should not be used")
    rig.copy("plain text")
    await rig.controller.copyText(of: rig.controller.entries[0])
    #expect(rig.ocr.calls == 0)
    #expect(rig.pasteboard.written.isEmpty)
}

@Test @MainActor func scanTextWhenTheSavedImageIsGoneSaysSoInsteadOfCrashing() async throws {
    let rig = Rig(recognisedText: "")
    rig.pasteboard.copy(imagePNG: makePNG(), types: ["public.png"])
    rig.controller.poll()
    guard case .image(let fileName) = rig.controller.entries[0].content else {
        Issue.record("expected an image entry")
        return
    }
    try FileManager.default.removeItem(at: rig.imagesDirectory.appendingPathComponent(fileName))
    await rig.controller.copyText(of: rig.controller.entries[0])
    #expect(rig.controller.message == "The image file is no longer there.")
    #expect(rig.pasteboard.written.isEmpty)
}
