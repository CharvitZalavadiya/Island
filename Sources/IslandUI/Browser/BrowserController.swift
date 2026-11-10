import AppKit
import Foundation
import Observation
import WebKit
import IslandCore

/// What the Browser tab keeps between launches: its tabs, its bookmarks, the selected tab, and whether the sidebar is
/// showing. Addresses are kept without anything that looks like a secret (`BrowserAddress.kept`).
struct BrowserState: Codable, Equatable {
    var tabs: BrowserTabList?
    /// From the first version, which had one page and no tabs: becomes the first tab once.
    var lastAddress: String?
    /// Whether ads are blocked. On unless it was switched off.
    var adBlock: Bool?

    init(tabs: BrowserTabList? = nil, lastAddress: String? = nil, adBlock: Bool? = nil) {
        self.tabs = tabs
        self.lastAddress = lastAddress
        self.adBlock = adBlock
    }
}

/// A web view that takes the keyboard when it is clicked. The island is a panel that does not activate the app, and a
/// page cannot be typed into until the app is active and the panel is the key window.
final class IslandWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        takeKeyboard()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        takeKeyboard()
        super.rightMouseDown(with: event)
    }

    private func takeKeyboard() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
    }
}

// MARK: One tab's page

/// One tab's live page. The web view is only made when the tab is first shown or loaded, and dropped when the tab is closed
/// or put to sleep: a tab that is not being looked at costs nothing.
@Observable
@MainActor
final class BrowserPage: Identifiable {
    let id: UUID
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// A page was asked for and is on its way (until then the tab shows the new-tab page).
    private(set) var showsWeb = false
    /// A page was asked for but has not been started yet: it waits for the ad-blocking rules (a moment, the first time after
    /// launch). Until they are ready there is no web view at all, so the page can never load without them.
    private(set) var pendingURL: URL?
    var isOpening: Bool { pendingURL != nil }
    var message: String?

    @ObservationIgnored private(set) var webView: IslandWebView?
    @ObservationIgnored fileprivate weak var owner: BrowserController?
    @ObservationIgnored private var coordinator: Coordinator?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    fileprivate init(id: UUID, title: String, owner: BrowserController) {
        self.id = id
        self.title = title
        self.owner = owner
    }

