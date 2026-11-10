import AppKit
import Foundation
import Network
import SwiftUI
import Testing
import WebKit
import IslandCore
@testable import IslandUI

/// A small web site on this Mac's loopback only, so the browser can be tested against real pages without the internet.
private final class LocalSite: @unchecked Sendable {
    struct Request { var path: String; var userAgent: String; var cookie: String }

    private let queue = DispatchQueue(label: "island.test.site")
    private var listener: NWListener?
    private let lock = NSLock()
    private var recorded: [Request] = []
    var requests: [Request] { lock.lock(); defer { lock.unlock() }; return recorded }

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: { let p = NWParameters.tcp; p.requiredInterfaceType = .loopback; return p }())
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        final class Once: @unchecked Sendable { var done = false }
        let once = Once()
        return try await withCheckedThrowingContinuation { (started: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                if case .ready = state { once.done = true; started.resume(returning: listener.port?.rawValue ?? 0) }
                if case .failed(let error) = state { once.done = true; started.resume(throwing: error) }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener?.cancel() }

    private func record(_ request: Request) {
        lock.lock(); recorded.append(request); lock.unlock()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { connection.cancel(); return }
            let lines = text.components(separatedBy: "\r\n")
            let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            func header(_ name: String) -> String {
                lines.first { $0.lowercased().hasPrefix(name.lowercased() + ":") }.map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) } ?? ""
            }
            self.record(Request(path: path, userAgent: header("User-Agent"), cookie: header("Cookie")))

            var status = "200 OK"
            var headers = "Content-Type: text/html; charset=utf-8\r\n"
            var body = ""
            let route = path.split(separator: "?").first.map(String.init) ?? path
            switch route {
            case "/a":
                headers += "Set-Cookie: sid=signed-in; Path=/\r\n"
                body = "<html><head><title>Page A</title></head><body><a id=l href=\"/b\">to b</a></body></html>"
            case "/b":
                body = "<html><head><title>Page B</title></head><body>b</body></html>"
            case "/file":
                headers = "Content-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"x.bin\"\r\n"
                body = "BINARY"
            default:
                status = "404 Not Found"
                body = "<html><head><title>Missing</title></head></html>"
            }
            let bytes = Data(body.utf8)
            let head = "HTTP/1.1 \(status)\r\n\(headers)Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

private final class Handed: @unchecked Sendable { var urls: [URL] = [] }

@MainActor private func tempStore() -> FileStore<BrowserState> {
    FileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("browser-\(UUID()).json"), defaultValue: BrowserState())
}

/// A browser that keeps its sites only in memory, so tests never touch the real (persistent) logins.
@MainActor private func makeBrowser(store: FileStore<BrowserState>? = nil, dataStore: WKWebsiteDataStore = .nonPersistent(), handed: Handed = Handed()) -> BrowserController {
    _ = NSApplication.shared
    return BrowserController(store: store ?? tempStore(), dataStore: dataStore, openElsewhere: { handed.urls.append($0) })
}

@MainActor private func browserEventually(timeout: TimeInterval = 8, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

@Test @MainActor func browserNothingFromWebKitRunsUntilTheTabIsOpened() {
    let browser = makeBrowser()
    #expect(browser.webView == nil && !browser.hasPage)
    browser.start()                                            // the tab opens with nothing remembered: a view, but still the start hint
    #expect(browser.webView != nil && !browser.hasPage)
    #expect(browser.webView?.customUserAgent == BrowserController.userAgent)
}

@Test @MainActor func browserOpensAPageKeepsTheBarInStepAndSendsTheSafariIdentity() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()

    browser.go("127.0.0.1:\(port)/a")                          // a bare address: http, because it is this Mac
    #expect(browser.hasPage)
    let loaded = await browserEventually { browser.title == "Page A" && !browser.isLoading }
    #expect(loaded, "the page did not load; message: \(String(describing: browser.message))")
    #expect(browser.address == "http://127.0.0.1:\(port)/a" && browser.currentURL?.path == "/a")
    #expect(!browser.canGoBack)
    #expect(site.requests.first?.userAgent == BrowserController.userAgent)    // what the site actually received

    browser.go("http://127.0.0.1:\(port)/b")
    #expect(await browserEventually { browser.title == "Page B" })
    #expect(browser.canGoBack && !browser.canGoForward)
    browser.goBack()
    #expect(await browserEventually { browser.title == "Page A" })
    #expect(browser.canGoForward)
    browser.goForward()
    #expect(await browserEventually { browser.title == "Page B" })
}

