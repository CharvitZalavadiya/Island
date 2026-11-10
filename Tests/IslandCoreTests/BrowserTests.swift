import Foundation
import Testing
@testable import IslandCore

private func resolved(_ text: String) -> BrowserAddress.Resolved { BrowserAddress.resolve(text) }

@Test func aBareWebsiteNameGetsHttpsAndAFullAddressIsKept() {
    #expect(resolved("teams.microsoft.com") == .page(URL(string: "https://teams.microsoft.com")!))
    #expect(resolved("  web.whatsapp.com  ") == .page(URL(string: "https://web.whatsapp.com")!))
    #expect(resolved("github.com/acme/finance/pull/757") == .page(URL(string: "https://github.com/acme/finance/pull/757")!))
    #expect(resolved("example.com:8443/a?b=1#c") == .page(URL(string: "https://example.com:8443/a?b=1#c")!))
    #expect(resolved("https://teams.microsoft.com/v2/") == .page(URL(string: "https://teams.microsoft.com/v2/")!))
    #expect(resolved("HTTP://Example.com/x") == .page(URL(string: "HTTP://Example.com/x")!))
}

@Test func thisMacAndLocalMachinesGetPlainHttp() {
    #expect(resolved("localhost:3000") == .page(URL(string: "http://localhost:3000")!))
    #expect(resolved("localhost") == .page(URL(string: "http://localhost")!))
    #expect(resolved("192.168.1.10:8080/admin") == .page(URL(string: "http://192.168.1.10:8080/admin")!))
}

@Test func wordsAreSearchedFor() throws {
    for words in ["swift concurrency", "what.is this", "teams", "localhost is where", "1.5", "a/b"] {
        guard case .search(let url) = resolved(words) else { Issue.record("\(words) should be a search"); continue }
        #expect(url.host == "www.google.com" && url.path == "/search")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == words)
    }
    // Characters that would break an address are carried safely.
    guard case .search(let url) = resolved("c++ & rust = ?") else { Issue.record("search"); return }
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "c++ & rust = ?")
    #expect(!url.absoluteString.contains(" "))
}

@Test func onlyWebAddressesAreOpened() {
    for other in ["file:///etc/passwd", "javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,<h1>x</h1>", "mailto:a@b.com", "about:blank", "ftp://example.com/x", "msteams://teams.microsoft.com/l/chat", "view-source:https://example.com"] {
        #expect(resolved(other) == .unsupported, "\(other)")
    }
    #expect(resolved("") == .empty)
    #expect(resolved("   \n ") == .empty)
}

@Test func aKeptAddressHasNoSecretsButKeepsTheHarmlessQuery() throws {
    func kept(_ text: String) -> String? { BrowserAddress.kept(URL(string: text)!) }
    #expect(kept("https://teams.microsoft.com/v2/?code=SECRET&state=x#id_token=T") == "https://teams.microsoft.com/v2/")
    #expect(kept("https://user:pass@example.com/a/b?q=1") == "https://example.com/a/b?q=1")            // a password never; a harmless query stays
    #expect(kept("https://example.com/search?q=swift&token=ABC&page=2&SID=9") == "https://example.com/search?q=swift&page=2")
    #expect(kept("https://example.com/docs#installation") == "https://example.com/docs#installation")   // an ordinary anchor stays
    #expect(kept("https://example.com/cb#access_token=ABC&type=bearer") == "https://example.com/cb")    // a fragment carrying values goes
    #expect(kept("http://localhost:3000/x") == "http://localhost:3000/x")
    #expect(kept("mailto:a@b.com") == nil)
    #expect(kept("about:blank") == nil)
}

