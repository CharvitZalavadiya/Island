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
            if path.split(separator: "?").first.map(String.init) == "/drop" {   // takes the request and hangs up, so the page can never be reached
                connection.cancel()
                return
            }

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
            case "/adpage":
                body = "<html><head><title>Ad page</title></head><body><script src=\"/ads/ad.js\"></script><script src=\"/app.js\"></script></body></html>"
            case "/ads/ad.js":
                headers = "Content-Type: application/javascript\r\n"
                body = "window.adLoaded = true;"
            case "/app.js":
                headers = "Content-Type: application/javascript\r\n"
                body = "window.appLoaded = true;"
            case "/yt":
                body = """
                <html><head><title>Fake YouTube</title></head><body><script>
                var ytInitialPlayerResponse = {"videoDetails":{"title":"Video"},"adPlacements":[{"a":1}],"playerAds":[1],"adSlots":[1]};
                window.parsed = JSON.parse('{"playerResponse":{"adPlacements":[1],"keep":2},"adSlots":[3],"other":4}');
                window.fetched = null;
                fetch('/youtubei/v1/player?key=x').then(function (r) { return r.json(); }).then(function (j) { window.fetched = j; });
                window.otherFetched = null;
                fetch('/other.json').then(function (r) { return r.json(); }).then(function (j) { window.otherFetched = j; });
                </script></body></html>
                """
            case "/youtubei/v1/player":
                headers = "Content-Type: application/json\r\n"
                body = #"{"videoDetails":{"title":"Fetched"},"adPlacements":[1],"playerAds":[2],"adSlots":[3]}"#
            case "/other.json":
                headers = "Content-Type: application/json\r\n"
                body = #"{"adPlacements":["not youtube's request, left alone by the fetch layer"],"x":1}"#
            case "/ytcss":
                body = "<html><head><title>Css</title></head><body><ytd-ad-slot-renderer id=\"ad\">Ad</ytd-ad-slot-renderer><div id=\"real\">Real</div></body></html>"
            case "/skip":
                body = """
                <html><head><title>Skip</title></head><body>
                <div id="movie_player" class="html5-video-player ad-showing"><video class="html5-main-video" id="v"></video>
                <button class="ytp-skip-ad-button" onclick="window.skipped = true"></button></div>
                <script>
                var v = document.getElementById('v');
                var time = 0;
                Object.defineProperty(v, 'duration', { get: function () { return 30; } });
                Object.defineProperty(v, 'currentTime', { get: function () { return time; }, set: function (x) { time = x; } });
                window.state = function () { return JSON.stringify({ skipped: !!window.skipped, time: time, muted: v.muted, rate: v.playbackRate }); };
                </script></body></html>
                """
            case "/old":
                status = "302 Found"
                headers += "Location: /b\r\n"
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
@MainActor private func makeBrowser(
    store: FileStore<BrowserState>? = nil, dataStore: WKWebsiteDataStore = .nonPersistent(), handed: Handed = Handed(),
    sleepAfter: TimeInterval = 120, clock: TestClock = TestClock(), adBlocker: BrowserAdBlocker? = nil
) -> BrowserController {
    _ = NSApplication.shared
    return BrowserController(store: store ?? tempStore(), dataStore: dataStore, adBlocker: adBlocker, sleepAfter: sleepAfter, now: { clock.now }, openElsewhere: { handed.urls.append($0) })
}

/// An ad blocker that keeps its compiled rules in a private folder (never WebKit's real store), blocking `/ads/` on the local
/// site as well, and treating the local address as YouTube.
@MainActor private func makeBlocker(port: UInt16, youtubeHost: String? = "^127\\.0\\.0\\.1$") -> BrowserAdBlocker {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("island-rules-\(UUID())", isDirectory: true)
    return BrowserAdBlocker(
        extraBlockedFilters: ["127\\.0\\.0\\.1:\(port)/ads/"], youtubeHostPattern: youtubeHost, store: WKContentRuleListStore(url: folder))
}

/// Runs JavaScript in the page being shown and returns its text result ("" if it could not run).
@MainActor private func script(_ browser: BrowserController, _ code: String) async -> String {
    guard let view = browser.webView else { return "" }
    return ((try? await view.evaluateJavaScript(code)) as? String) ?? ""
}

