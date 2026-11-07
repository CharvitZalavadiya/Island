import Testing
import AppKit
@testable import IslandUI

@Test @MainActor func theEditMenuGivesTextBoxesTheirShortcuts() throws {
    let menu = MainMenu.make()
    let edit = try #require(menu.items.compactMap(\.submenu).first { $0.title == "Edit" })
    func item(_ key: String, shift: Bool = false) -> NSMenuItem? {
        edit.items.first { $0.keyEquivalent == key && ($0.keyEquivalentModifierMask.contains(.shift) == shift) }
    }
    #expect(item("v")?.action == #selector(NSText.paste(_:)))
    #expect(item("c")?.action == #selector(NSText.copy(_:)))
    #expect(item("x")?.action == #selector(NSText.cut(_:)))
    #expect(item("a")?.action == #selector(NSText.selectAll(_:)))
    #expect(item("z")?.action == Selector(("undo:")))
    #expect(item("z", shift: true)?.action == Selector(("redo:")))
    // Every shortcut is a plain ⌘ one, aimed at whichever box has the cursor (no fixed target).
    #expect(edit.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.target == nil && $0.keyEquivalentModifierMask.contains(.command) })
    // And quitting has no shortcut: it must not happen while typing.
    let app = try #require(menu.items.first?.submenu)
    #expect(app.items.allSatisfy { $0.keyEquivalent.isEmpty })
}
