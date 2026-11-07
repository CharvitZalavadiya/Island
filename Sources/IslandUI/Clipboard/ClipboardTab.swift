import SwiftUI
import IslandCore

struct ClipboardTab: View {
    let controller: ClipboardController
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let entries = controller.visible(query: query)
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("Search copied text and text inside images", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.white.opacity(0.1), in: Capsule())
                PillButton(
                    title: controller.clearArmed ? "Tap again to clear all" : "Clear All", prominent: controller.clearArmed,
                    tint: IslandTheme.danger, height: 32
                ) {
                    controller.requestClearAll()
                }
            }

            if entries.isEmpty {
                Spacer()
                Text(query.isEmpty ? "Copy something and it will show up here" : "No matches")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            ClipboardRow(entry: entry, controller: controller)
                        }
                    }
                }
            }

            if let message = controller.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        // Typing needs Island to be the active app; this only happens when the search box gets focus.
        .onChange(of: searchFocused) { _, focused in
            if focused { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

struct ClipboardRow: View {
    let entry: ClipboardEntry
    let controller: ClipboardController
    @State private var hovering = false

    var body: some View {
        let actions = controller.actions(for: entry)
        HStack(spacing: 10) {
            leading(actions: actions)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if entry.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.black)
                            .padding(3)
                            .background(IslandTheme.pin, in: Circle())
                            .offset(x: -4, y: -4)
                    }
                }
            Text(preview)
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            controller.flashedID == entry.id ? IslandTheme.clipboard.opacity(0.3) : Color.white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12))
        // The buttons appear over the right end of the row only while the pointer is on it, so the row does not
        // change size or shift its text when they come and go.
        .overlay(alignment: .trailing) {
            if hovering { hoverActions(actions).padding(.trailing, 8) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { controller.copyBack(entry) }
    }

    // MARK: Actions (on hover)

    private func hoverActions(_ actions: [SmartAction]) -> some View {
        HStack(spacing: 6) {
            if case .image = entry.content {
                IconButton(symbol: "text.viewfinder", tint: IslandTheme.scan, help: "Copy the text found in this image") {
                    Task { await controller.copyText(of: entry) }
                }
            }
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                IconButton(symbol: symbol(for: action), tint: tint(for: action), help: label(for: action)) {
                    controller.perform(action)
                }
            }
            IconButton(
                symbol: entry.pinned ? "pin.slash" : "pin", tint: IslandTheme.pin,
                help: entry.pinned ? "Unpin" : "Pin to keep it at the top"
            ) { controller.togglePin(entry) }
            IconButton(symbol: "trash", tint: IslandTheme.danger, help: "Delete this record") {
                controller.remove(entry)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        // Frosted glass: the row's text behind the buttons is blurred, not just darkened.
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private func symbol(for action: SmartAction) -> String {
        switch action {
        case .openLink: "arrow.up.right.square"
        case .copyRGB: "paintpalette"
        case .composeMail: "envelope"
        }
    }

    private func tint(for action: SmartAction) -> Color {
        switch action {
        case .openLink: IslandTheme.link
        case .copyRGB: IslandTheme.swatch
        case .composeMail: IslandTheme.mail
        }
    }

    private func label(for action: SmartAction) -> String {
        switch action {
        case .openLink: "Open the link"
        case .copyRGB: "Copy the colour as RGB"
        case .composeMail: "Write an email"
        }
    }

    // MARK: The square on the left

    @ViewBuilder
    private func leading(actions: [SmartAction]) -> some View {
        if let swatch = swatchColor(actions) {
            Rectangle().fill(swatch)
        } else {
            switch entry.content {
            case .image(let fileName):
                ThumbnailView(url: controller.imagesDirectory.appendingPathComponent(fileName))
            case .text:
                icon("text.alignleft", tint: IslandTheme.clipboard)
            case .link:
                icon("link", tint: IslandTheme.link)
            case .files:
                icon("doc", tint: Color.white.opacity(0.7))
            }
        }
    }

    private func icon(_ name: String, tint: Color) -> some View {
        ZStack {
            Rectangle().fill(tint.opacity(0.18))
            Image(systemName: name).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
        }
    }

    private var preview: String {
        switch entry.content {
        case .text(let text): return String(text.prefix(200))
        case .link(let url): return url.absoluteString
        case .files(let urls): return urls.map(\.lastPathComponent).joined(separator: ", ")
        case .image:
            return "Image"   // the text found in it is still searched, it is just not spelled out here
        }
    }

    private func swatchColor(_ actions: [SmartAction]) -> Color? {
        for case .copyRGB(let rgb) in actions {
            let parts = rgb.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 3 { return Color(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255) }
        }
        return nil
    }
}

/// A small round icon button in its own colour.
private struct IconButton: View {
    let symbol: String
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.18), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Loads a saved image off the main render path and shows it as a small square.
struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                // Fills the square and is cropped to it, like a profile picture.
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.1)
            }
        }
        .clipped()
        .task { image = NSImage(contentsOf: url) }
    }
}