/// A clock the test moves by hand, so no test waits two real minutes for a page to fall asleep.
private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Like `browserEventually`, for a question that has to ask the page (which takes an `await`).
@MainActor private func browserEventuallyAsking(timeout: TimeInterval = 30, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 40_000_000)
    }
    return await condition()
}

@MainActor private func browserEventually(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

@Test @MainActor func browserNothingFromWebKitRunsUntilAPageIsOpened() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    #expect(browser.webView == nil && !browser.hasPage)
    browser.start()                                            // the tab opens on a blank tab: the new-tab page, no web view yet
    #expect(browser.webView == nil && !browser.hasPage && browser.wantsAddressFocus)
    browser.go("127.0.0.1:\(port)/a")
    #expect(browser.webView != nil && browser.hasPage)
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

    browser.addressEditingChanged(true)                        // the person is typing...
    browser.address = "tea"
    browser.webView?.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/a")!))   // ...and meanwhile the page reloads by itself
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })
    #expect(browser.address == "tea")                          // what they typed stays
    browser.addressEditingChanged(false)                       // they left the bar without pressing Return: the page's address comes back
    #expect(browser.address == "http://127.0.0.1:\(port)/a")
}

@Test @MainActor func browserTheBarShowsThePageYouAreOnNotWhatYouTypedAndFollowsRedirects() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()

    // Typed without a scheme, then Return: the bar shows the real address.
    browser.addressEditingChanged(true)
    browser.address = "127.0.0.1:\(port)/a"
    browser.go(browser.address)
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })
    #expect(browser.address == "http://127.0.0.1:\(port)/a")

    // A page that redirects: the bar ends on where the page really is.
    browser.addressEditingChanged(true)
    browser.address = "127.0.0.1:\(port)/old"
    browser.go(browser.address)
    #expect(await browserEventually { browser.title == "Page B" && !browser.isLoading })
    #expect(browser.address == "http://127.0.0.1:\(port)/b")
}

@Test @MainActor func browserRemembersTheLastPageWithoutAnySecretsFromItsAddress() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let store = tempStore()
    let first = makeBrowser(store: store)
    first.start()
    first.go("http://127.0.0.1:\(port)/a?q=keep&code=SECRET#id_token=T")
    #expect(await browserEventually { first.title == "Page A" && !first.isLoading })
    #expect(await browserEventually { store.load().tabs?.selectedEntry?.url != nil })
    #expect(store.load().tabs?.selectedEntry?.url == "http://127.0.0.1:\(port)/a?q=keep")
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

@Test @MainActor func browserAPageThatCannotBeReachedSaysSoAndOtherKindsOfAddressAreRefused() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.go("javascript:alert(1)")
    #expect(browser.message?.contains("web addresses") == true && !browser.hasPage)
    browser.go("   ")
    #expect(!browser.hasPage)

    // A server that hangs up on the request (a closed port would do on most Macs, but some networks make that wait for ages).
    browser.go("http://127.0.0.1:\(port)/drop")
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

// MARK: Tabs, bookmarks, the sidebar

@Test @MainActor func browserStartsOnOneBlankTabWithTheSidebarOffAndTheChoiceIsRemembered() {
    let store = tempStore()
    let browser = makeBrowser(store: store)
    #expect(browser.tabs.open.count == 1 && browser.tabs.bookmarks.isEmpty && !browser.tabs.sidebarOpen)
    browser.toggleSidebar()
    #expect(browser.tabs.sidebarOpen)
    #expect(makeBrowser(store: store).tabs.sidebarOpen)         // still on next launch
}

@Test @MainActor func browserANewTabIsBlankNextToTheCurrentOneAndAsksForTheAddressBar() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })
    let first = try #require(browser.tabs.selected)
    let request = browser.addressFocusRequest

    browser.newTab()
    #expect(browser.tabs.open.count == 2 && browser.tabs.selected != first && browser.tabs.open.first?.id == first)
    #expect(!browser.hasPage && browser.address == "" && browser.addressFocusRequest == request + 1)
    browser.select(first)                                       // back to the first: its page is still there, still awake
    #expect(browser.hasPage && browser.title == "Page A" && browser.address == "http://127.0.0.1:\(port)/a")
    #expect(browser.tabs.open.count == 1)                       // and the blank tab that was never used did not stay behind
}

