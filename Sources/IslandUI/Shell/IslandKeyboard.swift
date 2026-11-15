import AppKit
import WebKit
import IslandCore

/// Remembers the app the person was in before Island took the keyboard, so the keyboard can go back to it when the island
/// closes (or focus mode ends).
@MainActor
final class PreviousAppTracker {
    private var last: NSRunningApplication?
    private var observer: NSObjectProtocol?

    init(notifications: NotificationCenter? = nil, frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        let own = ProcessInfo.processInfo.processIdentifier
        if let frontmost, frontmost.processIdentifier != own { last = frontmost }
        observer = (notifications ?? NSWorkspace.shared.notificationCenter).addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier,
                pid != own
            else { return }
            MainActor.assumeIsolated { self?.last = NSRunningApplication(processIdentifier: pid) }
        }
    }

    /// The last app other than Island that was in front, if it is still running.
    var previous: NSRunningApplication? { last.flatMap { $0.isTerminated ? nil : $0 } }
}

enum IslandKeyboard {
    /// Whether the keyboard is going into something that takes typing: a text box being edited, or a web page. The plain-letter
    /// shortcuts must leave those alone.
    @MainActor
    static func isTyping(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if responder is NSText || responder is NSTextInputClient { return true }
        var view = responder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }
}

/// Acts on the island's keyboard shortcuts (see `IslandShortcuts` for which keys), according to what the island is showing.
@MainActor
struct IslandShortcutHandler {
    let model: IslandModel
    let openSettings: () -> Void

    /// Does what the key press asks, if it is a shortcut that applies now. Returns whether it did, so the key is then taken.
    func handle(_ press: KeyPress, isTyping: Bool) -> Bool {
        guard model.mode == .expanded || model.isFocusView,
            let shortcut = IslandShortcuts.shortcut(for: press, isTyping: isTyping)
        else { return false }
        switch shortcut {
        case .focusMode:
            model.isFocusView.toggle()
        case .toggleMax:
            // Max and Pin are about the island hanging from the notch; focus mode has neither.
            guard !model.isFocusView else { return false }
            model.isMax.toggle()
        case .togglePin:
            guard !model.isFocusView else { return false }
            model.isPinned.toggle()
        case .openSettings:
            model.isFocusView = false          // the settings window would open behind the focus card
            openSettings()
        }
        return true
    }
}

extension KeyPress {
    /// From a key-down event.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.init(
            key: event.charactersIgnoringModifiers ?? "", command: flags.contains(.command), option: flags.contains(.option),
            control: flags.contains(.control), shift: flags.contains(.shift), isRepeat: event.isARepeat)
    }
}
