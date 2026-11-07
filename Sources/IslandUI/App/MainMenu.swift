import AppKit

/// Island's menu bar, which is never drawn (the app has no Dock icon) but still decides what the keyboard shortcuts do.
/// Without an Edit menu, ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z do nothing in any text box, which is why pasting did not work.
enum MainMenu {
    @MainActor
    static func install() {
        NSApp.mainMenu = make()
    }

    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        // The first menu belongs to the app. It has no shortcuts: quitting by accident while typing would be unkind.
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Island")
        appMenu.addItem(withTitle: "Quit Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