@Test @MainActor func browserABookmarkIsOnlyALinkThatSurvivesClosingEverythingAndQuitting() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let store = tempStore()
    let browser = makeBrowser(store: store)
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a?token=NOPE")
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })
    #expect(!browser.isCurrentBookmarked)
    browser.toggleBookmark()                                    // the star
    #expect(browser.isCurrentBookmarked && browser.tabs.bookmarks.count == 1)
    let bookmark = try #require(browser.tabs.bookmarks.first)
    #expect(bookmark.url == "http://127.0.0.1:\(port)/a" && bookmark.title == "Page A")   // the address a secret was taken out of

    browser.newTab()
    browser.go("http://127.0.0.1:\(port)/b")
    #expect(await browserEventually { browser.title == "Page B" && !browser.isLoading })
    #expect(!browser.isCurrentBookmarked)                       // the star follows the page, not the tab
    for entry in browser.tabs.open { browser.close(entry.id) }  // close every tab, by mistake
    #expect(browser.tabs.bookmarks.map(\.id) == [bookmark.id])
    #expect(browser.tabs.open.count == 1 && browser.tabs.open[0].url == nil)

    // Quit and relaunch: the bookmark is there, and NOTHING is open or running until it is clicked.
    let relaunched = makeBrowser(store: store)
    relaunched.start()
    #expect(relaunched.tabs.bookmarks.map(\.id) == [bookmark.id])
    #expect(relaunched.webView == nil && !relaunched.hasPage)
    #expect(!((try? String(contentsOf: store.url, encoding: .utf8)) ?? "").contains("NOPE"))

    relaunched.openBookmark(bookmark.id)                        // the current tab is blank: it opens here
    #expect(relaunched.hasPage && relaunched.tabs.open.count == 1)
    #expect(await browserEventually { relaunched.title == "Page A" })
    #expect(relaunched.isCurrentBookmarked)
    relaunched.toggleBookmark()                                 // star again: gone
    #expect(relaunched.tabs.bookmarks.isEmpty)
}

@Test @MainActor func browserOpeningABookmarkThatIsAlreadyOpenSwitchesToItInsteadOfOpeningASecondCopy() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })
    let first = try #require(browser.tabs.selected)
    browser.toggleBookmark()
    let bookmark = try #require(browser.tabs.bookmarks.first)
    browser.newTab()
    browser.go("http://127.0.0.1:\(port)/b")
    #expect(await browserEventually { browser.title == "Page B" })

    browser.openBookmark(bookmark.id)
    #expect(browser.tabs.selected == first && browser.tabs.open.count == 2)   // back to the one that has it
    #expect(browser.title == "Page A")
}

@Test @MainActor func browserOpeningABookmarkFromAUsedTabOpensANewTabNextToIt() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })
    browser.toggleBookmark()
    let bookmark = try #require(browser.tabs.bookmarks.first)
    browser.go("http://127.0.0.1:\(port)/b")                   // this tab moves on from the bookmarked page
    #expect(await browserEventually { browser.title == "Page B" && !browser.isLoading })
    let here = try #require(browser.tabs.selected)

    browser.openBookmark(bookmark.id)
    #expect(browser.tabs.open.count == 2 && browser.tabs.selected != here)
    #expect(browser.tabs.open.first?.id == here)                // the one that was in use is still there, untouched
    #expect(await browserEventually { browser.title == "Page A" })
}

@Test @MainActor func browserTheStarNeedsAPageToBookmark() {
    let browser = makeBrowser()
    browser.start()
    browser.toggleBookmark()                                    // a blank tab has nothing to bookmark
    #expect(browser.tabs.bookmarks.isEmpty && !browser.isCurrentBookmarked)
}

