import AppKit
import SwiftUI
import WebKit
import IslandCore

/// The Browser tab: a bar of buttons over the page, with the tab list (the sidebar) down the left when it is switched on.
/// Max mode (the arrows in the island's tab bar) gives the page most of the screen.
struct BrowserTab: View {
    @Bindable var controller: BrowserController

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if let message = controller.message { messageBar(message) }
            HStack(spacing: 8) {
                if controller.tabs.sidebarOpen { BrowserSidebar(controller: controller) }
                ZStack {
                    if controller.hasPage, let page = controller.selectedPage {
                        BrowserWebView(page: page)
                            .id(page.id)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if controller.isWaking {
                        // The page was asleep (to save memory) and is opening again.
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Opening…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        }
                    } else {
                        BrowserNewTabPage(controller: controller)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        // While this tab is not on screen (the island closed, or another tab chosen) its pages count down to sleep.
        .onAppear { controller.setVisible(true) }
        .onDisappear { controller.setVisible(false) }
        .task { controller.start() }
    }

    // MARK: The top

    private var toolbar: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                iconButton("sidebar.left", help: controller.tabs.sidebarOpen ? "Hide the tab list" : "Show the tab list", enabled: true, on: controller.tabs.sidebarOpen) {
                    controller.toggleSidebar()
                }
                iconButton("chevron.left", help: "Back", enabled: controller.canGoBack) { controller.goBack() }
                iconButton("chevron.right", help: "Forward", enabled: controller.canGoForward) { controller.goForward() }
                iconButton(controller.isLoading ? "xmark" : "arrow.clockwise", help: controller.isLoading ? "Stop" : "Reload", enabled: controller.hasPage) {
                    controller.reloadOrStop()
                }
                iconButton(
                    controller.isCurrentBookmarked ? "star.fill" : "star",
                    help: controller.isCurrentBookmarked ? "Remove this bookmark" : "Bookmark this page: a link on the new-tab page, never kept open",
                    enabled: controller.isCurrentBookmarked || controller.currentURL != nil, tint: controller.isCurrentBookmarked ? IslandTheme.pin : nil
                ) { controller.toggleBookmark() }

                HStack(spacing: 6) {
                    Image(systemName: lockSymbol).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    SearchField(
                        text: $controller.address, placeholder: "Search or type a web address",
                        focusesOnAppear: controller.wantsAddressFocus, focusRequest: controller.addressFocusRequest,
                        onSubmit: { controller.go(controller.address) },
                        onCancel: { controller.resetAddress() },
                        onEditingChanged: { controller.addressEditingChanged($0) })
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.white.opacity(0.1), in: Capsule())

                iconButton("arrow.up.right.square", help: "Open this page in your own browser", enabled: controller.currentURL != nil) {
                    controller.openInDefaultBrowser()
                }
                iconButton("plus", help: "New tab", enabled: true) { controller.newTab() }
                Menu {
                    Button("Open in your own browser") { controller.openInDefaultBrowser() }
                        .disabled(controller.currentURL == nil)
                    Button("Free memory now (put other tabs to sleep)") { Task { await controller.sleepOtherTabs() } }
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

    private func iconButton(_ symbol: String, help: String, enabled: Bool, on: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint ?? (on ? IslandTheme.accent : Color.white.opacity(enabled ? 0.85 : 0.3)))
                .frame(width: 28, height: 28)
                .background((on ? IslandTheme.accent.opacity(0.18) : Color.white.opacity(0.1)), in: Circle())
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
            Button { controller.dismissMessage() } label: {
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
}

// MARK: The tab list

/// The open tabs, down the left like Arc's sidebar, and "New tab". Bookmarks are not here: they are links on the new-tab page.
struct BrowserSidebar: View {
    let controller: BrowserController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.tabs.open) { BrowserTabRow(controller: controller, entry: $0).id($0.id) }
                    }
                }
                .scrollIndicators(.hidden)
                // The tab that is showing is never left below the fold.
                .onChange(of: controller.tabs.selected) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                }
                .onAppear { if let id = controller.tabs.selected { proxy.scrollTo(id) } }
            }
            Button { controller.newTab() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 18)
                    Text("New tab").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// An open tab. One that is asleep (to save memory) is a little dimmer; choosing it wakes it.
struct BrowserTabRow: View {
    let controller: BrowserController
    let entry: BrowserTabList.Entry
    @State private var hovering = false

    var body: some View {
        let selected = controller.tabs.selected == entry.id
        let title = controller.displayTitle(of: entry)
        let asleep = !controller.isAwake(entry.id) && entry.url != nil
        HStack(spacing: 8) {
            BrowserSiteBadge(name: title)
            Text(verbatim: title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(selected ? 0.95 : (asleep ? 0.5 : 0.85)))
                .lineLimit(1)
            Spacer(minLength: 0)
            if hovering {
                Button { controller.close(entry.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close this tab")
            } else if asleep {
                Image(systemName: "moon.zzz.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3)).help("Asleep to save memory. Choose it to wake it.")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.white.opacity(selected ? 0.16 : (hovering ? 0.08 : 0)), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { controller.select(entry.id) }
        .onHover { hovering = $0 }
        .contextMenu { Button("Close") { controller.close(entry.id) } }
    }
}

/// A small round badge with the site's first letter, in a colour that stays the same for the same name (no site icons yet).
struct BrowserSiteBadge: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.3))
            Text(verbatim: letter).font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }

    private var letter: String { name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "•" }

    private var color: Color {
        let palette: [Color] = [IslandTheme.link, IslandTheme.tasks, IslandTheme.focus, IslandTheme.swatch, IslandTheme.scan, IslandTheme.clipboard, IslandTheme.teams]
        // Not `hashValue`: that changes every launch.
        let sum = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}

// MARK: A blank tab

/// What a tab with no page shows: the bookmarks as buttons (one click opens one; none of them is open until then), or a
/// hint when there are none yet.
struct BrowserNewTabPage: View {
    let controller: BrowserController

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe").font(.system(size: 28)).foregroundStyle(IslandTheme.link)
            Text("New tab").font(.system(size: 14, weight: .semibold))
            if controller.tabs.bookmarks.isEmpty {
                Text("Type a web address above, like teams.microsoft.com or web.whatsapp.com.\nPress the star to bookmark a page: it shows up here as a link, and nothing is kept open or using memory until you click it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)], spacing: 8) {
                    ForEach(controller.tabs.bookmarks) { bookmark in
                        let title = bookmark.title.isEmpty ? (URL(string: bookmark.url)?.host ?? bookmark.url) : bookmark.title
                        Button { controller.openBookmark(bookmark.id) } label: {
                            HStack(spacing: 8) {
                                BrowserSiteBadge(name: title, size: 22)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(verbatim: URL(string: bookmark.url)?.host ?? "").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Remove bookmark") { controller.removeBookmark(bookmark.id) } }
                    }
                }
                .frame(maxWidth: 520)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hosts a page's web view. The view belongs to the page and is put into a fresh container each time the tab appears, so
/// SwiftUI never owns (or tears down) the web view itself.
struct BrowserWebView: NSViewRepresentable {
    let page: BrowserPage

    func makeNSView(context: Context) -> WebContainer {
        let container = WebContainer()
        container.host(page.makeWebView())
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
