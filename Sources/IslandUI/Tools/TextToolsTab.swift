import SwiftUI
import IslandCore

/// What the Base64 & Cron tab remembers while you switch to other tabs and back. Each tool keeps its own text, so a
/// glance at Cron does not lose what was in the Base64 box.
@Observable
@MainActor
final class TextToolsController {
    enum Mode: Hashable {
        case base64
        case cron
    }

    /// How the result is drawn: normally, dimmed (still waiting for more typing), or as an error.
    enum Tone: Equatable {
        case normal
        case dim
        case error
    }

    struct Shown: Equatable {
        var text: String
        var tone: Tone
    }

    /// How many upcoming run times Cron lists under its sentence.
    static let nextRunCount = 4

    var mode: Mode = .base64
    var base64Input = ""
    var cronInput = ""
    private(set) var base64Output = ""
    private(set) var base64Error: String?

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let use24Hour: () -> Bool
    @ObservationIgnored private let calendar: Calendar

    init(
        now: @escaping () -> Date = Date.init, use24Hour: @escaping () -> Bool = { CronTool.uses24HourClock() },
        calendar: Calendar = .current
    ) {
        self.now = now
        self.use24Hour = use24Hour
        self.calendar = calendar
    }

    /// The text in the input box of whichever tool is showing.
    var input: String {
        get { mode == .base64 ? base64Input : cronInput }
        set {
            if mode == .base64 { base64Input = newValue } else { cronInput = newValue }
        }
    }

    // MARK: Base64

    func encode() {
        base64Output = Base64Tool.encode(base64Input)
        base64Error = nil
    }

    func decode() {
        switch Base64Tool.decode(base64Input) {
        case .success(let text):
            base64Output = text
            base64Error = nil
        case .failure(let failure):
            base64Output = ""
            base64Error = failure.message
        }
    }

    // MARK: Both

    func clearInput() { input = "" }

    /// Empties the Base64 result. (The Cron result follows its input, so it has nothing to clear.)
    func clearOutput() {
        base64Output = ""
        base64Error = nil
    }

    /// What the result box shows now. For Base64 that is what the last Encode or Decode made; for Cron it is worked out
    /// from the input the moment it changes, with no button to press.
    var shown: Shown {
        switch mode {
        case .base64:
            if let base64Error { return Shown(text: base64Error, tone: .error) }
            return Shown(text: base64Output, tone: .normal)
        case .cron:
            return cronShown
        }
    }

    private var cronShown: Shown {
        let current = now()
        switch CronTool.evaluate(cronInput, use24Hour: use24Hour(), now: current, calendar: calendar, nextRunCount: Self.nextRunCount) {
        case .empty:
            return Shown(text: "", tone: .normal)
        case .incomplete(let hint):
            return Shown(text: hint, tone: .dim)
        case .invalid(let problem):
            return Shown(text: problem, tone: .error)
        case .described(let summary, let runs):
            guard !runs.isEmpty else { return Shown(text: summary, tone: .normal) }
            let usesSeconds = cronInput.split(whereSeparator: \.isWhitespace).count >= 6
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(usesSeconds ? "EEEd MMM jms" : "EEEd MMM jm")
            let zone = calendar.timeZone.abbreviation(for: current) ?? calendar.timeZone.identifier
            let lines = runs.map { formatter.string(from: $0) }.joined(separator: "\n")
            return Shown(text: "\(summary)\n\nNext runs (\(zone))\n\(lines)", tone: .normal)
        }
    }

    /// Whether Copy has anything worth copying.
    var copyText: String {
        let result = shown
        return result.tone == .normal ? result.text : ""
    }
}

/// Base64 encode and decode, and cron expressions in plain words. A switch at the top picks the tool; Base64 has its
/// Encode and Decode buttons beside it, Cron has none because it answers as you type. Below are the input and the
/// result, the same kind of box (the same height too for Base64).
struct TextToolsTab: View {
    @Bindable var controller: TextToolsController

    private let tint = IslandTheme.swatch
    private static let headerHeight: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 8
            let room = proxy.size.height - Self.headerHeight - spacing * 2
            // Base64: two boxes of the same height. A cron expression is one short line and its answer is several, so
            // in Cron the answer gets most of the room.
            let inputHeight = controller.mode == .base64 ? room / 2 : room * 0.25
            let outputHeight = room - inputHeight
            VStack(spacing: spacing) {
                header
                    .frame(height: Self.headerHeight)

                block(
                    text: $controller.input, isEditable: true,
                    placeholder: controller.mode == .base64 ? "Type or paste text here" : "Paste a cron expression, e.g. 30 14 * * *",
                    copyText: controller.input, color: .white, clearable: true, buttonsInARow: controller.mode == .cron,
                    clear: { controller.clearInput() })
                    .frame(height: inputHeight)

                let shown = controller.shown
                block(
                    text: .constant(shown.text), isEditable: false,
                    placeholder: controller.mode == .base64 ? "The result appears here" : "What it means appears here",
                    copyText: controller.copyText, color: color(for: shown.tone), clearable: controller.mode == .base64,
                    clear: { controller.clearOutput() })
                    .frame(height: outputHeight)
            }
            // A fresh pair of boxes for each tool, so one tool's undo history and cursor never leak into the other.
            .id(controller.mode)
        }
        .foregroundStyle(.white)
    }

    /// The Base64 | Cron switch, with Encode and Decode on the right while Base64 is showing.
    private var header: some View {
        HStack(spacing: 8) {
            PillSwitch(
                selection: $controller.mode, options: [(.base64, "Base64"), (.cron, "Cron")], tint: tint.opacity(0.72))
            Spacer(minLength: 0)
            if controller.mode == .base64 {
                actionButton("Encode") { controller.encode() }
                actionButton("Decode") { controller.decode() }
            }
        }
    }

    private func color(for tone: TextToolsController.Tone) -> Color {
        switch tone {
        case .normal: .white
        case .dim: .white.opacity(0.5)
        case .error: IslandTheme.danger
        }
    }

    /// One box: the text, a placeholder while it is empty, and Copy above Clear at the top right.
    private func block(
        text: Binding<String>, isEditable: Bool, placeholder: String, copyText: String, color: Color,
        clearable: Bool, buttonsInARow: Bool = false, clear: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ToolTextView(text: text, isEditable: isEditable, color: color)
                // Keeps the text clear of the buttons. (In a short box they sit side by side, which needs more room.)
                .padding(.trailing, buttonsInARow && clearable ? 68 : 36)
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.leading, ToolTextView.inset.width)
                    .padding(.top, ToolTextView.inset.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            // One above the other, or side by side when the box is too short to hold them stacked.
            let buttons = Group {
                CopyButton(text: copyText, tint: tint)
                if clearable { ClearButton(isEmpty: text.wrappedValue.isEmpty, tint: tint, action: clear) }
            }
            Group {
                if buttonsInARow { HStack(spacing: 4) { buttons } } else { VStack(spacing: 4) { buttons } }
            }
            .padding(7)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: 80, height: 24)
                .background(tint.opacity(0.72), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Copies `text` to the clipboard; the icon turns into a tick for a moment.
struct CopyButton: View {
    let text: String
    let tint: Color
    @State private var copied = false

    var body: some View {
        Button {
            guard !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(copied ? IslandTheme.tasks : tint)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(text.isEmpty ? 0.35 : 1)
        .help("Copy")
    }
}

/// Empties a box.
struct ClearButton: View {
    let isEmpty: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.35 : 1)
        .help("Clear")
    }
}