@Test @MainActor func browserANewWindowFromAPageOpensAsANewTabNextToIt() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })
    let opener = try #require(browser.selectedPage)
    browser.newTab()                                            // (a second tab after the first, to check the placement)
    browser.select(opener.id)

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let popup = browser.openPopup(from: opener, configuration: configuration)
    #expect(popup != nil)
    #expect(browser.tabs.open.count == 2)                       // the opener and the popup (the unused blank tab went when it was left)
    let ids = browser.tabs.open.map(\.id)
    #expect(ids.first == opener.id && browser.tabs.selected == ids[1])                  // right after its opener, and selected
    #expect(browser.hasPage && browser.selectedPage?.webView === popup)
}

@Test @MainActor func browserTheFirstVersionsSingleSavedAddressBecomesTheFirstTab() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("browser-old-\(UUID()).json")
    try Data(#"{"lastAddress":"https://web.whatsapp.com/"}"#.utf8).write(to: url)
    let browser = makeBrowser(store: FileStore(url: url, defaultValue: BrowserState()))
    #expect(browser.tabs.open.count == 1 && browser.tabs.open[0].url == "https://web.whatsapp.com/" && browser.tabs.selected == browser.tabs.open[0].id)
}

@Test @MainActor func browserPinnedTabsFromTheLastVersionBecomeBookmarksWhenTheFileIsRead() throws {
    let teams = UUID(), other = UUID()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("browser-pinned-\(UUID()).json")
    let old = """
    {"tabs":{"selected":"\(teams.uuidString)","sidebarOpen":false,
     "pinned":[{"id":"\(teams.uuidString)","url":"https://teams.microsoft.com/v2/","title":"Microsoft Teams"}],
     "open":[{"id":"\(other.uuidString)","url":"https://example.com/","title":"Example"}]}}
    """
    try Data(old.utf8).write(to: url)
    let browser = makeBrowser(store: FileStore(url: url, defaultValue: BrowserState()))
    #expect(browser.tabs.bookmarks.map(\.title) == ["Microsoft Teams"])
    #expect(browser.tabs.open.map(\.id) == [other, teams] && browser.tabs.selected == teams)   // what was showing stays open
}

// MARK: Sleeping pages (the island stays light)

@Test @MainActor func browserAPageNobodyIsWatchingFallsAsleepAndWakesAtTheSameAddress() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let clock = TestClock()
    let browser = makeBrowser(sleepAfter: 120, clock: clock)
    browser.start()
    browser.setVisible(true)
    browser.go("http://127.0.0.1:\(port)/a?x=1")
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })
    let first = try #require(browser.tabs.selected)
    browser.newTab()                                            // looking at another tab now
    #expect(browser.isAwake(first))

    clock.advance(119)
    let tooSoon = await browser.sleepIdlePages()
    #expect(tooSoon == 0 && browser.isAwake(first))             // not yet
    clock.advance(2)
    let slept = await browser.sleepIdlePages()
    #expect(slept == 1 && !browser.isAwake(first))              // 121 seconds unwatched: its page is gone
    #expect(browser.tabs.entry(first)?.url == "http://127.0.0.1:\(port)/a?x=1")      // but the tab keeps its place, its address...
    #expect(browser.tabs.entry(first)?.title == "Page A")       // ...and its name
    #expect(browser.displayTitle(of: try #require(browser.tabs.entry(first))) == "Page A")

    let requestsBefore = site.requests.filter { $0.path.hasPrefix("/a") }.count
    browser.select(first)                                       // choose it: it wakes
    #expect(browser.hasPage)
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })
    #expect(site.requests.filter { $0.path.hasPrefix("/a") }.count == requestsBefore + 1)   // loaded again from the same address
}

@Test @MainActor func browserThePageBeingWatchedNeverSleeps() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let clock = TestClock()
    let browser = makeBrowser(sleepAfter: 120, clock: clock)
    browser.start()
    browser.setVisible(true)
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })
    clock.advance(10_000)                                       // hours with the tab open in front of the person
    let slept = await browser.sleepIdlePages()
    #expect(slept == 0 && browser.hasPage)
}

