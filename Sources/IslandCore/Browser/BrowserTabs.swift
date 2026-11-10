import Foundation

/// A saved link. It is not a tab and is never "open": it costs nothing until it is clicked.
public struct BrowserBookmark: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var url: String

    public init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

/// The Browser tab's list of tabs and bookmarks. Pure data and rules, so that what survives closing a tab, closing
/// everything by mistake, quitting, and the old saved format can be tested.
public struct BrowserTabList: Codable, Equatable {
    public struct Entry: Codable, Equatable, Identifiable {
        public var id: UUID
        /// Where the tab was last (kept without secrets, see `BrowserAddress.kept`). A tab whose page was put to sleep reopens here.
        public var url: String?
        public var title: String

        public init(id: UUID = UUID(), url: String? = nil, title: String = "") {
            self.id = id
            self.url = url
            self.title = title
        }
    }

    public private(set) var open: [Entry]
    public private(set) var selected: UUID?
    public private(set) var bookmarks: [BrowserBookmark]
    /// Whether the vertical tab list is showing. Off at first.
    public var sidebarOpen: Bool

    public init(open: [Entry] = [], selected: UUID? = nil, bookmarks: [BrowserBookmark] = [], sidebarOpen: Bool = false) {
        self.open = open
        self.selected = selected
        self.bookmarks = bookmarks
        self.sidebarOpen = sidebarOpen
    }

    /// One new tab (blank, or on `url`), selected.
    public static func fresh(url: String? = nil, id: UUID = UUID()) -> BrowserTabList {
        BrowserTabList(open: [Entry(id: id, url: url)], selected: id)
    }

    // MARK: Saving and reading (including the format of the previous version, which had "pinned" tabs)

    private enum CodingKeys: String, CodingKey { case open, selected, bookmarks, sidebarOpen }
    private enum LegacyKeys: String, CodingKey { case pinned }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var open = try container.decodeIfPresent([Entry].self, forKey: .open) ?? []
        let selected = try container.decodeIfPresent(UUID.self, forKey: .selected)
        var bookmarks = try container.decodeIfPresent([BrowserBookmark].self, forKey: .bookmarks) ?? []
        sidebarOpen = try container.decodeIfPresent(Bool.self, forKey: .sidebarOpen) ?? false

        // Pinned tabs (always-open tabs) became bookmarks (links that only open when clicked). The one that was showing
        // stays open as an ordinary tab, so nothing the person has open disappears.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        for entry in try legacy.decodeIfPresent([Entry].self, forKey: .pinned) ?? [] {
            guard let url = entry.url else { continue }
            if !bookmarks.contains(where: { BrowserAddress.sameDestination($0.url, url) }) {
                bookmarks.append(BrowserBookmark(id: entry.id, title: entry.title, url: url))
            }
            if entry.id == selected { open.append(entry) }
        }
        self.open = open
        self.selected = selected
        self.bookmarks = bookmarks
    }

    // MARK: Looking

    public func entry(_ id: UUID) -> Entry? { open.first { $0.id == id } }
    public var selectedEntry: Entry? { selected.flatMap(entry) }

    /// The bookmark for a page, if there is one.
    public func bookmark(for url: String) -> BrowserBookmark? {
        bookmarks.first { BrowserAddress.sameDestination($0.url, url) }
    }

    /// The open tab already on this page, if any.
    public func openTab(on url: String) -> Entry? {
        open.first { entry in entry.url.map { BrowserAddress.sameDestination($0, url) } ?? false }
    }

    // MARK: Changing tabs

    /// Makes a tab exist and be selected whatever a saved file said: a selection that points nowhere, or no tab at all.
    public mutating func repair(blankID: UUID = UUID()) {
        if let selected, entry(selected) == nil { self.selected = nil }
        if selected == nil { selected = open.first?.id }
        if selected == nil { addOpen(id: blankID) }
    }

    /// A new open tab, placed after `after` when that is an open tab (a popup next to the page that opened it), else last.
    @discardableResult
    public mutating func addOpen(url: String? = nil, id: UUID = UUID(), select: Bool = true, after: UUID? = nil) -> UUID {
        let entry = Entry(id: id, url: url)
        if let after, let index = open.firstIndex(where: { $0.id == after }) {
            open.insert(entry, at: index + 1)
        } else {
            open.append(entry)
        }
        if select { selected = id }
        return id
    }

    public mutating func select(_ id: UUID) {
        if entry(id) != nil { selected = id }
    }

    /// Closes a tab. If it was the selected one the neighbour is selected, and when nothing is left a blank tab is opened,
    /// so closing every tab by mistake never leaves the person with nothing to look at (and never touches the bookmarks).
    @discardableResult
    public mutating func close(_ id: UUID, blankID: UUID = UUID()) -> Bool {
        guard let index = open.firstIndex(where: { $0.id == id }) else { return false }
        open.remove(at: index)
        if selected == id { selected = open.isEmpty ? nil : open[min(index, open.count - 1)].id }
        if selected == nil { addOpen(id: blankID) }
        return true
    }

    /// Records where a tab is and what it is called.
    public mutating func update(_ id: UUID, url: String?, title: String?) {
        guard let index = open.firstIndex(where: { $0.id == id }) else { return }
        if let url { open[index].url = url }
        if let title { open[index].title = title }
    }

    // MARK: Changing bookmarks

    /// Adds a bookmark for a page (not twice for the same page). Returns whether one was added.
    @discardableResult
    public mutating func addBookmark(title: String, url: String) -> Bool {
        guard bookmark(for: url) == nil else { return false }
        bookmarks.append(BrowserBookmark(title: title, url: url))
        return true
    }

    public mutating func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    /// The star: bookmarks the page, or removes its bookmark. Returns whether it is bookmarked now.
    @discardableResult
    public mutating func toggleBookmark(title: String, url: String) -> Bool {
        if let existing = bookmark(for: url) {
            removeBookmark(existing.id)
            return false
        }
        addBookmark(title: title, url: url)
        return true
    }
}