@Test func linksFollowTheRulesOfASafeBrowser() {
    func nav(_ text: String, click: Bool = false, command: Bool = false, main: Bool = true, download: Bool = false) -> BrowserPolicy.Navigation {
        BrowserPolicy.navigation(to: URL(string: text), isLinkClick: click, commandHeld: command, isMainFrame: main, wantsDownload: download)
    }
    #expect(nav("https://example.com", click: true) == .allow)
    #expect(nav("https://example.com", click: true, command: true) == .openElsewhere)      // Command-click: my own browser
    #expect(nav("https://example.com", command: true) == .allow)                            // Command held while a page redirects: nothing to do with it
    #expect(nav("https://example.com/report.pdf", click: true, download: true) == .openElsewhere)
    #expect(nav("about:blank") == .allow && nav("blob:https://x/1") == .allow && nav("javascript:void(0)", click: true) == .allow)
    #expect(nav("data:text/html,hi", main: true) == .cancel)                                // a page may not take the view over with data:
    #expect(nav("data:image/png;base64,AA==", main: false) == .allow)                       // but may use it inside itself
    #expect(nav("file:///Users/me/secret.txt", click: true) == .cancel)
    #expect(nav("mailto:a@b.com", click: true) == .openElsewhere)                           // a click may open the mail app...
    #expect(nav("msteams://teams.microsoft.com/l/x", click: false) == .cancel)              // ...a page doing it by itself may not launch apps
    #expect(BrowserPolicy.navigation(to: nil, isLinkClick: true, commandHeld: false, isMainFrame: true) == .cancel)
}

@Test func filesToDownloadAreHandedToTheDefaultBrowser() {
    #expect(BrowserPolicy.opensElsewhere(canShow: false, contentDisposition: nil))                       // a type the view cannot show
    #expect(BrowserPolicy.opensElsewhere(canShow: true, contentDisposition: "attachment; filename=\"a.pdf\""))
    #expect(BrowserPolicy.opensElsewhere(canShow: true, contentDisposition: "  ATTACHMENT"))
    #expect(!BrowserPolicy.opensElsewhere(canShow: true, contentDisposition: "inline"))
    #expect(!BrowserPolicy.opensElsewhere(canShow: true, contentDisposition: nil))
}

@Test func theMaxIslandIsMostOfTheScreenHangingFromTheTopCenteredOnTheNotch() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let usual = CGSize(width: 620, height: 330)
    let size = NotchGeometry.maxSize(screenFrame: screen, minimum: usual)
    #expect(abs(size.width - 1209.6) < 0.01 && abs(size.height - 785.6) < 0.01)    // 80% each way

    let notch = CGRect(x: 656, y: 950, width: 200, height: 32)
    let frame = NotchGeometry.expandedFrame(notch: notch, screenFrame: screen, size: size)
    #expect(frame.size == size)
    #expect(abs(frame.midX - notch.midX) < 0.01)                                    // centered on the notch
    #expect(frame.maxY == screen.maxY)                                              // flush with the top edge
    #expect(screen.contains(frame))                                                 // and on the screen

    // A notch far from the middle (another arrangement) still keeps the island on the screen.
    let farNotch = CGRect(x: 1400, y: 950, width: 100, height: 32)
    #expect(screen.contains(NotchGeometry.expandedFrame(notch: farNotch, screenFrame: screen, size: size)))
    // A tiny screen never makes it smaller than the usual island.
    let tiny = NotchGeometry.maxSize(screenFrame: CGRect(x: 0, y: 0, width: 600, height: 400), minimum: usual)
    #expect(tiny == CGSize(width: 620, height: 330))
}

// MARK: Tabs and bookmarks

private func ids(_ entries: [BrowserTabList.Entry]) -> [UUID] { entries.map(\.id) }

@Test func aFreshListHasOneBlankSelectedTabNoBookmarksAndTheSidebarIsOff() {
    let list = BrowserTabList.fresh()
    #expect(list.open.count == 1 && list.bookmarks.isEmpty && list.selected == list.open[0].id && list.open[0].url == nil)
    #expect(!list.sidebarOpen)
    #expect(BrowserTabList.fresh(url: "https://a.com").open[0].url == "https://a.com")
}