@Test @MainActor func browserWhenTheIslandClosesEvenTheShownPageCountsDownThenWakesWhenItOpensAgain() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let clock = TestClock()
    let browser = makeBrowser(sleepAfter: 120, clock: clock)
    browser.start()
    browser.setVisible(true)
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })

    browser.setVisible(false)                                   // the island closed (or another island tab was chosen)
    clock.advance(60)
    let early = await browser.sleepIdlePages()
    #expect(early == 0 && browser.hasPage)                      // a short trip away costs nothing
    clock.advance(70)
    let slept = await browser.sleepIdlePages()
    #expect(slept == 1 && !browser.hasPage)
    #expect(browser.isWaking)                                   // it has somewhere to be, and is not up

    browser.setVisible(true)                                    // the island opens on the Browser tab again
    browser.start()
    #expect(browser.hasPage && !browser.isWaking)
    #expect(await browserEventually { browser.title == "Page A" })
}

@Test @MainActor func browserFreeMemoryNowPutsEveryTabToSleepExceptTheOneBeingLookedAt() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.setVisible(true)
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })
    let first = try #require(browser.tabs.selected)
    browser.newTab()
    browser.go("http://127.0.0.1:\(port)/b")
    #expect(await browserEventually { browser.title == "Page B" })
    let second = try #require(browser.tabs.selected)

    let slept = await browser.sleepOtherTabs()
    #expect(slept == 1 && !browser.isAwake(first) && browser.isAwake(second))
    #expect(browser.title == "Page B")                          // the one in front is untouched
}

@Test @MainActor func browserNothingIsHeldForABlankTabOrABookmark() {
    let store = tempStore()
    let browser = makeBrowser(store: store)
    browser.start()
    browser.setVisible(true)
    #expect(browser.webView == nil && browser.selectedPage?.webView == nil)
}

@Test @MainActor func browserEveryTabCanBeClosedAndExactlyOneBlankTabToSearchFromIsLeft() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser()
    browser.start()
    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" })
    browser.toggleBookmark()                                    // a bookmark exists, to prove it is not a tab
    browser.newTab()
    browser.go("http://127.0.0.1:\(port)/b")
    #expect(await browserEventually { browser.title == "Page B" })
    browser.newTab()
    #expect(browser.tabs.open.count == 3)

    for entry in browser.tabs.open { browser.close(entry.id) }
    #expect(browser.tabs.open.count == 1)                       // only one tab...
    #expect(browser.tabs.open[0].url == nil && !browser.hasPage && browser.selectedPage?.webView == nil)   // ...blank, to search from
    #expect(browser.wantsAddressFocus && browser.address == "")
    #expect(browser.tabs.bookmarks.count == 1)                  // and the bookmark is still one click away on that page

    browser.close(try #require(browser.tabs.selected))          // closing that last blank tab changes nothing the person can see
    #expect(browser.tabs.open.count == 1 && browser.tabs.open[0].url == nil && !browser.hasPage)
}

@Test @MainActor func browserTheTabsCanBeOnTopOrOnTheSideAndTheChoiceIsRemembered() {
    let store = tempStore()
    let browser = makeBrowser(store: store)
    #expect(!browser.tabs.tabsOnTop && !browser.tabs.sidebarOpen)         // at first: tabs on the side, list hidden

    browser.setTabsOnTop(true)
    #expect(browser.tabs.tabsOnTop && !browser.tabs.sidebarOpen)
    #expect(makeBrowser(store: store).tabs.tabsOnTop)                      // still on top next launch

    browser.setTabsOnTop(false)                                            // "Show tabs on the side": the list appears, it is what was asked for
    #expect(!browser.tabs.tabsOnTop && browser.tabs.sidebarOpen)
    let relaunched = makeBrowser(store: store)
    #expect(!relaunched.tabs.tabsOnTop && relaunched.tabs.sidebarOpen)

    browser.toggleSidebar()                                                // hiding the list on the side still works as before
    #expect(!browser.tabs.sidebarOpen && !browser.tabs.tabsOnTop)
    browser.setTabsOnTop(true)
    browser.setTabsOnTop(true)                                             // asking for what is already so changes nothing
    #expect(browser.tabs.tabsOnTop && !browser.tabs.sidebarOpen)
}

