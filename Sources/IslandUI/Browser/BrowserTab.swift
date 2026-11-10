import AppKit
import SwiftUI
import WebKit
import IslandCore

/// The Browser tab (a prototype): an address bar over one web page, kept signed in. Max mode (the arrows button in the tab
/// bar, or here) gives the page most of the screen.
struct BrowserTab: View {
    @Bindable var controller: BrowserController
    let model: IslandModel

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if let message = controller.message { messageBar(message) }
            ZStack {
                if controller.hasPage {
                    BrowserWebView(controller: controller)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    startHint
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .task { controller.start() }
    }

    // MARK: The top

    private var toolbar: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                iconButton("chevron.left", help: "Back", enabled: controller.canGoBack) { controller.goBack() }
                iconButton("chevron.right", help: "Forward", enabled: controller.canGoForward) { controller.goForward() }
                iconButton(controller.isLoading ? "xmark" : "arrow.clockwise", help: controller.isLoading ? "Stop" : "Reload", enabled: controller.hasPage) {
                    controller.reloadOrStop()
                }

                HStack(spacing: 6) {
                    Image(systemName: lockSymbol).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    SearchField(
                        text: $controller.address, placeholder: "Search or type a web address",
                        focusesOnAppear: !controller.hasPage,
                        onSubmit: { controller.go(controller.address) },
                        onCancel: { controller.resetAddress() })
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.white.opacity(0.1), in: Capsule())

                iconButton("arrow.up.right.square", help: "Open this page in your own browser", enabled: controller.currentURL != nil) {
                    controller.openInDefaultBrowser()
                }
                iconButton(
                    model.isMax ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: model.isMax ? "Back to the usual size" : "Max: give the page most of the screen", enabled: true
                ) { model.isMax.toggle() }
                Menu {
                    Button("Open in your own browser") { controller.openInDefaultBrowser() }
                        .disabled(controller.currentURL == nil)
                    Divider()
                    Button("Sign out of all sites and clear data…", role: .destructive) { Task { await controller.clearWebsiteData() } }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Browser options")
            }
            // A thin line under the bar while a page loads.
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule().fill(IslandTheme.link).frame(width: geometry.size.width * max(0.04, controller.progress))
                    }
                    .opacity(controller.isLoading ? 1 : 0)
                }
        }
    }

    private var lockSymbol: String {
        controller.currentURL?.scheme == "https" ? "lock.fill" : (controller.currentURL == nil ? "globe" : "exclamationmark.triangle")
    }

    private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.3))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func messageBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IslandTheme.keepAwake)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { controller.message = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(IslandTheme.keepAwake.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var startHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe").font(.system(size: 30)).foregroundStyle(IslandTheme.link)
            Text("Type a web address above").font(.system(size: 14, weight: .semibold))
            Text("Try teams.microsoft.com or web.whatsapp.com. You sign in once and stay signed in.\nFor room to read, press the arrows button for Max.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hosts the controller's one web view. The view is kept by the controller and put into a fresh container each time the
/// tab appears, so SwiftUI never owns (or tears down) the web view itself.
struct BrowserWebView: NSViewRepresentable {
    let controller: BrowserController

    func makeNSView(context: Context) -> WebContainer {
        let container = WebContainer()
        container.host(controller.ensureWebView())
        return container
    }

    func updateNSView(_ container: WebContainer, context: Context) {}

    final class WebContainer: NSView {
        func host(_ view: NSView) {
            view.removeFromSuperview()
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }
}