    /// What the sidebar calls the tab: the page's title, else its site, else "New tab".
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return url?.host ?? "New tab"
    }

    /// Makes the web view (once). A page opened by another page (a popup) is made with the configuration WebKit gives it.
    @discardableResult
    func makeWebView(configuration given: WKWebViewConfiguration? = nil) -> IslandWebView {
        if let webView { return webView }
        let configuration = given ?? WKWebViewConfiguration()
        if given == nil, let store = owner?.dataStore { configuration.websiteDataStore = store }
        owner?.installBlocking(on: configuration.userContentController)
        let view = IslandWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = BrowserController.userAgent
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        let coordinator = Coordinator(page: self)
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        self.coordinator = coordinator
        observations = [
            view.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.title = view.title ?? "" } },
            view.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.urlChanged(view.url) } },
            view.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            view.observe(\.estimatedProgress) { [weak self] view, _ in MainActor.assumeIsolated { self?.progress = view.estimatedProgress } },
            view.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            view.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } },
        ]
        webView = view
        return view
    }

    func load(_ url: URL) {
        guard let owner, owner.isPreparingBlocker else {
            pendingURL = nil
            showsWeb = true
            makeWebView().load(URLRequest(url: url))
            return
        }
        // The web view is not made (and the tab does not show it) until the rules are ready: a view made earlier would load
        // the page with no ad blocking. If a second address is asked for meanwhile, the latest one wins.
        pendingURL = url
        owner.afterBlockerReady { [weak self] in
            guard let self, let target = self.pendingURL else { return }   // closed, sent home, or already started
            self.pendingURL = nil
            self.showsWeb = true
            self.makeWebView().load(URLRequest(url: target))
        }
    }

    /// This page is the target of a popup: WebKit loads into it by itself.
    fileprivate func markAsPopup() { showsWeb = true }

    /// Lets go of the page (and, with the last page, WebKit's process for it). Back to the new-tab look.
    func teardown() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        observations = []
        webView = nil
        coordinator = nil
        pendingURL = nil
        url = nil
        isLoading = false
        progress = 0
        canGoBack = false
        canGoForward = false
        showsWeb = false
        message = nil
    }

    private func urlChanged(_ new: URL?) {
        url = new
        owner?.pageAddressChanged(self)
    }

    fileprivate func failed(_ error: Error) {
        let nsError = error as NSError
        // A page that was stopped, or that this tab itself handed to another app, is not a failure.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        message = "Couldn't open this page. \(nsError.localizedDescription)"
    }

    // MARK: The web view's delegates (one per page)

    private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var page: BrowserPage?

        init(page: BrowserPage) {
            self.page = page
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            let decision = BrowserPolicy.navigation(
                to: url, isLinkClick: navigationAction.navigationType == .linkActivated,
                commandHeld: navigationAction.modifierFlags.contains(.command),
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                wantsDownload: navigationAction.shouldPerformDownload)
            switch decision {
            case .allow:
                decisionHandler(.allow)
            case .openElsewhere:
                if let url { page?.owner?.handOver(url) }
                decisionHandler(.cancel)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
            let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
            if navigationResponse.isForMainFrame,
               BrowserPolicy.opensElsewhere(canShow: navigationResponse.canShowMIMEType, contentDisposition: disposition),
               let url = navigationResponse.response.url {
                page?.owner?.handOver(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let page else { return }
            page.message = nil
            page.owner?.pageFinished(page)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { page?.failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { page?.failed(error) }

        /// A link or script that wants a new window (target="_blank", window.open, a sign-in popup) gets a new tab. The
        /// new view is made with the configuration WebKit hands over, which keeps the link between the two pages that
        /// sign-in popups rely on.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let page, let owner = page.owner else { return nil }
            return owner.openPopup(from: page, configuration: configuration)
        }

        /// The page closed its own window (window.close(), the end of a sign-in popup).
        func webViewDidClose(_ webView: WKWebView) {
            guard let page else { return }
            page.owner?.close(page.id)
        }

        // Pages ask questions with alert(), confirm() and prompt(); without these they get no answer at all.
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
            let alert = NSAlert()
            alert.messageText = frame.request.url?.host ?? "This page says"
            alert.informativeText = message
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = frame.request.url?.host ?? "This page asks"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = frame.request.url?.host ?? "This page asks"
            alert.informativeText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.stringValue = defaultText ?? ""
            alert.accessoryView = field
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
        }

        /// "Attach a file" on a page (Teams, for one).
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.begin { response in
                MainActor.assumeIsolated { completionHandler(response == .OK ? panel.urls : nil) }
            }
        }
    }
}

// MARK: The tab

/// The Browser tab: web pages inside the island, in tabs, signed in the way a normal browser is (logins are kept between
/// launches, separately from the person's own browser). Meant for sites like Teams and WhatsApp on the web.
///
/// Built to be light: a page costs memory (Teams on the web is well over a gigabyte), so
/// - a page is only made when its tab is shown, and a page nobody is looking at (another tab, or the island closed or on
///   another tab) is put to sleep after `sleepAfter` seconds: its web view is thrown away and the tab reopens at the same
///   address when it is chosen again (a page that is playing sound or video is left alone);
/// - bookmarks are plain links on the new-tab page (there are no pinned tabs), never open until clicked.
///
/// - Tabs are listed down the left side (the sidebar, off at first).
/// - The address bar shows the page the tab is on, not what was typed, unless it is being typed in right now.
/// - Links to other kinds of address and files to download are handed to the app that handles them; Command-click on a
///   link opens it in the person's own browser; a new window (target="_blank", a sign-in popup) opens as a new tab.
@Observable
@MainActor
final class BrowserController {
    /// What the address bar shows and the person edits.
    var address = ""
    /// The person has typed in the address bar and not yet pressed Return, Escape or left it.
    private(set) var isEditingAddress = false
    /// Changes when a new tab asks for the address bar to take the keyboard.
    private(set) var addressFocusRequest = 0
    private(set) var tabs: BrowserTabList

