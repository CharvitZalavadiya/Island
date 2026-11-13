import SwiftUI

/// The card a tool opens over its tab for its settings. It belongs to no feature in particular: give it a title, an icon, the
/// tool's colour and what to do when it is closed; if the tool can be switched on and off, give it the switch for the header; and
/// put whatever the tool needs inside. It fills the area of the tab (whatever was there is covered until it is closed) and
/// draws its own header and close button, so every tool's settings look and behave alike.
///
///     ToolPopup(title: "My tool", symbol: "star", tint: .orange, isOn: $enabled, onClose: { open = false }) {
///         MyToolSettings()
///     }
struct ToolPopup<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    /// A tool that can be switched on and off shows its switch in the header.
    var isOn: Binding<Bool>?
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            if let isOn {
                Text(isOn.wrappedValue ? "On" : "Off")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? tint : Color.white.opacity(0.5))
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(tint)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.55))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Close")
        }
        .frame(height: 24)
    }
}