@Test func aNewTabGoesNextToTheOneItWasOpenedFromAndIsSelected() {
    var list = BrowserTabList.fresh()
    let first = list.open[0].id
    let third = list.addOpen()
    let second = list.addOpen(after: first)
    #expect(ids(list.open) == [first, second, third] && list.selected == second)
    let popup = list.addOpen(select: false, after: UUID())                    // unknown opener: last
    #expect(list.open.last?.id == popup && list.selected == second)
}

@Test func closingATabSelectsItsNeighbourAndUnknownOnesChangeNothing() {
    var list = BrowserTabList.fresh(url: "a")
    let a = list.open[0].id
    let b = list.addOpen(url: "b"), c = list.addOpen(url: "c")
    list.select(b)
    let closedB = list.close(b)
    #expect(closedB)
    #expect(ids(list.open) == [a, c] && list.selected == c)                     // the one that moved into its place
    let closedC = list.close(c)
    #expect(closedC && list.selected == a)                                      // the last one: the one before
    let unknown = list.close(UUID())
    #expect(!unknown && list.selected == a)
}

@Test func closingEveryTabByMistakeLeavesTheBookmarksAndABlankTab() {
    var list = BrowserTabList.fresh(url: "https://teams.microsoft.com/v2/")
    list.toggleBookmark(title: "Microsoft Teams", url: "https://teams.microsoft.com/v2/")
    list.toggleBookmark(title: "WhatsApp", url: "https://web.whatsapp.com/")
    let teams = list.open[0].id
    let notes = list.addOpen(url: "https://notes.example.com/")
    list.select(notes)

    let closedNotes = list.close(notes)
    let closedTeams = list.close(teams)                                         // everything closed
    #expect(closedNotes && closedTeams)
    #expect(list.bookmarks.count == 2)                                          // the bookmarks are not tabs: untouched
    #expect(list.open.count == 1 && list.open[0].url == nil && list.selected == list.open[0].id)   // a blank tab to look at
}

@Test func theStarBookmarksAPageOnceAndRemovesItAgain() {
    var list = BrowserTabList.fresh()
    let nowBookmarked = list.toggleBookmark(title: "Microsoft Teams", url: "https://teams.microsoft.com/v2/")
    #expect(nowBookmarked && list.bookmarks.count == 1 && list.bookmarks[0].title == "Microsoft Teams")
    #expect(list.bookmark(for: "https://teams.microsoft.com/v2")?.id == list.bookmarks[0].id)            // a trailing slash is the same page
    #expect(list.bookmark(for: "https://www.teams.microsoft.com/v2/#chat") != nil)                        // so are www. and an anchor
    #expect(list.bookmark(for: "https://teams.microsoft.com/v2/?x=1") == nil)                             // another query is another page
    let again = list.addBookmark(title: "Teams again", url: "https://teams.microsoft.com/v2")
    #expect(!again && list.bookmarks.count == 1)                                // never two for one page
    let afterSecondTap = list.toggleBookmark(title: "ignored", url: "https://teams.microsoft.com/v2/")
    #expect(!afterSecondTap && list.bookmarks.isEmpty)
}

@Test func anOpenTabOnABookmarkedPageIsFoundSoItIsNotOpenedTwice() {
    var list = BrowserTabList.fresh(url: "https://web.whatsapp.com/")
    let id = list.open[0].id
    #expect(list.openTab(on: "https://web.whatsapp.com")?.id == id)
    #expect(list.openTab(on: "https://teams.microsoft.com") == nil)
    list.update(id, url: "https://github.com/a/b", title: "A repo")
    #expect(list.openTab(on: "https://web.whatsapp.com") == nil && list.entry(id)?.title == "A repo")
}

@Test func samePageMeansSameSitePathAndQueryNothingMore() {
    #expect(BrowserAddress.sameDestination("https://a.com/x/", "http://www.a.com/x#top"))
    #expect(BrowserAddress.sameDestination("https://A.com", "https://a.com/"))
    #expect(!BrowserAddress.sameDestination("https://a.com/x", "https://a.com/y"))
    #expect(!BrowserAddress.sameDestination("https://a.com/x?q=1", "https://a.com/x?q=2"))
    #expect(!BrowserAddress.sameDestination("https://a.com:8080/x", "https://a.com/x"))
    #expect(BrowserAddress.sameDestination("not a url", "not a url"))
}

