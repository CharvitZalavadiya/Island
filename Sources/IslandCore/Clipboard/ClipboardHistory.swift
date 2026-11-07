import Foundation

/// The clipboard history: newest first, de-duplicated, capped, with pins that survive clearing.
public final class ClipboardHistory {
    public private(set) var entries: [ClipboardEntry]
    /// Called with entries that were dropped (by the limit or by clearing), so the owner can delete files they referenced.
    public var onRemove: (([ClipboardEntry]) -> Void)?

    private let store: FileStore<[ClipboardEntry]>
    private let limit: Int
    private let now: () -> Date

    public init(store: FileStore<[ClipboardEntry]>, limit: Int = 200, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.limit = limit
        self.now = now
        self.entries = store.load()
    }

    /// Adds a copy. Copying content that is already in the history moves it to the top, keeping its pin and recognized text.
    public func add(_ content: ClipboardContent) {
        let added: ClipboardEntry
        if let index = entries.firstIndex(where: { $0.content == content }) {
            var existing = entries.remove(at: index)
            existing.date = now()
            added = existing
        } else {
            added = ClipboardEntry(content: content, date: now())
        }
        entries.insert(added, at: 0)
        trimToLimit(keeping: added.id)
        save()
    }

    public func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
        save()
    }

    public func setOCR(_ id: UUID, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].ocrText = text
        save()
    }

    /// Deletes one entry (pinned or not). Unknown ids are ignored.
    public func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let removed = entries.remove(at: index)
        onRemove?([removed])
        save()
    }

    /// Deletes every entry, pinned ones included.
    public func clearAll() {
        guard !entries.isEmpty else { return }
        let removed = entries
        entries = []
        onRemove?(removed)
        save()
    }

    /// Entries whose text, link, file names or recognized image text contain `query` (case-insensitive).
    public func search(_ query: String) -> [ClipboardEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            searchableStrings(of: entry).contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    // MARK: Internals

    /// Drops the oldest unpinned entries beyond the limit. Pinned entries and the entry just added are never dropped,
    /// so a history full of pins can run past the limit instead of refusing new copies.
    private func trimToLimit(keeping keptID: UUID) {
        var removed: [ClipboardEntry] = []
        while entries.count > limit, let index = entries.lastIndex(where: { !$0.pinned && $0.id != keptID }) {
            removed.append(entries.remove(at: index))
        }
        if !removed.isEmpty { onRemove?(removed) }
    }

    private func searchableStrings(of entry: ClipboardEntry) -> [String] {
        var strings: [String]
        switch entry.content {
        case .text(let text): strings = [text]
        case .link(let url): strings = [url.absoluteString]
        case .image(let fileName): strings = [fileName]
        case .files(let urls): strings = urls.map(\.lastPathComponent)
        }
        if let ocr = entry.ocrText { strings.append(ocr) }
        return strings
    }

    private func save() {
        try? store.save(entries)
    }
}
