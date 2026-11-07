import SwiftUI
import IslandCore

/// The Tools tab: the player down the whole left side, and the tools as small square tiles beside it, the same size as a
/// mascot tile in the Focus tab. Pick a colour from anywhere on the screen, and lock the keyboard for half a minute
/// while it is wiped clean.
struct ToolsTab: View {
    @Bindable var controller: ToolsController
    let nowPlaying: NowPlayingController
    /// The tool the pointer is over, so its name can be shown (the tiles are too small to carry one).
    @State private var hovered: ToolHint?

    private static let playerWidth: CGFloat = 178

    struct ToolHint: Equatable {
        var title: String
        var detail: String
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 12) {
                PlayerTile(controller: nowPlaying, width: Self.playerWidth, height: geometry.size.height)
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: IslandMetrics.toolTile, maximum: IslandMetrics.toolTile), spacing: 6)],
                        alignment: .leading, spacing: 6
                    ) {
                        tools
                    }
                    status
                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(.white)
        // Listens to what is playing only while this tab is on screen.
        .onAppear { nowPlaying.start() }
        .onDisappear { nowPlaying.stop() }
    }

    @ViewBuilder
    private var tools: some View {
        let locked = controller.keyboard == .locked
        let pick = ToolHint(title: "Pick color", detail: "Click anywhere on the screen to pick a color.")
        ToolTile(
            hint: pick, symbol: "eyedropper", tint: IslandTheme.swatch, ringFraction: nil, hovered: $hovered
        ) { controller.pickColor() }

        let clean = ToolHint(
            title: locked ? "Unlock keyboard" : "Clean keyboard",
            detail: locked ? "\(Int(controller.lockRemaining.rounded(.up))) s left. Click to unlock now."
                : "Locks the keys for \(Int(controller.lockDuration)) seconds while you wipe the keyboard.")
        ToolTile(
            hint: clean, symbol: locked ? "lock.fill" : "keyboard", tint: IslandTheme.keepAwake,
            ringFraction: controller.lockProgress, hovered: $hovered
        ) { controller.toggleKeyboardLock() }
    }

    // The area under the tiles: what the tools just did.
    @ViewBuilder
    private var status: some View {
        if controller.keyboard == .locked {
            note("Keyboard locked. The trackpad still works. Press Esc three times, or click Unlock, to unlock early.")
        } else if controller.keyboard == .needsPermission {
            VStack(alignment: .leading, spacing: 8) {
                note("To lock the keyboard, Island needs Accessibility access. Turn it on for Island in System Settings, then try again.")
                HStack(spacing: 8) {
                    PillButton(title: "Open Settings", prominent: true, tint: IslandTheme.keepAwake) { controller.openAccessibilitySettings() }
                    PillButton(title: "Not now") { controller.dismissPermissionNotice() }
                }
            }
        } else if let color = controller.pickedColor {
            PickedColorBar(color: color, controller: controller)
        } else if let hint = hovered {
            VStack(alignment: .leading, spacing: 2) {
                Text(hint.title).font(.system(size: 12, weight: .semibold))
                Text(hint.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One tool: an icon in a ring (which counts down while the tool is running), in a square tile the size of a mascot tile.
/// Hovering it shows its name and what it does under the tiles.
struct ToolTile: View {
    let hint: ToolsTab.ToolHint
    let symbol: String
    let tint: Color
    let ringFraction: Double?
    @Binding var hovered: ToolsTab.ToolHint?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RingProgress(fraction: ringFraction, tint: tint, lineWidth: 2.5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)
            .frame(width: IslandMetrics.toolTile, height: IslandMetrics.toolTile)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(hint.title)
        .onHover { inside in
            if inside { hovered = hint } else if hovered?.title == hint.title { hovered = nil }
        }
    }
}

/// The colour that was picked: its swatch, its codes, and buttons to copy them.
struct PickedColorBar: View {
    let color: ToolsController.PickedColor
    let controller: ToolsController

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(color.hex).font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(color.rgb).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Button { controller.dismissColor() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            HStack(spacing: 8) {
                Text("Hex copied").font(.system(size: 10, weight: .medium)).foregroundStyle(IslandTheme.tasks)
                Spacer(minLength: 0)
                PillButton(title: "Copy RGB") { controller.copy(color.rgb) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
