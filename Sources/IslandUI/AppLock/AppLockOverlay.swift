import AppKit
import SwiftUI
import IslandCore

/// One window of the cover: opaque, over the locked app, and able to take the keyboard (for the password).
final class LockPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = IslandWindowLevel.lock
        // Over a full-screen app and on every Space, the way the island is.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = true
        backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 1)
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The cover on the screen: a `LockPanel` over each screen the locked app is on, with the box to type in on one of them. It
/// owns nothing but these windows (and the Esc key while it shows), and `hide` removes all of it.
@MainActor
final class LockOverlay: AppLockPresenting {
    private var panels: [(frame: CGRect, panel: LockPanel)] = []
    private var cardFrame: CGRect?
    private weak var controller: AppLockController?
    private var keyMonitor: Any?

    var isShowing: Bool { panels.contains { $0.panel.isVisible } }

    func attach(_ controller: AppLockController) { self.controller = controller }

    func show(covering covered: [CGRect], card: CGRect) {
        guard let controller, !covered.isEmpty else { return }
        // Showing again for the same thing (the locked app was clicked again) keeps the windows, and so what was typed.
        if !(isShowing && covered == panels.map(\.frame) && card == cardFrame) {
            removePanels()
            cardFrame = card
            for frame in covered {
                let panel = LockPanel(frame: frame)
                panel.contentView = NSHostingView(rootView: LockCoverView(controller: controller, showsCard: frame == card))
                panels.append((frame, panel))
            }
        }
        NSApp.activate()
        for entry in panels where entry.frame != card { entry.panel.orderFrontRegardless() }
        (panels.first { $0.frame == card } ?? panels.first)?.panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        removePanels()
    }

    private func removePanels() {
        for entry in panels {
            entry.panel.orderOut(nil)
            entry.panel.contentView = nil
            entry.panel.close()
        }
        panels = []
        cardFrame = nil
    }

    /// Esc is "Not now": a plain Escape, typed into the cover itself.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                    self.panels.contains(where: { $0.panel === event.window })
                else { return false }
                self.controller?.notNow()
                return true
            }
            return consumed ? nil : event
        }
    }
}

/// What one window of the cover shows: the box to type in on one screen, and just a lock on the others.
struct LockCoverView: View {
    let controller: AppLockController
    let showsCard: Bool

    var body: some View {
        ZStack {
            Color(white: 0.05)
            if showsCard {
                LockCardView(controller: controller)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 30, weight: .semibold))
                    Text("\(controller.request?.name ?? "This app") is locked").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The box that asks: the app, a password field, Touch ID, and the ways out ("Not now", the Mac's own password, "Quit Island").
struct LockCardView: View {
    let controller: AppLockController
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            if let request = controller.request {
                Image(nsImage: AppIcons.icon(forBundleID: request.bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                Text("\(request.name) is locked").font(.system(size: 17, weight: .semibold))
            }
            Text(controller.isUsingTouchID ? "Touch the sensor, or type the password." : "Type the password to open it.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            passwordRow
            if let message = controller.message {
                Text(message)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(IslandTheme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                PillButton(title: "Use Mac password") { controller.useMacPassword() }
                PillButton(title: "Not now") { controller.notNow() }
            }
            .padding(.top, 2)
            Button { controller.quitIsland() } label: {
                Text("Quit Island").font(.system(size: 11)).underline().foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("The lock only works while Island runs. Quitting Island opens every app without a password.")
            Text("Quitting Island turns the lock off.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(24)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(.white)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: controller.request) { _, _ in password = "" }
    }

    private var passwordRow: some View {
        HStack(spacing: 8) {
            SecureField("Password", text: $password)
                .textFieldStyle(.plain)
                .focused($focused)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit(submit)
            PillButton(title: "Open", prominent: true, tint: IslandTheme.appLock, height: 30, action: submit)
            if controller.touchIDOffered {
                Button { controller.tryTouchID() } label: {
                    Image(systemName: "touchid")
                        .font(.system(size: 17))
                        .foregroundStyle(IslandTheme.appLock)
                        .frame(width: 30, height: 30)
                        .background(IslandTheme.appLock.opacity(0.16), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Use Touch ID")
            }
        }
    }

    private func submit() {
        let typed = password
        password = ""
        controller.submitPassword(typed)
        focused = true
    }
}

enum AppIcons {
    /// The icon of an app, by its identifier; a plain app icon when it is not installed.
    @MainActor
    static func icon(forBundleID id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}
