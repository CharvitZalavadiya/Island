import AppKit
import Foundation
import Observation
import WebKit
import IslandCore

/// What the Browser tab remembers between launches: the last page, without its query (see `BrowserAddress.remembered`).
struct BrowserState: Codable, Equatable {
    var lastAddress: String?
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

/// The Browser tab (a prototype): one web page inside the island, signed in the way a normal browser is (logins are kept
/// between launches, separately from the person's own browser). Meant for sites like Teams and WhatsApp on the web.
///
/// - The web view is made the first time the tab is opened and then kept, so a chat is still where it was after a visit
///   to another tab (and the page keeps running in the background).
/// - Links to other kinds of address (mail, a Teams app link) and files to download are handed to the app that handles
///   them; Command-click on a link opens it in the person's own browser.
@Observable
@MainActor
final class BrowserController {
    /// What the address bar shows and the person edits.
    var address = ""
    private(set) var title = ""
    private(set) var currentURL: URL?
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// Something was opened (until then the tab shows its start hint).
    private(set) var hasPage = false
    var message: String?

    /// The one web view, once it has been made.
    @ObservationIgnored private(set) var webView: IslandWebView?
    @ObservationIgnored private let store: FileStore<BrowserState>
    @ObservationIgnored private let openElsewhere: (URL) -> Void
    @ObservationIgnored private let dataStore: WKWebsiteDataStore
    @ObservationIgnored private var coordinator: Coordinator?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// What the address bar showed last by itself: the bar is only updated while it still shows that (not while it is being typed in).
    @ObservationIgnored private var shownAddress = ""

    /// A recent Safari: some sites (WhatsApp Web among them) turn away a web view that does not say who it is.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    init(
        store: FileStore<BrowserState>, dataStore: WKWebsiteDataStore? = nil,
        openElsewhere: @escaping (URL) -> Void = { url in _ = NSWorkspace.shared.open(url) }
    ) {
        self.store = store
        self.dataStore = dataStore ?? .default()
        self.openElsewhere = openElsewhere
    }

    // MARK: The tab

    /// The tab is on screen: make the web view if this is the first time, and go back to the page left open last time.
    func start() {
        ensureWebView()
        guard !hasPage, let last = store.load().lastAddress, let url = URL(string: last) else { return }
        load(url)
    }

    /// The view to show. Made on first use, so nothing from WebKit runs until the tab is opened.
    @discardableResult
    func ensureWebView() -> IslandWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let view = IslandWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = Self.userAgent
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        let coordinator = Coordinator(controller: self)
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

    // MARK: Going places

    /// Opens what was typed in the address bar: a web address, or words to search for.
    func go(_ text: String) {
        switch BrowserAddress.resolve(text) {
        case .empty:
            return
        case .unsupported:
            message = "This browser opens web addresses (http and https). Use your own browser for anything else."
        case .page(let url), .search(let url):
            message = nil
            load(url)
        }
    }

    func load(_ url: URL) {
        ensureWebView().load(URLRequest(url: url))
        hasPage = true
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func reloadOrStop() {
        guard let webView else { return }
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    /// Puts the current page's address back in the bar (after Escape, or an edit that was not wanted).
    func resetAddress() {
        address = currentURL?.absoluteString ?? ""
        shownAddress = address
    }

    func openInDefaultBrowser() {
        if let url = currentURL { openElsewhere(url) }
    }

    /// Signs out of every site and forgets everything the sites stored (cookies, logins, caches).
    func clearWebsiteData() async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        webView?.reload()
    }

    // MARK: What the web view reports

    private func urlChanged(_ url: URL?) {
        currentURL = url
        let shown = url?.absoluteString ?? ""
        if address.isEmpty || address == shownAddress { address = shown }
        shownAddress = shown
    }

    fileprivate func pageFinished() {
        message = nil
        if let url = currentURL, let remembered = BrowserAddress.remembered(url) {
            try? store.save(BrowserState(lastAddress: remembered))
        }
    }

    fileprivate func pageFailed(_ error: Error) {
        let nsError = error as NSError
        // A page that was stopped, or that this tab itself handed to another app, is not a failure.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        message = "Couldn't open this page. \(nsError.localizedDescription)"
    }

    fileprivate func handOver(_ url: URL) {
        openElsewhere(url)
    }

    // MARK: The web view's delegates

    private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var controller: BrowserController?

        init(controller: BrowserController) {
            self.controller = controller
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
                if let url { controller?.handOver(url) }
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
                controller?.handOver(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { controller?.pageFinished() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { controller?.pageFailed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { controller?.pageFailed(error) }

        /// A link that wants a new window (target="_blank", window.open) opens in this same view: there is only one.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
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
