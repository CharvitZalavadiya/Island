import AppKit
import Observation
import IslandCore

/// Opens Finder, behind a seam so tests do not open real windows.
@MainActor
protocol FinderOpening {
    /// A Finder window with the file or folder selected.
    func reveal(_ url: URL)
    func openFolder(_ url: URL)
}

struct SystemFinder: FinderOpening {
    // Conforming to a main-actor protocol makes the type main-actor too; this init has no state, so it may be called
    // from a default argument.
    nonisolated init() {}
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openFolder(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// The shelf feature: the list of stashed files, which of them are selected, the actions on the selection, and new
/// screenshots. Results of converting, zipping or unzipping are added to the shelf so they can be dragged out too.
@Observable
@MainActor
final class ShelfController {
    private(set) var items: [ShelfItem]
    /// The tiles the user has clicked. The action bar acts on these.
    private(set) var selectedIDs: Set<UUID> = []
    /// The outcome of the last action, shown at the bottom of the tab.
    private(set) var message: String?

    @ObservationIgnored private let store: ShelfStore
    @ObservationIgnored private let model: IslandModel
    @ObservationIgnored private let finder: FinderOpening

    init(store: ShelfStore, model: IslandModel, finder: FinderOpening = SystemFinder()) {
        self.store = store
        self.model = model
        self.finder = finder
        self.items = store.items
    }

    // MARK: Items

    func add(urls: [URL]) {
        store.add(urls: urls)
        refresh()
    }

    /// Takes the item off the shelf. The file itself is left alone.
    func remove(_ item: ShelfItem) {
        store.remove(item.id)
        refresh()
    }

    func url(for item: ShelfItem) -> URL? {
        if case .available(let url) = store.resolve(item) { return url }
        return nil
    }

    func isMissing(_ item: ShelfItem) -> Bool {
        url(for: item) == nil
    }

    // MARK: Selection

    func toggleSelection(_ item: ShelfItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedIDs = []
    }

    /// The selected items, in shelf order.
    var selectedItems: [ShelfItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    /// What the action bar offers. Files that have vanished cannot be zipped, converted or sent, so they are left out
    /// of those; they can still be taken off the shelf, and Show in Finder opens the folder they were in.
    var actions: ShelfActions {
        var result = ShelfActions.make(for: selectedURLs)
        result.canRemove = !selectedItems.isEmpty
        result.canShowInFinder = selectedItems.count == 1
        return result
    }

    private var selectedURLs: [URL] {
        selectedItems.compactMap { url(for: $0) }
    }

    // MARK: Actions on the selection

    /// Several files become one `Archive.zip`; a single file becomes `<name>.zip`.
    func zipSelected() async {
        let urls = selectedURLs
        guard !urls.isEmpty else {
            message = selectedIDs.isEmpty ? "Select the files to zip first." : "The selected files aren't there any more."
            return
        }
        do {
            let result = try await Task.detached {
                if urls.count == 1 { return try ArchiveService.zip(urls[0]) }
                return try ArchiveService.zip(urls: urls)
            }.value
            finish(adding: [result], verb: "Zipped to")
        } catch {
            message = "Couldn't zip: \(Self.describe(error))"
        }
    }

    /// Converts every selected image or PDF. Files that cannot be converted to `format`, or already are `format`,
    /// are skipped, and the one message says what happened to all of them.
    func convertSelected(to format: ImageFormat) async {
        let urls = selectedURLs
        let convertible = urls.filter { ShelfActions.isConvertible($0) && ShelfActions.format(of: $0) != format }
        guard !convertible.isEmpty else {
            message = urls.isEmpty
                ? "The selected files aren't there any more."
                : "None of the selected files can be converted to \(format.label)."
            return
        }
        let outcome = await Task.detached { () -> (written: [URL], failed: [String]) in
            var written: [URL] = []
            var failed: [String] = []
            for url in convertible {
                do { written += try ImageConverter.convert(url, to: format) } catch { failed.append(url.lastPathComponent) }
            }
            return (written, failed)
        }.value

        store.add(urls: outcome.written)
        refresh()
        var parts: [String] = []
        if !outcome.written.isEmpty { parts.append("Converted to " + outcome.written.map(\.lastPathComponent).joined(separator: ", ") + ".") }
        if !outcome.failed.isEmpty { parts.append("Couldn't convert " + outcome.failed.joined(separator: ", ") + ".") }
        let skipped = urls.count - convertible.count
        if skipped > 0 { parts.append("Skipped \(skipped).") }
        message = parts.joined(separator: " ")
    }

    func unzipSelected() async {
        guard actions.canUnzip, let item = selectedItems.first(where: { !isMissing($0) }) else { return }
        await unzip(item)
    }

    func airDropSelected() {
        let urls = selectedURLs
        guard !urls.isEmpty else {
            message = "The selected files aren't there any more."
            return
        }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            message = "AirDrop isn't available right now. Check that Wi-Fi and Bluetooth are on."
            return
        }
        service.perform(withItems: urls)
    }

    /// Takes the selected items off the shelf. The files themselves are left alone.
    func removeSelected() {
        for item in selectedItems { store.remove(item.id) }
        refresh()
    }

    /// Finder opens with the file selected; if it is gone, with the folder it was in; failing that, the home folder.
    func showSelectedInFinder() {
        guard selectedItems.count == 1, let item = selectedItems.first else { return }
        let resolved = url(for: item)
        // The store keeps the freshest path (it is updated whenever a moved file is found again).
        let lastKnownPath = store.items.first(where: { $0.id == item.id })?.lastKnownPath ?? item.lastKnownPath
        let target = FinderReveal.target(
            resolved: resolved, lastKnownPath: lastKnownPath,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            home: FileManager.default.homeDirectoryForCurrentUser)
        switch target {
        case .reveal(let url): finder.reveal(url)
        case .openFolder(let url): finder.openFolder(url)
        }
    }

    // MARK: Actions

    func convert(_ item: ShelfItem, to format: ImageFormat) async {
        guard let url = availableURL(for: item) else { return }
        do {
            let results = try await Task.detached { try ImageConverter.convert(url, to: format) }.value
            finish(adding: results, verb: "Converted to")
        } catch {
            message = "Couldn't convert \(item.displayName): \(Self.describe(error))"
        }
    }

    func zip(_ item: ShelfItem) async {
        guard let url = availableURL(for: item) else { return }
        do {
            let result = try await Task.detached { try ArchiveService.zip(url) }.value
            finish(adding: [result], verb: "Zipped to")
        } catch {
            message = "Couldn't zip \(item.displayName): \(Self.describe(error))"
        }
    }

    func unzip(_ item: ShelfItem) async {
        guard let url = availableURL(for: item) else { return }
        do {
            let result = try await Task.detached { try ArchiveService.unzip(url) }.value
            finish(adding: [result], verb: "Unzipped to")
        } catch {
            message = "Couldn't unzip \(item.displayName): \(Self.describe(error))"
        }
    }

    func airDrop(_ item: ShelfItem) {
        guard let url = availableURL(for: item) else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [url]) else {
            message = "AirDrop isn't available right now. Check that Wi-Fi and Bluetooth are on."
            return
        }
        service.perform(withItems: [url])
    }

    // MARK: Screenshots

    /// A new screenshot goes on the shelf (marked as a screenshot).
    func handleScreenshot(_ url: URL) {
        store.add(urls: [url], isScreenshot: true)
        refresh()
    }

    // MARK: Internals

    private func availableURL(for item: ShelfItem) -> URL? {
        if let url = url(for: item) { return url }
        message = "\(item.displayName) isn't there any more."
        return nil
    }

    private func finish(adding results: [URL], verb: String) {
        store.add(urls: results)
        refresh()
        message = "\(verb) " + results.map(\.lastPathComponent).joined(separator: ", ")
    }

    private func refresh() {
        items = store.items
        selectedIDs.formIntersection(items.map(\.id))
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case ImageConverterError.unreadable: "it isn't a readable image or PDF."
        case ImageConverterError.writeFailed: "the result couldn't be written."
        case ArchiveError.failed(let text): text
        default: error.localizedDescription
        }
    }
}
