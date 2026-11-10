import Foundation
import Testing
@testable import IslandCore

private func resolved(_ text: String) -> BrowserAddress.Resolved { BrowserAddress.resolve(text) }

@Test func aBareWebsiteNameGetsHttpsAndAFullAddressIsKept() {
    #expect(resolved("teams.microsoft.com") == .page(URL(string: "https://teams.microsoft.com")!))
    #expect(resolved("  web.whatsapp.com  ") == .page(URL(string: "https://web.whatsapp.com")!))
    #expect(resolved("github.com/shipmnts/finance/pull/757") == .page(URL(string: "https://github.com/shipmnts/finance/pull/757")!))
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

@Test func onlyThePlaceOfAPageIsRememberedNeverWhatCameWithIt() throws {
    #expect(BrowserAddress.remembered(URL(string: "https://teams.microsoft.com/v2/?code=SECRET&state=x#id_token=T")!) == "https://teams.microsoft.com/v2/")
    #expect(BrowserAddress.remembered(URL(string: "https://user:pass@example.com/a/b?q=1")!) == "https://example.com/a/b")
    #expect(BrowserAddress.remembered(URL(string: "http://localhost:3000/x")!) == "http://localhost:3000/x")
    #expect(BrowserAddress.remembered(URL(string: "mailto:a@b.com")!) == nil)
    #expect(BrowserAddress.remembered(URL(string: "about:blank")!) == nil)
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
