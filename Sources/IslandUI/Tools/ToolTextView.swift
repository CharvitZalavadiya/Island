import AppKit
import SwiftUI

/// The text box used for both the input and the result on the Base64 & Cron tab, so the two look exactly alike: the same
/// font, the same colour and the same space inside. The input is editable; the result can be selected and copied.
struct ToolTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var color: Color = .white

    /// Space between the text and the edge of the box.
    static let inset = NSSize(width: 12, height: 10)
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusingTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.font = Self.font
        textView.insertionPointColor = .white
        textView.isRichText = false
        textView.allowsUndo = true
        // Base64 and its input are exact text: nothing may be "corrected" into curly quotes or long dashes.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        // macOS's Writing Tools button would pop out of the island's edge when the box is focused.
        textView.writingToolsBehavior = .none
        textView.textContainerInset = Self.inset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.documentView = textView
        apply(to: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        apply(to: textView)
    }

    private func apply(to textView: NSTextView) {
        textView.isEditable = isEditable
        textView.isSelectable = true
        let nsColor = NSColor(color)
        if textView.string != text { textView.string = text }
        textView.font = Self.font
        textView.textColor = nsColor
        textView.typingAttributes = [.font: Self.font, .foregroundColor: nsColor]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ToolTextView
        init(_ parent: ToolTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, textView.string != parent.text else { return }
            parent.text = textView.string
        }
    }
}

/// Island is almost never the active app, and typing only reaches a box in the active app, so an editable box makes
/// Island active the moment it is clicked.
private final class FocusingTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        if isEditable { NSApp.activate(ignoringOtherApps: true) }
        return super.becomeFirstResponder()
    }
}
