import AppKit
import SwiftUI

/// A one-line search box that takes the keyboard the moment it appears.
///
/// Island is almost never the active app and its window is a panel that does not take the keyboard by itself, so a
/// SwiftUI text field that is focused in code can silently fail, and the keyboard focus then falls to the first control in
/// the window (the first tab). This box does it the AppKit way: it makes the app active, makes the island the key window
/// and takes the first-responder spot, then checks a few times in the next moment that nothing took it back.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Take the keyboard as soon as the box appears (a search that was just opened). Otherwise it waits to be clicked.
    var focusesOnAppear = true
    /// Change this number to ask the box to take the keyboard again (after a repository was chosen, say).
    var focusRequest = 0
    var onSubmit: () -> Void = {}
    /// Escape.
    var onCancel: () -> Void = {}
    /// The person started typing (true), or left the box (false). Not called for changes made in code.
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.focusesOnAppear = focusesOnAppear
        field.stringValue = text
        context.coordinator.lastFocusRequest = focusRequest
        updatePlaceholder(of: field)
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        updatePlaceholder(of: field)
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            field.claimFocus()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusingTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 20)
    }

    private func updatePlaceholder(of field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 13)])
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var lastFocusRequest = 0
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            // The blinking cursor is white, like the text.
            ((notification.object as? NSTextField)?.currentEditor() as? NSTextView)?.insertionPointColor = .white
        }

        func controlTextDidChange(_ notification: Notification) {
            parent.onEditingChanged(true)
            guard let field = notification.object as? NSTextField, field.stringValue != parent.text else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

final class FocusingTextField: NSTextField {
    var focusesOnAppear = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, focusesOnAppear { claimFocus() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        // A click on the box also makes Island the active app, so what is typed reaches it.
        NSApp.activate(ignoringOtherApps: true)
        return super.becomeFirstResponder()
    }

    /// Takes the keyboard, and looks again a moment later (up to four times) in case becoming the active app moved the
    /// focus away again.
    func claimFocus(attempt: Int = 0) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            window.makeFirstResponder(self)
            guard attempt < 4 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, let window = self.window else { return }
                if self.currentEditor() == nil || window.firstResponder !== self.currentEditor() { self.claimFocus(attempt: attempt + 1) }
            }
        }
    }
}