@Test @MainActor func browserWhatIsBeingTypedInTheBarIsNotOverwrittenByAPageChange() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })

    browser.address = "tea"                                    // the person is typing...
    browser.webView?.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/a")!))   // ...and meanwhile the page reloads by itself
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })
    #expect(browser.address == "tea")                          // what they typed stays
    browser.resetAddress()                                     // Escape brings the page's address back
    #expect(browser.address == "http://127.0.0.1:\(port)/a")
}

@Test @MainActor func browserRemembersTheLastPageWithoutAnythingFromItsQuery() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let store = tempStore()
    let first = makeBrowser(store: store)
    first.start()
    first.go("http://127.0.0.1:\(port)/a?code=SECRET#id_token=T")
    #expect(await browserEventually { first.title == "Page A" && !first.isLoading })
    #expect(await browserEventually { store.load().lastAddress != nil })
    #expect(store.load().lastAddress == "http://127.0.0.1:\(port)/a")
    let onDisk = (try? String(contentsOf: store.url, encoding: .utf8)) ?? ""
    #expect(!onDisk.contains("SECRET") && !onDisk.contains("id_token"))

    // Next launch: opening the tab returns to that page by itself.
    let second = makeBrowser(store: store)
    #expect(!second.hasPage)
    second.start()
    #expect(second.hasPage)
    #expect(await browserEventually { second.title == "Page A" })
}

@Test @MainActor func browserAFileToDownloadIsHandedToTheDefaultBrowserAndThePageStays() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let handed = Handed()
    let browser = makeBrowser(handed: handed)
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })

    browser.go("http://127.0.0.1:\(port)/file")
    #expect(await browserEventually { !handed.urls.isEmpty })
    #expect(handed.urls.first?.path == "/file")
    try? await Task.sleep(nanoseconds: 200_000_000)
    #expect(browser.title == "Page A" && browser.message == nil)    // still on the page, and no "failed" message for a hand-over
}

@Test @MainActor func browserAPageThatCannotBeReachedSaysSoAndOtherKindsOfAddressAreRefused() async {
    let browser = makeBrowser()
    browser.start()
    browser.go("javascript:alert(1)")
    #expect(browser.message?.contains("web addresses") == true && !browser.hasPage)
    browser.go("   ")
    #expect(!browser.hasPage)

    browser.go("http://127.0.0.1:1/nothing-listens-here")
    #expect(await browserEventually { browser.message?.contains("Couldn't open this page") == true })
}

@Test @MainActor func browserSigningOutOfAllSitesClearsWhatTheyStored() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let dataStore = WKWebsiteDataStore.nonPersistent()
    let browser = makeBrowser(dataStore: dataStore)
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")                    // this page sets a cookie, like a login would
    #expect(await browserEventually { browser.title == "Page A" })
    var cookies = await dataStore.httpCookieStore.allCookies()
    #expect(cookies.contains { $0.name == "sid" })

    await browser.clearWebsiteData()
    cookies = await dataStore.httpCookieStore.allCookies()
    #expect(!cookies.contains { $0.name == "sid" })
}

@Test @MainActor func theTabBarFitsTheIslandWithEveryTabAndTheMaxButton() {
    _ = NSApplication.shared
    let model = IslandModel(settings: SettingsStore(store: FileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID()).json"), defaultValue: Settings())))
    let needed = NSHostingView(rootView: TabBar(model: model, openSettings: {})).fittingSize.width
    let available = IslandMetrics.expandedSize.width - 2 * (18 + NotchShape.expanded.top)
    #expect(needed <= available - 8, "the tab bar needs \(needed) pt and the island gives \(available) pt: widen the island or slim the icons")
}

@Test @MainActor func maxModeIsOffAtFirstAndTheContentStartsAtTheUsualSize() {
    let model = IslandModel(settings: SettingsStore(store: FileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("m-\(UUID()).json"), defaultValue: Settings())))
    #expect(!model.isMax && !model.isPinned)
    #expect(model.contentSize == IslandMetrics.expandedSize)
    #expect(IslandTab.browser.title == "Browser" && model.orderedTabs.contains(.browser))
}