@Test @MainActor func browserHomeTakesTheCurrentTabBackToTheNewTabPageAndLetsGoOfThePage() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let store = tempStore()
    let browser = makeBrowser(store: store)
    browser.start()
    browser.goHome()                                            // a blank tab is already home: nothing to do
    #expect(!browser.hasPage && browser.tabs.open.count == 1)

    browser.go("http://127.0.0.1:\(port)/a")
    #expect(await browserEventually { browser.title == "Page A" && !browser.isLoading })
    browser.toggleBookmark()
    let tab = try #require(browser.tabs.selected)
    let request = browser.addressFocusRequest

    browser.goHome()
    #expect(browser.tabs.selected == tab && browser.tabs.open.count == 1)    // the same tab...
    #expect(!browser.hasPage && !browser.isAwake(tab) && browser.webView == nil)   // ...on the new-tab page, its page let go
    #expect(browser.tabs.entry(tab)?.url == nil && browser.address == "" && browser.wantsAddressFocus)
    #expect(browser.addressFocusRequest == request + 1)                      // the address bar is ready to type in
    #expect(browser.tabs.bookmarks.count == 1)                               // and the bookmark is one click away
    #expect(makeBrowser(store: store).tabs.selectedEntry?.url == nil)        // it stays blank after a relaunch

    browser.openBookmark(try #require(browser.tabs.bookmarks.first?.id))     // from home, a bookmark opens right here
    #expect(browser.hasPage && browser.tabs.open.count == 1)
    #expect(await browserEventually { browser.title == "Page A" })
}

// MARK: Ad blocking

@Test @MainActor func adBlockTheRulesCompileInWebKitAndAreTheSameEveryTime() async throws {
    let json = AdBlockRules.json()
    #expect(json == AdBlockRules.json())                                                  // stable, so WebKit's saved copy is reused
    let list = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    #expect(list.count > 60)
    #expect(list.contains { ($0["action"] as? [String: Any])?["type"] as? String == "css-display-none" })
    #expect(AdBlockRules.identifier(for: json) == AdBlockRules.identifier(for: AdBlockRules.json()))
    #expect(AdBlockRules.identifier(for: json) != AdBlockRules.identifier(for: AdBlockRules.json(extraBlockedFilters: ["x"])))   // new rules, new name

    // WebKit itself accepts the real rules (its compiler rejects anything its syntax does not allow).
    _ = NSApplication.shared
    let blocker = BrowserAdBlocker(store: WKContentRuleListStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("island-rules-\(UUID())", isDirectory: true)))
    await blocker.prepare()
    #expect(blocker.problem == nil, "WebKit refused the rules: \(blocker.problem ?? "")")
    #expect(blocker.ruleList != nil)
}

@Test @MainActor func adBlockAdRequestsAreStoppedAndTheRestOfThePageLoadsAndSwitchingItOffBringsThemBack() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser(adBlocker: makeBlocker(port: port))
    #expect(browser.adBlockEnabled && browser.canBlockAds)
    browser.start()
    browser.go("http://127.0.0.1:\(port)/adpage")
    #expect(await browserEventually { browser.title == "Ad page" && !browser.isLoading })
    #expect(await browserEventuallyAsking { await script(browser, "window.appLoaded === true ? 'yes' : 'no'") == "yes" })     // the page itself works
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(await script(browser, "typeof window.adLoaded") == "undefined")                                              // the ad script did not run
    #expect(!site.requests.contains { $0.path.hasPrefix("/ads/") })                                                      // and was never even asked for

    browser.setAdBlock(false)                                                                                            // switched off: the page reloads with its ads
    #expect(await browserEventuallyAsking { await script(browser, "window.adLoaded === true ? 'yes' : 'no'") == "yes" })
    #expect(site.requests.contains { $0.path.hasPrefix("/ads/") })

    browser.setAdBlock(true)                                                                                             // and on again
    let before = site.requests.filter { $0.path.hasPrefix("/ads/") }.count
    try? await Task.sleep(nanoseconds: 800_000_000)
    #expect(await browserEventuallyAsking { await script(browser, "typeof window.adLoaded") == "undefined" && !browser.isLoading })
    #expect(site.requests.filter { $0.path.hasPrefix("/ads/") }.count == before)
}