    @ObservationIgnored private let injectedDataStore: WKWebsiteDataStore?
    // Ad blocking.
    @ObservationIgnored private let adBlocker: BrowserAdBlocker?
    @ObservationIgnored private var blockerStarted = false
    @ObservationIgnored private var blockerReady = false
    @ObservationIgnored private var waitingForBlocker: [() -> Void] = []
    /// Whether ads are blocked (the person's choice, and a blocker exists).
    private(set) var adBlockEnabled: Bool
    @ObservationIgnored private var pages: [UUID: BrowserPage] = [:]
    @ObservationIgnored private let store: FileStore<BrowserState>
    @ObservationIgnored private let openElsewhere: (URL) -> Void
    // Putting idle pages to sleep.
    @ObservationIgnored let sleepAfter: TimeInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastWatched: [UUID: Date] = [:]
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var sleepTimer: Timer?

    /// WebKit's store of cookies and logins. Asked for only when the first page is made, so nothing of WebKit exists until then.
    fileprivate var dataStore: WKWebsiteDataStore { injectedDataStore ?? .default() }

    /// A recent Safari: some sites (WhatsApp Web among them) turn away a web view that does not say who it is.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    /// How long a page can go unwatched before it is put to sleep.
    nonisolated static let defaultSleepAfter: TimeInterval = 120

    init(
        store: FileStore<BrowserState>, dataStore: WKWebsiteDataStore? = nil, adBlocker: BrowserAdBlocker? = nil,
        sleepAfter: TimeInterval = BrowserController.defaultSleepAfter,
        now: @escaping () -> Date = { Date() }, openElsewhere: @escaping (URL) -> Void = { url in _ = NSWorkspace.shared.open(url) }
    ) {
        self.store = store
        self.injectedDataStore = dataStore
        self.adBlocker = adBlocker
        self.sleepAfter = sleepAfter
        self.now = now
        self.openElsewhere = openElsewhere
        let saved = store.load()
        adBlockEnabled = adBlocker != nil && (saved.adBlock ?? true)
        var list = saved.tabs ?? BrowserTabList.fresh(url: saved.lastAddress)
        list.repair()
        tabs = list
    }

    // MARK: What the tab shows (the selected tab's page)

    var selectedPage: BrowserPage? { tabs.selected.flatMap { pages[$0] } }
    var webView: IslandWebView? { selectedPage?.webView }
    var title: String { selectedPage?.title ?? "" }
    var currentURL: URL? { selectedPage?.url }
    var isLoading: Bool { selectedPage?.isLoading ?? false }
    var progress: Double { selectedPage?.progress ?? 0 }
    var canGoBack: Bool { selectedPage?.canGoBack ?? false }
    var canGoForward: Bool { selectedPage?.canGoForward ?? false }
    /// The selected tab shows a page (otherwise the new-tab page shows).
    var hasPage: Bool { selectedPage?.showsWeb ?? false }
    /// The selected tab has somewhere to be but its page is not up yet (it was asleep, or the island has just opened).
    var isWaking: Bool { (!hasPage && tabs.selectedEntry?.url != nil) || (selectedPage?.isOpening ?? false) }

    /// Whether the page being shown is bookmarked (the star is filled).
    var isCurrentBookmarked: Bool {
        guard let url = currentURL, let kept = BrowserAddress.kept(url) else { return false }
        return tabs.bookmark(for: kept) != nil
    }

    /// A problem to show: the selected page's (it could not be opened), else a general one (an address that is refused).
    var message: String? { selectedPage?.message ?? generalMessage }
    private(set) var generalMessage: String?

    func dismissMessage() {
        generalMessage = nil
        selectedPage?.message = nil
    }

    /// The address bar takes the keyboard by itself on a tab that is blank and has nothing to open.
    var wantsAddressFocus: Bool { !hasPage && tabs.selectedEntry?.url == nil && !(selectedPage?.isOpening ?? false) }

    /// What a tab is called in the sidebar, awake or asleep.
    func displayTitle(of entry: BrowserTabList.Entry) -> String {
        if let page = pages[entry.id], page.showsWeb { return page.displayTitle }
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return entry.url.flatMap { URL(string: $0)?.host } ?? "New tab"
    }

