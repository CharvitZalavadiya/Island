import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IslandCore

/// The Settings window, opened from the gear menu or by right-clicking the island.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let launchAtLogin: LaunchAtLoginController
    private let keepAwake: KeepAwakeViewModel
    private let update: UpdateController

    init(settings: SettingsStore, launchAtLogin: LaunchAtLoginController, keepAwake: KeepAwakeViewModel, update: UpdateController) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.keepAwake = keepAwake
        self.update = update
    }

    func show() {
        launchAtLogin.syncWithSystem()
        keepAwake.refreshPermission()
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: settings, launchAtLogin: launchAtLogin, keepAwake: keepAwake, update: update))
            let window = NSWindow(contentViewController: controller)
            window.title = "Island Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let settings: SettingsStore
    let launchAtLogin: LaunchAtLoginController
    let keepAwake: KeepAwakeViewModel
    let update: UpdateController
    /// The tab row being dragged right now (see `TabDropDelegate`).
    @State private var draggingTab: String?

    var body: some View {
        let current = settings.settings
        Form {
            Section("Island") {
                // On by default. On: the island opens when the pointer reaches the notch. Off: hovering does nothing
                // and one click on the notch opens it.
                Toggle("Hover to open", isOn: binding(\.hoverOpens))
                Text(
                    current.hoverOpens
                        ? "Move the pointer onto the notch and the island opens."
                        : "Hovering does nothing. Click the notch once to open the island."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                LabeledContent("Close delay") {
                    HStack {
                        Slider(value: binding(\.collapseDelay), in: 0.1...2, step: 0.1).frame(width: 160)
                        Text(String(format: "%.1f s", current.collapseDelay))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Minimal view") {
                Toggle("Show what's playing", isOn: binding(\.mediaInMinimalView))
                Text("While music or a video plays, the minimal view beside the notch shows the app's icon with the track's progress on the left, and a small equalizer on the right. Turn this off and Island stops watching what's playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sounds") {
                Toggle("Play a sound when the Mac locks and unlocks", isOn: binding(\.lockSounds))
                Text("A soft 0.2-second tone when the screen locks or the screen saver starts, and another when you unlock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tabs") {
                let order = TabOrder.normalized(saved: current.tabOrder, all: IslandTab.allCases.map(\.rawValue))
                // The tabs that are on. The last one that is on cannot be switched off: the island always has a tab.
                let on = Set(TabOrder.shown(order, hidden: current.hiddenTabs))
                ForEach(order, id: \.self) { id in
                    if let tab = IslandTab(rawValue: id) {
                        let isOn = on.contains(id)
                        HStack(spacing: 10) {
                            // The handle and the name are what is grabbed; the switch stays a switch.
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                    .help("Drag to change the order")
                                Label { Text(tab.title) } icon: { TabIcon(tab: tab).frame(width: 22) }
                            }
                            .opacity(isOn ? 1 : 0.5)
                            .contentShape(Rectangle())
                            .onDrag {
                                draggingTab = id
                                return NSItemProvider(object: id as NSString)
                            }
                            Spacer()
                            Toggle(tab.title, isOn: tabSwitch(id, order: order))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(isOn && on.count == 1)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TabDropDelegate(target: id, dragging: $draggingTab, order: order) { newOrder in
                                withAnimation(.snappy(duration: 0.2)) { settings.update { $0.tabOrder = newOrder } }
                            })
                    }
                }
                Text("Switch a tab off to take it out of the island, and back on to bring it back. Drag a row by its handle to change the order. At least one tab stays on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to the default order") { settings.update { $0.tabOrder = [] } }
                    .disabled(current.tabOrder.isEmpty)
            }

            Section("Pomodoro") {
                Stepper(
                    "Long break after every \(current.longBreakEvery) focus sessions",
                    value: binding(\.longBreakEvery), in: 2...10)
                Toggle("Start the next session automatically", isOn: binding(\.autoChain))
                Text("Session lengths and the mascot are set on the Focus tab itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keep awake") {
                HStack {
                    Text("Permission to change the sleep setting")
                    Spacer()
                    Text(keepAwake.permission == .granted ? "Allowed" : "Not allowed")
                        .foregroundStyle(keepAwake.permission == .granted ? IslandTheme.accent : Color.secondary)
                    if keepAwake.permission == .granted {
                        Button("Remove…") { Task { await keepAwake.revokePermission() } }
                            .disabled(keepAwake.isWorking)
                    } else {
                        Button("Allow…") { Task { await keepAwake.grantPermission() } }
                            .disabled(keepAwake.isWorking)
                    }
                }
                Text("This lets Island switch your Mac's sleep setting on and off without asking for a password each time, and nothing else. macOS asks for your password when you allow or remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = keepAwake.message {
                    Text(message).font(.caption).foregroundStyle(IslandTheme.accent)
                }
            }

            UpdateSettingsSection(update: update, settings: settings)

            Section("General") {
                Toggle(
                    "Open Island when I log in",
                    isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.setOn($0) }))
                if let message = launchAtLogin.message {
                    Text(message).font(.caption).foregroundStyle(IslandTheme.accent)
                }
                Button("Quit Island") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 780)
    }

    /// The switch for one tab: on unless the tab is in the settings' list of switched-off tabs. Saved the moment it changes.
    private func tabSwitch(_ id: String, order: [String]) -> Binding<Bool> {
        Binding(
            get: { TabOrder.shown(order, hidden: settings.settings.hiddenTabs).contains(id) },
            set: { isOn in
                settings.update {
                    $0.hiddenTabs = TabOrder.settingShown(isOn, id: id, hidden: $0.hiddenTabs, all: IslandTab.allCases.map(\.rawValue))
                }
            })
    }

    /// A binding that saves to the settings the moment it changes.
    private func binding<Value>(_ keyPath: WritableKeyPath<IslandCore.Settings, Value>) -> Binding<Value> {
        Binding(
            get: { settings.settings[keyPath: keyPath] },
            set: { newValue in settings.update { $0[keyPath: keyPath] = newValue } })
    }
}

/// Reorders the tab rows while one is dragged over another: the dragged row takes the place of the row it is over, at once,
/// so the rows slide as it moves. The order is saved with every move, so letting go anywhere leaves it where it was dropped.
private struct TabDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let order: [String]
    let save: ([String]) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil && info.hasItemsConforming(to: [UTType.text]) }

    func dropEntered(info: DropInfo) {
        guard let dragging, info.hasItemsConforming(to: [UTType.text]) else { return }
        let moved = TabOrder.moved(order, id: dragging, to: target)
        if moved != order { save(moved) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