@Test @MainActor func adBlockTheChoiceIsRememberedAndOnByDefaultAndAbsentWithoutABlocker() async throws {
    _ = NSApplication.shared
    let store = tempStore()
    let first = makeBrowser(store: store, adBlocker: makeBlocker(port: 1))
    #expect(first.adBlockEnabled)                                                // on unless switched off
    first.setAdBlock(false)
    #expect(!first.adBlockEnabled)
    #expect(!makeBrowser(store: store, adBlocker: makeBlocker(port: 1)).adBlockEnabled)       // still off next launch
    first.setAdBlock(true)
    #expect(makeBrowser(store: store, adBlocker: makeBlocker(port: 1)).adBlockEnabled)

    let none = makeBrowser()                                                     // no blocker: nothing to switch
    #expect(!none.canBlockAds && !none.adBlockEnabled)
    none.setAdBlock(true)
    #expect(!none.adBlockEnabled)
}

@Test @MainActor func adBlockYouTubeAdDataIsRemovedBeforeThePlayerSeesIt() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser(adBlocker: makeBlocker(port: port))
    browser.start()
    browser.go("http://127.0.0.1:\(port)/yt")
    #expect(await browserEventuallyAsking { await script(browser, "window.fetched ? 'yes' : 'no'") == "yes" })
    // The page's own copy of the player data: the ad keys are gone, the video's details stay.
    #expect(await script(browser, "Object.keys(ytInitialPlayerResponse).join(',')") == "videoDetails")
    #expect(await script(browser, "ytInitialPlayerResponse.videoDetails.title") == "Video")
    // Anything the page parses.
    #expect(await script(browser, "JSON.stringify(window.parsed)") == #"{"playerResponse":{"keep":2},"other":4}"#)
    // YouTube's own request for the player: the answer arrives without ads, the rest intact.
    #expect(await script(browser, "JSON.stringify(window.fetched)") == #"{"videoDetails":{"title":"Fetched"}}"#)
    // A request that is not YouTube's player/next is not touched by the fetch layer.
    #expect(await browserEventuallyAsking { await script(browser, "window.otherFetched ? 'yes' : 'no'") == "yes" })
    #expect(await script(browser, "String(window.otherFetched.adPlacements.length) + ',' + window.otherFetched.x") == "1,1")   // left exactly as it came
}

@Test @MainActor func adBlockNothingHappensOnASiteThatIsNotYouTube() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    // The same fake page, but the script is told YouTube is some other address: it must leave the page alone.
    let browser = makeBrowser(adBlocker: makeBlocker(port: port, youtubeHost: "^not-this-host\\.example$"))
    browser.start()
    browser.go("http://127.0.0.1:\(port)/yt")
    #expect(await browserEventuallyAsking { await script(browser, "window.fetched ? 'yes' : 'no'") == "yes" })
    #expect(await script(browser, "Object.keys(ytInitialPlayerResponse).sort().join(',')") == "adPlacements,adSlots,playerAds,videoDetails")
    #expect(await script(browser, "String(window.fetched.adPlacements)") == "1")
    #expect(await script(browser, "typeof window.__islandAdBlock") == "undefined")
}

@Test @MainActor func adBlockTheDefaultScriptOnlyAppliesToYouTubeAddresses() throws {
    let pattern = try NSRegularExpression(pattern: YouTubeAdScript.defaultHostPattern)
    func matches(_ host: String) -> Bool { pattern.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil }
    for host in ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "www.youtube-nocookie.com"] { #expect(matches(host), "\(host)") }
    for host in ["notyoutube.com", "youtube.com.evil.example", "evilyoutube.com", "example.com", "teams.microsoft.com", "youtube.org"] { #expect(!matches(host), "\(host)") }
    // A pattern with quotes or backslashes cannot break out of the script it is put in.
    let hostile = YouTubeAdScript.source(hostPattern: "\"); alert(1); (\"")
    #expect(hostile.contains("new RegExp(\"\\\"); alert(1); (\\\"\")"))
}

@Test @MainActor func adBlockYouTubeAdContainersAreHiddenAndRealContentIsNot() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser(adBlocker: makeBlocker(port: port))
    browser.start()
    browser.go("http://127.0.0.1:\(port)/ytcss")
    #expect(await browserEventually { browser.title == "Css" && !browser.isLoading })
    #expect(await browserEventuallyAsking { await script(browser, "getComputedStyle(document.getElementById('ad')).display") == "none" })
    #expect(await script(browser, "getComputedStyle(document.getElementById('real')).display") == "block")
}

