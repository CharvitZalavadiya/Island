import Foundation

public struct ShelfItem: Codable, Identifiable, Equatable {
    public let id: UUID
    /// A macOS bookmark, so the file is found again even if it is moved or renamed.
    public var bookmark: Data
    public let displayName: String
    public let addedAt: Date
    public let isScreenshot: Bool
    /// Where the file was the last time Island saw it, so "Show in Finder" can still open the right folder after the
    /// file is deleted. Shelves saved by earlier versions do not have it.
    public var lastKnownPath: String?

    public init(
        id: UUID = UUID(), bookmark: Data, displayName: String, addedAt: Date, isScreenshot: Bool,
        lastKnownPath: String? = nil
    ) {
        self.id = id
        self.bookmark = bookmark
        self.displayName = displayName
        self.addedAt = addedAt
        self.isScreenshot = isScreenshot
        self.lastKnownPath = lastKnownPath
    }
}

public enum ResolvedShelfItem: Equatable {
    case available(URL)
    /// The file was deleted (or moved to the Trash); the item stays on the shelf, greyed out.
    case missing
}

/// The file shelf. It holds references to files and never moves, copies or deletes the originals.
public final class ShelfStore {
    public private(set) var items: [ShelfItem]

    private let store: FileStore<[ShelfItem]>
    private let now: () -> Date

    public init(store: FileStore<[ShelfItem]>, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        self.items = store.load()
    }

    /// Adds files (newest first). Files that do not exist, or are already on the shelf, are skipped.
    public func add(urls: [URL], isScreenshot: Bool = false) {
        var changed = false
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path), let bookmark = try? url.bookmarkData() else { continue }
            let path = url.resolvingSymlinksInPath().path
            let alreadyThere = items.contains { item in
                if case .available(let existing) = resolve(item) { return existing.resolvingSymlinksInPath().path == path }
                return false
            }
            if alreadyThere { continue }
            items.insert(
                ShelfItem(
                    bookmark: bookmark, displayName: url.lastPathComponent, addedAt: now(), isScreenshot: isScreenshot,
                    lastKnownPath: url.path),
                at: 0)
            changed = true
        }
        if changed { save() }
    }

    /// Takes the item off the shelf. The file itself is left alone.
    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func resolve(_ item: ShelfItem) -> ResolvedShelfItem {
        var stale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: item.bookmark, options: [.withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale),
            FileManager.default.fileExists(atPath: url.path),
            !Self.isTrashed(url)
        else { return .missing }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var changed = false
            if stale, let fresh = try? url.bookmarkData() {
                items[index].bookmark = fresh
                changed = true
            }
            // Compared without symlinks, so /var and /private/var do not look like a move.
            let known = items[index].lastKnownPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            if known != url.resolvingSymlinksInPath().path {
                items[index].lastKnownPath = url.path
                changed = true
            }
            if changed { save() }
        }
        return .available(url)
    }

    /// A bookmark follows a file into the Trash, but a trashed file counts as gone.
    public static func isTrashed(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    private func save() {
        try? store.save(items)
    }
}
