import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IslandCore

/// What tapping the trackpad with three or four fingers, twice or three times, does: four cards to choose a tap from, and what
/// the chosen one does. Every tap is lit up on its card as it is noticed. Shown inside a `ToolPopup`.
struct TrackpadTapSettings: View {
    let controller: TrackpadController
    let settings: SettingsStore

    var body: some View {
        TapsPage(controller: controller, settings: settings.settings)
            // Every tap is followed (so it can be shown) only while this is open.
            .onAppear { controller.setTapPreviewing(true) }
            .onDisappear { controller.setTapPreviewing(false) }
    }
}

private struct TapsPage: View {
    let controller: TrackpadController
    let settings: IslandCore.Settings
    @State private var selected = TrackpadTapTrigger.all[0]
    /// The tap that was just noticed, lit up for a moment.
    @State private var flashed: TrackpadTapTrigger?

    private static let groups: [[TrackpadTapAction]] = [
        [.none], [.copy, .paste], [.screenshot, .missionControl, .openApp, .shortcut],
        [.lockScreen, .screenSaver, .displaySleep], [.mute, .playPause],
    ]

    var body: some View {
        let action = settings.trackpadTapAction(for: selected)
        HStack(alignment: .top, spacing: 16) {
            cards
                .frame(width: 214)
            VStack(alignment: .leading, spacing: 7) {
                Text(selected.title).font(.system(size: 12, weight: .semibold))
                actionMenu(action)
                detail(action)
                Text(Self.hint(action))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if selected.fingers == 3, controller.systemThreeFingerTapIsOn {
                    Text("macOS also uses a three-finger tap (to look a word up). Turn that off in System Settings ▸ Trackpad.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(IslandTheme.keepAwake)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await controller.loadShortcuts() }
        .onChange(of: controller.lastTap) { _, tap in
            guard let tap else { return }
            selected = tap.trigger
            withAnimation(.easeOut(duration: 0.1)) { flashed = tap.trigger }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.easeOut(duration: 0.25)) { if flashed == tap.trigger { flashed = nil } }
            }
        }
    }

    /// Two rows (three fingers, four) of two cards (double tap, triple tap).
    private var cards: some View {
        VStack(spacing: 6) {
            ForEach([3, 4], id: \.self) { fingers in
                HStack(spacing: 6) {
                    ForEach([2, 3], id: \.self) { taps in
                        let trigger = TrackpadTapTrigger(fingers: fingers, taps: taps)
                        TapCard(
                            trigger: trigger, action: settings.trackpadTapAction(for: trigger), isSelected: trigger == selected,
                            isFlashed: flashed == trigger
                        ) { selected = trigger }
                    }
                }
            }
        }
    }

    private func actionMenu(_ action: TrackpadTapAction) -> some View {
        Menu {
            ForEach(Self.groups.indices, id: \.self) { index in
                if index > 0 { Divider() }
                ForEach(Self.groups[index], id: \.self) { choice in
                    Button { controller.setTapAction(choice, for: selected) } label: { Label(choice.title, systemImage: choice.symbol) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.symbol)
                Text(action.title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(IslandTheme.trackpadTaps)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(IslandTheme.trackpadTaps.opacity(0.18), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose what this tap does")
    }

    /// What the chosen action still needs: an app, a Shortcut, or a permission.
    @ViewBuilder
    private func detail(_ action: TrackpadTapAction) -> some View {
        switch action {
        case .openApp:
            let path = settings.trackpadTapApp(for: selected)
            Button { chooseApp() } label: {
                HStack(spacing: 6) {
                    if let path { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 16, height: 16) }
                    Text(path.map { ($0 as NSString).deletingPathExtension.components(separatedBy: "/").last ?? $0 } ?? "Choose an app…")
                        .lineLimit(1)
                }
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.white.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
        case .shortcut:
            if controller.shortcutNames.isEmpty {
                Text("No Shortcuts found. Make one in the Shortcuts app.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            } else {
                Menu {
                    ForEach(controller.shortcutNames, id: \.self) { name in
                        Button(name) { controller.setTapShortcut(name, for: selected) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(settings.trackpadTapShortcut(for: selected) ?? "Choose a Shortcut…").lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        case .copy, .paste:
            if controller.hasAccessibility {
                Label("Island is allowed to press keys", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(IslandTheme.tasks)
            } else {
                Button { controller.requestAccessibility() } label: {
                    Label("Allow in Accessibility…", systemImage: "lock.shield")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(IslandTheme.keepAwake.opacity(0.2), in: Capsule())
                        .foregroundStyle(IslandTheme.keepAwake)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        default:
            EmptyView()
        }
    }

    private static func hint(_ action: TrackpadTapAction) -> String {
        switch action {
        case .none: "Tap with three or four fingers, two or three times in a row, quickly. Choose what it does."
        case .copy: "Presses ⌘C in the app you are using. macOS asks you to allow this once."
        case .paste: "Presses ⌘V in the app you are using. macOS asks you to allow this once."
        case .screenshot: "Opens the screenshot tools (the same as ⇧⌘5)."
        case .missionControl: "Shows all your windows and spaces."
        case .openApp: "Opens the app, or brings it to the front."
        case .shortcut: "Runs one of your Shortcuts. A Shortcut with “Set Focus” turns Do Not Disturb on or off."
        case .lockScreen: "Locks the screen at once."
        case .screenSaver: "Starts the screen saver."
        case .displaySleep: "Turns the display off until you touch something."
        case .mute: "Mutes the sound, or unmutes it."
        case .playPause: "Pauses or plays whatever is playing."
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to open"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { controller.setTapApp(url.path, for: selected) }
    }
}

private struct TapCard: View {
    let trigger: TrackpadTapTrigger
    let action: TrackpadTapAction
    let isSelected: Bool
    let isFlashed: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(0..<trigger.fingers, id: \.self) { _ in
                        Circle().fill(isFlashed ? IslandTheme.accent : Color.white.opacity(0.75)).frame(width: 7, height: 7)
                    }
                }
                Text(trigger.tapsTitle).font(.system(size: 11, weight: .semibold))
                HStack(spacing: 3) {
                    Image(systemName: action.symbol).font(.system(size: 9.5, weight: .semibold))
                    Text(action.shortTitle).font(.system(size: 10.5)).lineLimit(1)
                }
                .foregroundStyle(action == .none ? Color.white.opacity(0.4) : IslandTheme.trackpadTaps)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(isFlashed ? IslandTheme.accent.opacity(0.35) : Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.white : Color.white.opacity(0.14), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .frame(height: 76)
        .help(trigger.title)
    }
}

