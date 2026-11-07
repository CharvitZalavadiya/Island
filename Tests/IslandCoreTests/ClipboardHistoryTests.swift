import Testing
import Foundation
@testable import IslandCore

private func makeHistory(limit: Int = 200, at url: URL? = nil, clock: FakeClock = FakeClock()) -> (ClipboardHistory, URL) {
    let file = url ?? makeTempDirectory().appendingPathComponent("clipboard.json")
    let history = ClipboardHistory(store: FileStore(url: file, defaultValue: []), limit: limit, now: { clock.now })
    return (history, file)
}

private func texts(_ history: ClipboardHistory) -> [String] {
    history.entries.compactMap { if case .text(let value) = $0.content { value } else { nil } }
}

@Test func newestEntryComesFirst() {
    let (history, _) = makeHistory()
    history.add(.text("one"))
    history.add(.text("two"))
    #expect(texts(history) == ["two", "one"])
}

@Test func copyingTheSameContentAgainMovesItToTheTopInsteadOfDuplicating() {
    let (history, _) = makeHistory()
    history.add(.text("A"))
    history.add(.text("B"))
    history.add(.text("A"))
    #expect(texts(history) == ["A", "B"])
}

@Test func aRecopiedEntryKeepsItsPinAndOCR() {
    let (history, _) = makeHistory()
    history.add(.text("A"))
    let id = history.entries[0].id
    history.togglePin(id)
    history.setOCR(id, text: "words")
    history.add(.text("B"))
    history.add(.text("A"))
    #expect(history.entries[0].id == id)
    #expect(history.entries[0].pinned)
    #expect(history.entries[0].ocrText == "words")
}

@Test func theLimitDropsTheOldestUnpinnedButNeverAPinnedEntry() {
    let (history, _) = makeHistory(limit: 3)
    history.add(.text("1"))
    history.togglePin(history.entries[0].id)
    history.add(.text("2"))
    history.add(.text("3"))
    history.add(.text("4"))
    #expect(texts(history) == ["4", "3", "1"])
}

@Test func aFullyPinnedHistoryStillAcceptsNewCopies() {
    let (history, _) = makeHistory(limit: 2)
    history.add(.text("1"))
    history.togglePin(history.entries[0].id)
    history.add(.text("2"))
    history.togglePin(history.entries[0].id)
    history.add(.text("3"))
    #expect(texts(history) == ["3", "2", "1"])
}

@Test func removeDeletesOneEntryAndReportsIt() {
    let (history, _) = makeHistory()
    var removed: [ClipboardEntry] = []
    history.onRemove = { removed += $0 }
    history.add(.text("one"))
    history.add(.text("two"))
    let victim = history.entries[1]   // "one"
    history.remove(victim.id)
    #expect(texts(history) == ["two"])
    #expect(removed == [victim])
}

@Test func removeOfAnUnknownIdIsIgnored() {
    let (history, _) = makeHistory()
    var removed: [ClipboardEntry] = []
    history.onRemove = { removed += $0 }
    history.add(.text("one"))
    history.remove(UUID())
    #expect(texts(history) == ["one"])
    #expect(removed.isEmpty)
}

@Test func removingAPinnedEntryWorksToo() {
    let (history, _) = makeHistory()
    history.add(.text("pinned"))
    history.togglePin(history.entries[0].id)
    history.remove(history.entries[0].id)
    #expect(history.entries.isEmpty)
}

@Test func clearAllRemovesEverythingIncludingPins() {
    let (history, _) = makeHistory()
    var removed: [ClipboardEntry] = []
    history.onRemove = { removed += $0 }
    history.add(.text("keep?"))
    history.togglePin(history.entries[0].id)
    history.add(.text("drop 1"))
    history.add(.text("drop 2"))
    history.clearAll()
    #expect(history.entries.isEmpty)
    #expect(removed.count == 3)
}

@Test func clearAllOnAnEmptyHistoryReportsNothing() {
    let (history, _) = makeHistory()
    var calls = 0
    history.onRemove = { _ in calls += 1 }
    history.clearAll()
    #expect(calls == 0)
}

@Test func removalsAreRememberedAcrossARestart() {
    let (first, file) = makeHistory()
    first.add(.text("gone"))
    first.add(.text("stays"))
    first.remove(first.entries[1].id)
    let (second, _) = makeHistory(at: file)
    #expect(texts(second) == ["stays"])
}

@Test func entriesRemovedByTheLimitOrByClearingAreReported() {
    let (history, _) = makeHistory(limit: 2)
    var removed: [ClipboardEntry] = []
    history.onRemove = { removed += $0 }
    history.add(.image(fileName: "a.png"))
    history.add(.text("b"))
    history.add(.text("c"))
    #expect(removed.map(\.content) == [.image(fileName: "a.png")])
    history.clearAll()
    #expect(removed.count == 3)
}

@Test func togglePinFlipsAndUnknownIdsAreIgnored() {
    let (history, _) = makeHistory()
    history.add(.text("x"))
    let id = history.entries[0].id
    history.togglePin(id)
    #expect(history.entries[0].pinned)
    history.togglePin(id)
    #expect(!history.entries[0].pinned)
    history.togglePin(UUID())
    history.setOCR(UUID(), text: "nothing")
    #expect(history.entries.count == 1)
}

@Test func searchMatchesTextLinksFileNamesAndOCRTextCaseInsensitively() {
    let (history, _) = makeHistory()
    history.add(.text("Quarterly REPORT draft"))
    history.add(.link(URL(string: "https://example.com/Pricing")!))
    history.add(.files([URL(fileURLWithPath: "/tmp/Invoice-42.pdf")]))
    history.add(.image(fileName: "shot.png"))
    history.setOCR(history.entries[0].id, text: "Total due: 1,250 EUR")

    #expect(history.search("report").count == 1)
    #expect(history.search("PRICING").count == 1)
    #expect(history.search("invoice-42").count == 1)
    #expect(history.search("1,250").map(\.id) == [history.entries[0].id])
    #expect(history.search("nothing like this").isEmpty)
}

@Test func anEmptySearchReturnsEverything() {
    let (history, _) = makeHistory()
    history.add(.text("a"))
    history.add(.text("b"))
    #expect(history.search("").count == 2)
    #expect(history.search("   ").count == 2)
}

@Test func historyPinsAndOCRSurviveAReload() {
    let (first, file) = makeHistory()
    first.add(.text("persisted"))
    let id = first.entries[0].id
    first.togglePin(id)
    first.setOCR(id, text: "ocr words")

    let (second, _) = makeHistory(at: file)
    #expect(texts(second) == ["persisted"])
    #expect(second.entries[0].pinned)
    #expect(second.entries[0].ocrText == "ocr words")
}
