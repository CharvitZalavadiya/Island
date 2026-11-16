import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IslandCore

/// App lock's settings, inside a `ToolPopup`: which apps ask, the password, and when they ask again. While the lock is on,
/// changing any of it first needs Touch ID or the password (otherwise anyone at the Mac could switch the lock off), and it asks
/// again every time this is closed.
struct AppLockSettings: View {
    let controller: AppLockController

    var body: some View {
        Group {
            if controller.needsUnlockForSettings {
                AppLockGate(controller: controller)
            } else if !controller.hasPassword {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a password. Apps you lock ask for it, or for Touch ID, every time you open them.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    SetPasswordForm(controller: controller, buttonTitle: "Save and turn on")
                        .frame(maxWidth: 300, alignment: .leading)
                }
            } else {
                AppLockMain(controller: controller)
            }
        }
        .onDisappear { controller.lockSettings() }
    }
}

/// "Show it is you": the password, Touch ID, or the Mac's own password (for someone who forgot the App lock one).
private struct AppLockGate: View {
    let controller: AppLockController
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App lock is on. Show it is you to change its settings.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 8) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(width: 190, height: 28)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit(submit)
                PillButton(title: "Unlock", prominent: true, tint: IslandTheme.appLock, height: 28, action: submit)
                if controller.touchIDOffered {
                    Button { controller.unlockSettingsWithTouchID() } label: {
                        Image(systemName: "touchid")
                            .font(.system(size: 16))
                            .foregroundStyle(IslandTheme.appLock)
                            .frame(width: 28, height: 28)
                            .background(IslandTheme.appLock.opacity(0.16), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Use Touch ID")
                }
            }
            if let message = controller.message {
                Text(message).font(.system(size: 11)).foregroundStyle(IslandTheme.danger)
            }
            HStack(spacing: 8) {
                PillButton(title: "Use Mac password") { controller.unlockSettingsWithMacPassword() }
                Text("Forgot the password? Your Mac's own password works too.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func submit() {
        let typed = password
        password = ""
        controller.unlockSettings(password: typed)
    }
}

/// Two boxes for a new password and a button to keep it.
private struct SetPasswordForm: View {
    let controller: AppLockController
    let buttonTitle: String
    var onSaved: () -> Void = {}
    @State private var first = ""
    @State private var second = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("New password", text: $first)
            field("Same password again", text: $second)
            HStack(spacing: 8) {
                PillButton(title: buttonTitle, prominent: true, tint: IslandTheme.appLock, action: save)
                if let problem {
                    Text(problem).font(.system(size: 10.5)).foregroundStyle(IslandTheme.danger).lineLimit(2)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .onSubmit(save)
    }

    private func save() {
        switch controller.setPassword(first, repeated: second) {
        case .saved:
            first = ""
            second = ""
            problem = nil
            onSaved()
        case .tooShort: problem = "Use at least \(AppLockPassword.minimumLength) characters."
        case .doesNotMatch: problem = "The two passwords are not the same."
        case .couldNotSave: problem = "Island could not save the password."
        case .locked: problem = "Unlock the settings first."
        }
    }
}

private struct AppLockMain: View {
    let controller: AppLockController
    @State private var changingPassword = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            apps
                .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 8) {
                if changingPassword {
                    SetPasswordForm(controller: controller, buttonTitle: "Save") { changingPassword = false }
                    PillButton(title: "Cancel") { changingPassword = false }
                } else {
                    relockMenu
                    if controller.touchIDAvailable {
                        Toggle("Touch ID", isOn: Binding(get: { controller.touchIDOffered }, set: { controller.setTouchID($0) }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(IslandTheme.appLock)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    PillButton(title: "Change password…") { changingPassword = true }
                    Text("Works only while Island runs. Quit Island and these apps open without a password.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 214, alignment: .leading)
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Locked apps").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                addMenu
            }
            if controller.lockedApps.isEmpty {
                Text("None yet. Add the apps that should ask for Touch ID or the password when you open them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(controller.lockedApps) { app in
                            AppRow(app: app) { controller.removeApp(app.id) }
                        }
                    }
                }
                .frame(maxHeight: 112)
            }
            if let message = controller.message {
                Text(message).font(.system(size: 10.5)).foregroundStyle(IslandTheme.danger)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            let candidates = controller.candidates()
            ForEach(candidates) { app in
                Button { controller.addApp(bundleID: app.id, name: app.name) } label: {
                    Label { Text(app.name) } icon: { Image(nsImage: AppIcons.icon(forBundleID: app.id)) }
                }
            }
            if !candidates.isEmpty { Divider() }
            Button("Other app…") { chooseApp() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text("Add app")
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(IslandTheme.appLock)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(IslandTheme.appLock.opacity(0.18), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var relockMenu: some View {
        Menu {
            ForEach(AppLockRelock.allCases, id: \.self) { choice in
                Button(choice.title) { controller.setRelock(choice) }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Ask again: \(controller.relock.title.lowercasedFirst)").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(IslandTheme.appLock)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(IslandTheme.appLock.opacity(0.18), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("How soon an app asks again after you opened it")
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to lock"
        panel.prompt = "Lock"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.level = IslandWindowLevel.dialog              // above the island, which may be a big card in focus mode
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { controller.addApp(at: url) }
    }
}

private struct AppRow: View {
    let app: AppLockController.App
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIcons.icon(forBundleID: app.id)).resizable().frame(width: 18, height: 18)
            Text(app.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop locking \(app.name)")
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension String {
    /// "Every time" → "every time", for use in the middle of a sentence.
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