@Test @MainActor func adBlockAnAdThatStillPlaysIsSkippedThenSoundAndSpeedComeBack() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser(adBlocker: makeBlocker(port: port))
    browser.start()
    browser.go("http://127.0.0.1:\(port)/skip")
    #expect(await browserEventually { browser.title == "Skip" && !browser.isLoading })
    // While the ad shows: Skip is pressed, the ad is muted, sped up and sent to its end.
    #expect(await browserEventuallyAsking(timeout: 30) { await script(browser, "JSON.parse(window.state()).skipped ? 'yes' : 'no'") == "yes" })
    #expect(await browserEventuallyAsking(timeout: 30) { await script(browser, "JSON.parse(window.state()).time >= 29.9 ? 'yes' : 'no'") == "yes" })
    #expect(await script(browser, "String(JSON.parse(window.state()).muted)") == "true")
    #expect(await script(browser, "String(JSON.parse(window.state()).rate)") == "16")
    // The ad is over: the sound and the speed are put back.
    _ = await script(browser, "document.getElementById('movie_player').classList.remove('ad-showing'); 'ok'")
    #expect(await browserEventuallyAsking(timeout: 30) { await script(browser, "String(JSON.parse(window.state()).muted) + ',' + String(JSON.parse(window.state()).rate)") == "false,1" })
}

/// The browser shown the way the island shows it (in a window, through its SwiftUI view), not driven from code alone.
@MainActor private func showInPanel(_ browser: BrowserController) -> IslandPanel {
    _ = NSApplication.shared
    let hosting = NSHostingView(rootView: BrowserTab(controller: browser).frame(width: 900, height: 600).background(Color.black).preferredColorScheme(.dark))
    hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    let panel = IslandPanel()
    panel.setFrame(NSRect(x: -6000, y: -6000, width: 900, height: 600), display: false)
    panel.contentView = hosting
    panel.orderBack(nil)
    return panel
}

@Test @MainActor func adBlockAPageShownInTheRealViewIsProtectedFromItsVeryFirstRequest() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser(adBlocker: makeBlocker(port: port))
    let panel = showInPanel(browser)                            // the view is on screen BEFORE the first page is asked for
    defer { panel.orderOut(nil) }
    browser.start()
    browser.setVisible(true)
    browser.go("http://127.0.0.1:\(port)/adpage")
    #expect(await browserEventually { browser.title == "Ad page" && !browser.isLoading })
    #expect(await browserEventuallyAsking { await script(browser, "window.appLoaded === true ? 'yes' : 'no'") == "yes" })
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(await script(browser, "typeof window.adLoaded") == "undefined", "the first page after launch loaded unprotected")
    #expect(!site.requests.contains { $0.path.hasPrefix("/ads/") })
}

@Test @MainActor func adBlockTheYouTubeScriptIsAlsoOnTheFirstPageWhenShownInTheRealView() async throws {
    let site = LocalSite()
    let port = try await site.start()
    defer { site.stop() }
    let browser = makeBrowser(adBlocker: makeBlocker(port: port))
    let panel = showInPanel(browser)
    defer { panel.orderOut(nil) }
    browser.start()
    browser.setVisible(true)
    browser.go("http://127.0.0.1:\(port)/yt")
    #expect(await browserEventuallyAsking { await script(browser, "window.fetched ? 'yes' : 'no'") == "yes" })
    #expect(await script(browser, "typeof window.__islandAdBlock") == "boolean")
    #expect(await script(browser, "Object.keys(ytInitialPlayerResponse).join(',')") == "videoDetails")
}
