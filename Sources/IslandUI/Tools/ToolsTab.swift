import SwiftUI
import IslandCore

/// The Tools tab: the player down the whole left side, and the tools as small square tiles beside it, the same size as a
/// mascot tile in the Focus tab. Pick a colour from anywhere on the screen, lock the keyboard for half a minute while it
/// is wiped clean, and set up what sliding a finger along the trackpad's edges does.
struct ToolsTab: View {
    @Bindable var controller: ToolsController
    let nowPlaying: NowPlayingController
    let trackpad: TrackpadController
    let settings: SettingsStore
    /// The tool the pointer is over, so its name can be shown (the tiles are too small to carry one).
    @State private var hovered: ToolHint?
    /// The tool whose settings are open as a card over the tab, if any.
    @State private var popup: PopupTool?

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
        .overlay {
            if let popup {
                popupCard(for: popup)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: popup)
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

        // The tools that open a popup of settings (see `PopupTool`).
        ForEach(PopupTool.allCases, id: \.self) { tool in
            ToolTile(
                hint: ToolHint(title: tool.title, detail: tool.detail(isOn: isOn(tool))), symbol: tool.symbol, tint: tool.tint,
                ringFraction: nil, hovered: $hovered
            ) { popup = tool }
        }
    }

    private func isOn(_ tool: PopupTool) -> Bool {
        switch tool {
        case .trackpadSlide: trackpad.isEnabled
        case .trackpadTaps: trackpad.isTapsEnabled
        }
    }

    /// The card for a tool's settings: the same `ToolPopup` for every tool, with that tool's own settings inside it.
    @ViewBuilder
    private func popupCard(for tool: PopupTool) -> some View {
        switch tool {
        case .trackpadSlide:
            ToolPopup(
                title: tool.title, symbol: tool.symbol, tint: tool.tint,
                isOn: Binding(get: { trackpad.isEnabled }, set: { trackpad.setEnabled($0) }), onClose: { popup = nil }
            ) {
                TrackpadSlideSettings(controller: trackpad, settings: settings)
            }
        case .trackpadTaps:
            ToolPopup(
                title: tool.title, symbol: tool.symbol, tint: tool.tint,
                isOn: Binding(get: { trackpad.isTapsEnabled }, set: { trackpad.setTapsEnabled($0) }), onClose: { popup = nil }
            ) {
                TrackpadTapSettings(controller: trackpad, settings: settings)
            }
        }
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

/// The tools that open a popup of settings over the Tools tab, each with a tile of its own. To add one: add a case here, say what
/// it is called, looks like and does in the properties, and build its settings inside a `ToolPopup` in `popupCard(for:)`.
enum PopupTool: String, CaseIterable {
    case trackpadSlide, trackpadTaps

    var title: String {
        switch self {
        case .trackpadSlide: "Slide gestures"
        case .trackpadTaps: "Tap gestures"
        }
    }

    var symbol: String {
        switch self {
        case .trackpadSlide: "rectangle.and.hand.point.up.left"
        case .trackpadTaps: "hand.tap"
        }
    }

    /// Every tool has a colour of its own.
    var tint: Color {
        switch self {
        case .trackpadSlide: IslandTheme.trackpadSlide
        case .trackpadTaps: IslandTheme.trackpadTaps
        }
    }

    /// What it does, shown when the pointer is over its tile.
    func detail(isOn: Bool) -> String {
        switch self {
        case .trackpadSlide:
            isOn ? "On. Slide a finger along the trackpad's edge to change volume or brightness. Click to change it."
                : "Off. Click to set up sliding along the trackpad's edge for volume, brightness and skipping."
        case .trackpadTaps:
            isOn ? "On. Tap with three or four fingers, twice or three times. Click to choose what each tap does."
                : "Off. Click to set up taps with three or four fingers: copy, paste, screenshot, open an app and more."
        }
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