    /// The tab has a live page (as opposed to being blank, or asleep).
    func isAwake(_ id: UUID) -> Bool { pages[id]?.showsWeb ?? false }

    // MARK: The tab appears and goes

    /// The tab is on screen: make the selected tab's page if it has none (the first time after launch, or after it slept).
    func start() {
        ensureSelectedLoaded()
        if address.isEmpty || !isEditingAddress { resetAddress() }
    }

    /// The Browser tab came on screen or left it (the island closed, or another island tab was chosen). While it is away its
    /// pages start their countdown to sleep.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        if let id = tabs.selected { lastWatched[id] = now() }
        scheduleSleepCheck()
    }

    private func ensureSelectedLoaded() {
        guard let id = tabs.selected, let entry = tabs.entry(id) else { return }
        let page = pages[id] ?? makePage(id: id, title: entry.title)
        if !page.showsWeb, let saved = entry.url, let url = URL(string: saved) {
            page.load(url)
            lastWatched[id] = now()
            scheduleSleepCheck()
        }
    }

    private func makePage(id: UUID, title: String = "") -> BrowserPage {
        let page = BrowserPage(id: id, title: title, owner: self)
        pages[id] = page
        return page
    }

    // MARK: Going places

    /// Opens what was typed in the address bar (a web address, or words to search for) in the selected tab.
    func go(_ text: String) {
        switch BrowserAddress.resolve(text) {
        case .empty:
            return
        case .unsupported:
            generalMessage = "This browser opens web addresses (http and https). Use your own browser for anything else."
        case .page(let url), .search(let url):
            generalMessage = nil
            isEditingAddress = false
            let page = selectedPage ?? makePage(id: tabs.selected ?? tabs.addOpen())
            page.message = nil
            page.load(url)
            if let id = tabs.selected { lastWatched[id] = now() }
            scheduleSleepCheck()
            address = url.absoluteString
            save()
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func reloadOrStop() {
        guard let webView else { return }
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func openInDefaultBrowser() {
        if let url = currentURL { openElsewhere(url) }
    }

    /// Signs out of every site and forgets everything the sites stored (cookies, logins, caches).
    func clearWebsiteData() async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        webView?.reload()
    }

    // MARK: The address bar

    /// The person is typing in it (or has stopped without pressing Return).
    func addressEditingChanged(_ editing: Bool) {
        isEditingAddress = editing
        if !editing { resetAddress() }
    }

    /// Puts the page's address back in the bar (after Escape, leaving it, or switching tab).
    func resetAddress() {
        isEditingAddress = false
        address = currentURL?.absoluteString ?? ""
    }

    fileprivate func pageAddressChanged(_ page: BrowserPage) {
        guard page.id == tabs.selected, !isEditingAddress else { return }
        address = page.url?.absoluteString ?? ""
    }

    // MARK: Tabs

    func select(_ id: UUID) {
        guard tabs.entry(id) != nil, id != tabs.selected else { return }
        let previous = tabs.selected
        if let previous { lastWatched[previous] = now() }
        tabs.select(id)
        // Leaving a tab that is blank and was never used drops it, so a stray "New tab" does not pile up in the sidebar.
        if let previous, tabs.entry(previous)?.url == nil, !isAwake(previous) {
            tabs.close(previous)
            pages[previous]?.teardown()
            pages[previous] = nil
        }
        ensureSelectedLoaded()
        resetAddress()
        if wantsAddressFocus { addressFocusRequest += 1 }
        save()
    }

    /// A new blank tab, next to the one it was opened from, with the address bar ready to type in.
    func newTab() {
        if let previous = tabs.selected { lastWatched[previous] = now() }
        tabs.addOpen(after: tabs.selected)
        if let id = tabs.selected { _ = makePage(id: id) }
        address = ""
        isEditingAddress = false
        addressFocusRequest += 1
        save()
    }

    /// Closes a tab. If it was the selected one the neighbour is selected, or a blank tab if that was the last.
    func close(_ id: UUID) {
        let wasSelected = tabs.selected == id
        guard tabs.close(id) else { return }
        pages[id]?.teardown()
        pages[id] = nil
        lastWatched[id] = nil
        if wasSelected {
            ensureSelectedLoaded()
            resetAddress()
            if wantsAddressFocus { addressFocusRequest += 1 }
        }
        save()
    }

    /// Home: the current tab goes back to the new-tab page (its page is let go, so it costs nothing), with the address bar
    /// ready. A tab that is already blank stays as it is. The page it was on is not kept in this tab: "+" opens a new tab
    /// instead and leaves the page alone.
    func goHome() {
        guard let id = tabs.selected, hasPage || isWaking else { return }
        pages[id]?.teardown()
        pages[id] = nil
        lastWatched[id] = nil
        tabs.clear(id)
        generalMessage = nil
        address = ""
        isEditingAddress = false
        addressFocusRequest += 1
        scheduleSleepCheck()
        MemoryRelief.releaseSoon()
        save()
    }

    /// A page asked for a new window: it gets a new tab next to its own, made with WebKit's configuration.
    func openPopup(from opener: BrowserPage, configuration: WKWebViewConfiguration) -> WKWebView? {
        let id = tabs.addOpen(after: opener.id)
        let page = makePage(id: id)
        page.markAsPopup()
        let view = page.makeWebView(configuration: configuration)
        lastWatched[opener.id] = now()
        lastWatched[id] = now()
        scheduleSleepCheck()
        resetAddress()
        save()
        return view
    }

    // MARK: Bookmarks

    /// The star: bookmarks the page being shown, or removes its bookmark.
    func toggleBookmark() {
        guard let page = selectedPage, let url = page.url, let kept = BrowserAddress.kept(url) else { return }
        tabs.toggleBookmark(title: page.displayTitle, url: kept)
        save()
    }

    func removeBookmark(_ id: UUID) {
        tabs.removeBookmark(id)
        save()
    }

    /// Opens a bookmark: in the tab that already has that page if there is one (no second copy of Teams), else in the
    /// current tab if it is blank, else in a new tab next to the current one. Nothing of it exists until now.
    func openBookmark(_ id: UUID) {
        guard let bookmark = tabs.bookmarks.first(where: { $0.id == id }), let url = URL(string: bookmark.url) else { return }
        if let existing = tabs.openTab(on: bookmark.url) {
            select(existing.id)
            return
        }
        if let selected = tabs.selectedEntry, selected.url == nil, !hasPage {
            let page = selectedPage ?? makePage(id: selected.id)
            page.load(url)
            lastWatched[selected.id] = now()
            scheduleSleepCheck()
            address = url.absoluteString
            isEditingAddress = false
        } else {
            if let previous = tabs.selected { lastWatched[previous] = now() }
            tabs.addOpen(url: bookmark.url, after: tabs.selected)
            ensureSelectedLoaded()
            resetAddress()
        }
        save()
    }

    func toggleSidebar() {
        tabs.sidebarOpen.toggle()
        save()
    }

    /// Chooses where the tabs are: in a strip along the top, or in the list down the side. Choosing the side shows the list
    /// (it is what was just asked for); the sidebar button is only there while the tabs are on the side.
    func setTabsOnTop(_ onTop: Bool) {
        guard tabs.tabsOnTop != onTop else { return }
        tabs.tabsOnTop = onTop
        if !onTop { tabs.sidebarOpen = true }
        save()
    }

    // MARK: Sleeping pages

    /// Puts to sleep every page that has gone unwatched for `sleepAfter` seconds, except one that is playing sound or video.
    /// A sleeping tab keeps its place, its title and its address, and wakes (loads again) when it is chosen.
    @discardableResult
    func sleepIdlePages() async -> Int {
        await sleepPages(idleFor: sleepAfter)
    }

    /// "Free memory": puts every page to sleep except the one being looked at, now.
    @discardableResult
    func sleepOtherTabs() async -> Int {
        await sleepPages(idleFor: 0, includingPlaying: true)
    }

    private func isBeingWatched(_ id: UUID) -> Bool { isVisible && id == tabs.selected }

    private func sleepPages(idleFor minimum: TimeInterval, includingPlaying: Bool = false) async -> Int {
        let current = now()
        var slept = 0
        for (id, page) in pages where page.showsWeb {
            if isBeingWatched(id) {
                lastWatched[id] = current
                continue
            }
            guard current.timeIntervalSince(lastWatched[id] ?? current) >= minimum else { continue }
            if !includingPlaying, let view = page.webView, await view.requestMediaPlaybackState() == .playing {
                lastWatched[id] = current                // sound or video is playing: not idle
                continue
            }
            // The person may have looked at it while the question was being asked.
            guard pages[id] === page, !isBeingWatched(id) else { continue }
            sleep(page)
            slept += 1
        }
        if slept > 0 { MemoryRelief.releaseSoon() }
        scheduleSleepCheck()
        return slept
    }

    private func sleep(_ page: BrowserPage) {
        // Where it is now is where it wakes up.
        if let url = page.url, let kept = BrowserAddress.kept(url) { tabs.update(page.id, url: kept, title: page.title) }
        page.teardown()
        pages[page.id] = nil
        lastWatched[page.id] = nil
        save()
    }

    /// A light timer that runs only while some page is awake, to put idle ones to sleep. Nothing runs when none is.
    private func scheduleSleepCheck() {
        let anyAwake = pages.values.contains { $0.showsWeb }
        if !anyAwake {
            sleepTimer?.invalidate()
            sleepTimer = nil
            return
        }
        guard sleepTimer == nil, sleepAfter > 0 else { return }
        let interval = max(1, min(15, sleepAfter / 4))
        sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }   // the browser is gone: so is the timer
            Task { @MainActor in await self.sleepIdlePages() }
        }
        sleepTimer?.tolerance = interval / 2
    }

    // MARK: Ad blocking

    /// Whether the person can switch ad blocking on and off here (there is a blocker).
    var canBlockAds: Bool { adBlocker != nil }

    /// Ad blocking is on but its rules are not ready yet (the first moments after launch).
    fileprivate var isPreparingBlocker: Bool { adBlockEnabled && !blockerReady }

    /// Runs `work` once the rules are ready (now, if they are), starting to prepare them the first time.
    fileprivate func afterBlockerReady(_ work: @escaping () -> Void) {
        guard let adBlocker, !blockerReady else { work(); return }
        waitingForBlocker.append(work)
        guard !blockerStarted else { return }
        blockerStarted = true
        Task { @MainActor in
            await adBlocker.prepare()
            blockerReady = true
            let queued = waitingForBlocker
            waitingForBlocker = []
            queued.forEach { $0() }
        }
    }

    /// Puts ad blocking on a new page's content controller, if it is on.
    fileprivate func installBlocking(on controller: WKUserContentController) {
        guard adBlockEnabled, blockerReady, let adBlocker else { return }
        adBlocker.install(on: controller)
    }

    /// Switches ad blocking on or off. The page being shown reloads so the change shows; other pages change on their next load.
    func setAdBlock(_ on: Bool) {
        guard adBlocker != nil, on != adBlockEnabled else { return }
        adBlockEnabled = on
        save()
        let apply = { [weak self] in
            guard let self, let adBlocker = self.adBlocker else { return }
            for page in self.pages.values {
                guard let controller = page.webView?.configuration.userContentController else { continue }
                if self.adBlockEnabled { adBlocker.install(on: controller) } else { adBlocker.uninstall(from: controller) }
            }
            self.webView?.reload()
        }
        if on { afterBlockerReady(apply) } else { apply() }
    }

    // MARK: What the pages report

    fileprivate func pageFinished(_ page: BrowserPage) {
        if let url = page.url {
            tabs.update(page.id, url: BrowserAddress.kept(url), title: page.title)
        }
        save()
    }

    fileprivate func handOver(_ url: URL) {
        openElsewhere(url)
    }

    private func save() {
        try? store.save(BrowserState(tabs: tabs, adBlock: adBlocker == nil ? nil : adBlockEnabled))
    }
}

/// Hands memory the app has freed back to the system. The allocator keeps freed memory for later; after a page has been
/// thrown away that only makes the app look big in Activity Monitor.
enum MemoryRelief {
    private static let queue = DispatchQueue(label: "island.memory-relief", qos: .utility)

    static func releaseSoon(after delay: TimeInterval = 2) {
        queue.asyncAfter(deadline: .now() + delay) { _ = malloc_zone_pressure_relief(nil, 0) }
    }
}