@Test func aSavedListThatPointsNowhereIsRepaired() {
    var empty = BrowserTabList()
    empty.repair()
    #expect(empty.open.count == 1 && empty.selected == empty.open[0].id)

    let a = UUID()
    var dangling = BrowserTabList(open: [BrowserTabList.Entry(id: a, url: "https://a.com")], selected: UUID())
    dangling.repair()
    #expect(dangling.selected == a)
}

@Test func theTabListSurvivesBeingSavedAndReadBack() throws {
    var list = BrowserTabList.fresh(url: "https://a.com")
    list.toggleBookmark(title: "A", url: "https://a.com/home")
    list.addOpen(url: "https://b.com")
    list.sidebarOpen = true
    let decoded = try JSONDecoder().decode(BrowserTabList.self, from: JSONEncoder().encode(list))
    #expect(decoded == list && decoded.sidebarOpen && decoded.bookmarks.count == 1)
}

@Test func pinnedTabsFromThePreviousVersionBecomeBookmarksAndTheOpenOneStaysOpen() throws {
    let teams = UUID(), whatsapp = UUID(), notes = UUID()
    let old = """
    {"selected":"\(teams.uuidString)","sidebarOpen":true,
     "pinned":[{"id":"\(teams.uuidString)","url":"https://teams.microsoft.com/v2/","title":"Microsoft Teams"},
               {"id":"\(whatsapp.uuidString)","url":"https://web.whatsapp.com/","title":"WhatsApp Web"},
               {"id":"\(UUID().uuidString)","title":"never had an address"}],
     "open":[{"id":"\(notes.uuidString)","url":"https://notes.example.com/","title":"Notes"}]}
    """
    var list = try JSONDecoder().decode(BrowserTabList.self, from: Data(old.utf8))
    list.repair()
    #expect(list.bookmarks.map(\.title) == ["Microsoft Teams", "WhatsApp Web"])      // the one with no address is dropped
    #expect(list.sidebarOpen)
    #expect(ids(list.open) == [notes, teams])                                      // what was showing stays open as an ordinary tab
    #expect(list.selected == teams)
    // Written out again it is the new format (no "pinned").
    let written = String(decoding: try JSONEncoder().encode(list), as: UTF8.self)
    #expect(!written.contains("pinned") && written.contains("bookmarks"))
}

@Test func theTabsAreOnTheSideAtFirstAndTheChoiceIsSavedAndOlderFilesReadAsTheSide() throws {
    #expect(!BrowserTabList.fresh().tabsOnTop)
    var list = BrowserTabList.fresh(url: "https://a.com")
    list.tabsOnTop = true
    let decoded = try JSONDecoder().decode(BrowserTabList.self, from: JSONEncoder().encode(list))
    #expect(decoded.tabsOnTop && decoded == list)
    // A file saved before the choice existed has no such key: the tabs stay where they were (the side).
    let old = try JSONDecoder().decode(BrowserTabList.self, from: Data(#"{"open":[{"id":"\#(UUID().uuidString)","title":"A"}],"sidebarOpen":true}"#.utf8))
    #expect(!old.tabsOnTop && old.sidebarOpen)
}

@Test func clearingATabTakesItBackToBlankAndLeavesTheRestAlone() {
    var list = BrowserTabList.fresh(url: "https://a.com")
    let id = list.open[0].id
    list.update(id, url: "https://a.com/x", title: "A page")
    let other = list.addOpen(url: "https://b.com")
    list.toggleBookmark(title: "B", url: "https://b.com")
    list.clear(id)
    #expect(list.entry(id)?.url == nil && list.entry(id)?.title == "")
    #expect(list.entry(other)?.url == "https://b.com" && list.bookmarks.count == 1 && list.open.count == 2)
    list.clear(UUID())                                                         // an unknown tab changes nothing
    #expect(list.open.count == 2)
}
