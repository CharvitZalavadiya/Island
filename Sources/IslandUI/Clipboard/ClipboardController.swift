import AppKit
import ImageIO
import Observation
import IslandCore

/// The clipboard feature: owns the history and the monitor, and offers what the tab needs.
@Observable
@MainActor
final class ClipboardController {
    private(set) var entries: [ClipboardEntry]
    /// The entry that was just copied back, highlighted briefly in the list.
    private(set) var flashedID: UUID?
    /// True after the first tap on "Clear All": the next tap really clears. It wears off after a few seconds.
    private(set) var clearArmed = false
    /// The outcome of the last scan, shown under the list.
    private(set) var message: String?
    let imagesDirectory: URL

    @ObservationIgnored private let history: ClipboardHistory
    @ObservationIgnored private let monitor: PasteboardMonitor
    @ObservationIgnored private let pasteboard: PasteboardAccess
    @ObservationIgnored private let ocr: @Sendable (CGImage) async -> String
    /// What "Scan text" uses when an image has not been read yet: the quick, less careful reading, so a click is
    /// answered at once. (New images are read carefully in the background when they are copied.)
    @ObservationIgnored private let quickOCR: @Sendable (CGImage) async -> String
    @ObservationIgnored private var flashTimer: Timer?
    @ObservationIgnored private var armTimer: Timer?
    @ObservationIgnored private var messageTimer: Timer?

    init(
        history: ClipboardHistory, imagesDirectory: URL,
        pasteboard: PasteboardAccess = SystemPasteboard(),
        ocr: @escaping @Sendable (CGImage) async -> String,
        quickOCR: (@Sendable (CGImage) async -> String)? = nil
    ) {
        self.history = history
        self.imagesDirectory = imagesDirectory
        self.pasteboard = pasteboard
        self.ocr = ocr
        self.quickOCR = quickOCR ?? ocr
        self.entries = history.entries
        self.monitor = PasteboardMonitor(
            history: history, imagesDirectory: imagesDirectory, pasteboard: pasteboard, ocr: ocr, quickOCR: quickOCR)

        // Island's saved copies of images go away with their history entries.
        history.onRemove = { removed in
            for entry in removed {
                if case .image(let fileName) = entry.content {
                    try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(fileName))
                }
            }
        }
        monitor.onChange = { [weak self] in self?.refresh() }
    }

    func start() {
        monitor.start()
    }

    /// Checks the pasteboard now (the monitor's timer does this twice a second).
    func poll() {
        monitor.poll()
    }

    /// Pinned entries first, then the rest, newest first within each, narrowed by `query`.
    func visible(query: String) -> [ClipboardEntry] {
        _ = entries  // reading this makes views update when the history changes
        let results = history.search(query)
        return results.filter(\.pinned) + results.filter { !$0.pinned }
    }

    /// Puts the entry back on the clipboard. It does not paste, and the monitor does not record it again.
    func copyBack(_ entry: ClipboardEntry) {
        _ = pasteboard.write(entry.content, imagesDirectory: imagesDirectory)
        monitor.markCurrentAsSeen()
        flash(entry.id)
    }

    func togglePin(_ entry: ClipboardEntry) {
        history.togglePin(entry.id)
        refresh()
    }

    /// Deletes one record (and, for an image, Island's saved copy of it).
    func remove(_ entry: ClipboardEntry) {
        history.remove(entry.id)
        refresh()
    }

    /// "Clear All": the first tap only arms it, the second (within a few seconds) deletes every record, pinned ones
    /// too, so a stray click cannot wipe the history.
    func requestClearAll() {
        guard !entries.isEmpty else { return }
        if clearArmed {
            disarmClear()
            history.clearAll()
            refresh()
        } else {
            clearArmed = true
            armTimer?.invalidate()
            armTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.disarmClear() }
            }
        }
    }

    func disarmClear() {
        armTimer?.invalidate()
        armTimer = nil
        clearArmed = false
    }

    /// "Scan text" on an image: copies the text found in it. Uses text that was already recognised, otherwise scans now.
    func copyText(of entry: ClipboardEntry) async {
        guard case .image(let fileName) = entry.content else { return }
        if let known = entry.ocrText, !known.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            putOnClipboard(known)
            return
        }
        let url = imagesDirectory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            show("The image file is no longer there.")
            return
        }
        show("Scanning…")
        let text = await quickOCR(image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show("No text found in this image.")
            return
        }
        history.setOCR(entry.id, text: text)
        refresh()
        putOnClipboard(text)
    }

    func actions(for entry: ClipboardEntry) -> [SmartAction] {
        switch entry.content {
        case .text(let text): return SmartAction.detect(in: text)
        case .link(let url): return [.openLink(url)]
        case .image, .files: return []
        }
    }

    func perform(_ action: SmartAction) {
        switch action {
        case .openLink(let url):
            NSWorkspace.shared.open(url)
        case .copyRGB(let rgb):
            _ = pasteboard.write(.text("rgb(\(rgb))"), imagesDirectory: imagesDirectory)
            monitor.markCurrentAsSeen()
        case .composeMail(let address):
            if let url = URL(string: "mailto:\(address)") { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: Internals

    private func refresh() {
        entries = history.entries
    }

    private func putOnClipboard(_ text: String) {
        _ = pasteboard.write(.text(text), imagesDirectory: imagesDirectory)
        monitor.markCurrentAsSeen()
        show("Copied the text from the image.")
    }

    /// Shows a short note under the list that goes away by itself.
    private func show(_ text: String) {
        message = text
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.message = nil }
        }
    }

    private func flash(_ id: UUID) {
        flashedID = id
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flashedID = nil }
        }
    }
}
