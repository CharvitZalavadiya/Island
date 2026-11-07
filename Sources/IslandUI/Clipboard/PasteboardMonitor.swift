import AppKit
import ImageIO
import IslandCore

/// What was on the pasteboard at one moment, reduced to what Island cares about.
struct PasteboardSnapshot: Equatable {
    var types: [String] = []
    var string: String?
    /// Only filled when there is no text and no file, since text and files win over an image that comes with them.
    var imagePNGData: Data?
    var fileURLs: [URL] = []
}

/// The pasteboard as Island uses it. The real one is `SystemPasteboard`; tests use a fake.
protocol PasteboardAccess {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    /// Replaces the pasteboard's contents and returns the new change count.
    func write(_ content: ClipboardContent, imagesDirectory: URL) -> Int
}

/// The real pasteboard. Tests pass a private, uniquely named `NSPasteboard` instead of the general one.
struct SystemPasteboard: PasteboardAccess {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> PasteboardSnapshot {
        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let string = pasteboard.string(forType: .string)
        var png: Data?
        if fileURLs.isEmpty, string == nil {
            if let data = pasteboard.data(forType: .png) {
                png = data
            } else if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
                png = rep.representation(using: .png, properties: [:])
            }
        }
        return PasteboardSnapshot(
            types: pasteboard.types?.map(\.rawValue) ?? [], string: string, imagePNGData: png, fileURLs: fileURLs)
    }

    func write(_ content: ClipboardContent, imagesDirectory: URL) -> Int {
        pasteboard.clearContents()
        switch content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .link(let url):
            pasteboard.setString(url.absoluteString, forType: .string)
            pasteboard.writeObjects([url as NSURL])
        case .image(let fileName):
            if let image = NSImage(contentsOf: imagesDirectory.appendingPathComponent(fileName)) {
                pasteboard.writeObjects([image])
            }
        case .files(let urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
        return pasteboard.changeCount
    }
}

/// Watches the pasteboard (twice a second, comparing only its change count) and records what is copied.
@MainActor
final class PasteboardMonitor {
    /// Called after anything is recorded or its recognized text arrives.
    var onChange: (() -> Void)?

    private let history: ClipboardHistory
    private let imagesDirectory: URL
    private let pasteboard: PasteboardAccess
    private let ocr: @Sendable (CGImage) async -> String
    /// A faster, less careful reading done first, so the text is searchable within a moment of the copy; the careful
    /// one then replaces it. Nil means only the careful reading is done.
    private let quickOCR: (@Sendable (CGImage) async -> String)?
    private var lastChangeCount = 0
    private var timer: Timer?

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
        self.quickOCR = quickOCR
    }

    /// Starts watching. Whatever is on the pasteboard right now is not recorded.
    func start() {
        lastChangeCount = pasteboard.changeCount
        guard timer == nil else { return }
        // Four times a second: a copy is noticed within a quarter of a second. Looking is just comparing a counter.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Treats the current pasteboard contents as already seen. Used after Island itself writes to the pasteboard.
    func markCurrentAsSeen() {
        lastChangeCount = pasteboard.changeCount
    }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        process(pasteboard.snapshot())
    }

    /// Records a snapshot if it should be recorded. For an image, returns the task that adds its recognized text.
    @discardableResult
    func process(_ snapshot: PasteboardSnapshot) -> Task<Void, Never>? {
        guard ClipboardFilter.shouldRecord(types: snapshot.types, text: snapshot.string) else { return nil }
        if !snapshot.fileURLs.isEmpty {
            history.add(.files(snapshot.fileURLs))
        } else if let text = snapshot.string {
            if case .openLink(let url)? = SmartAction.detect(in: text).first {
                history.add(.link(url))
            } else {
                history.add(.text(text))
            }
        } else if let png = snapshot.imagePNGData {
            return recordImage(png)
        } else {
            return nil
        }
        onChange?()
        return nil
    }

    private func recordImage(_ png: Data) -> Task<Void, Never>? {
        let fileName = "\(UUID().uuidString).png"
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try png.write(to: imagesDirectory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            return nil
        }
        history.add(.image(fileName: fileName))
        onChange?()

        guard let id = history.entries.first?.id,
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let ocr = self.ocr
        let quickOCR = self.quickOCR
        return Task { [weak self] in
            var stored = ""
            if let quickOCR {
                stored = await quickOCR(image)
                if let self, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.history.setOCR(id, text: stored)
                    self.onChange?()
                }
            }
            let careful = await ocr(image)
            guard let self, !careful.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, careful != stored else { return }
            self.history.setOCR(id, text: careful)
            self.onChange?()
        }
    }
}
