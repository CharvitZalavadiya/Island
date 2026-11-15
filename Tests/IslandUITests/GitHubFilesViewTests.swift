import AppKit
import Foundation
import SwiftUI
import Testing
import IslandCore
@testable import IslandUI

// The review panel and the changed files: where there is room they are shown beside the review (and only then asked of GitHub),
// and in the usual small island nothing is spent on them.

private final class FilesHub: GitHubAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var fileCalls = 0
    var fileRequests: Int { lock.lock(); defer { lock.unlock() }; return fileCalls }
    private func countFileRequest() { lock.lock(); fileCalls += 1; lock.unlock() }

    let pull = GitHubPullRequest(number: 9, title: "Change", url: URL(string: "https://github.com/acme/app/pull/9")!, repoFullName: "acme/app", authorLogin: "ravi")
    /// The files the pull request changes (each with the same one-line change).
    var paths = ["Sources/App.swift"]
    func account(token: String) async throws -> GitHubAccount { GitHubAccount(login: "jane") }
    func repos(token: String) async throws -> [GitHubRepo] { [] }
    func repo(token: String, _ ref: GitHubRepoRef) async throws -> GitHubRepo { throw GitHubError.notFound }
    func branches(token: String, _ repo: GitHubRepoRef) async throws -> [GitHubBranch] { [] }
    func branch(token: String, _ repo: GitHubRepoRef, name: String) async throws -> GitHubBranch { throw GitHubError.notFound }
    func compare(token: String, _ repo: GitHubRepoRef, base: String, head: String) async throws -> GitHubComparison { throw GitHubError.notFound }
    func pullRequestTemplate(token: String, _ repo: GitHubRepoRef) async throws -> String? { nil }
    func createPullRequest(token: String, _ repo: GitHubRepoRef, title: String, head: String, base: String, body: String, draft: Bool) async throws -> GitHubPullRequest { throw GitHubError.notFound }
    func openPullRequest(token: String, _ repo: GitHubRepoRef, head: String, base: String) async throws -> GitHubPullRequest? { nil }
    func pullRequestLists(token: String) async throws -> GitHubPullRequestLists { GitHubPullRequestLists(mine: [], review: []) }
    func searchPullRequests(token: String, query: String) async throws -> [GitHubPullRequest] { [] }
    func pullRequest(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequest? { pull }
    func pullRequestDetails(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequestDetails { GitHubPullRequestDetails(pullRequest: pull, commits: 1) }
    func submitReview(token: String, _ repo: GitHubRepoRef, number: Int, event: GitHubReviewEvent, body: String) async throws -> GitHubReview { throw GitHubError.notFound }
    func pullRequestFiles(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> [GitHubChangedFile] {
        countFileRequest()
        return paths.map { path in
            GitHubChangedFile(filename: path, status: .modified, additions: 1, deletions: 1,
                hunks: GitHubDiff.hunks(fromPatch: "@@ -1,2 +1,2 @@\n a\n-b\n+c"))
        }
    }
}

private final class SavedToken: TokenStoring {
    func load() -> String? { "t" }
    func save(_ token: String) -> Bool { true }
    func delete() {}
}

@MainActor private func turnTheRunLoop() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }

/// Waits (up to `timeout`) for something that should happen in a window, letting the run loop turn meanwhile.
@MainActor private func eventually(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        turnTheRunLoop()
        try? await Task.sleep(nanoseconds: 15_000_000)
    }
    return condition()
}

/// The review panel in a window far off every screen, `width` wide (the width of the island's content area).
@MainActor private func host(_ controller: GitHubController, width: CGFloat) -> IslandPanel {
    _ = NSApplication.shared
    let hosting = NSHostingView(rootView: PullRequestReviewView(controller: controller).frame(width: width, height: 420).background(Color.black).preferredColorScheme(.dark))
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: 420)
    let panel = IslandPanel()
    panel.setFrame(NSRect(x: -9000, y: -9000, width: width, height: 420), display: false)
    panel.contentView = hosting
    panel.orderBack(nil)
    return panel
}

@Test @MainActor func inTheUsualSmallIslandTheChangedFilesAreNeverAskedFor() async {
    let hub = FilesHub()
    let controller = GitHubController(api: hub, tokens: SavedToken(), refreshInterval: 0)
    await controller.start()
    await controller.openReview(hub.pull)
    let panel = host(controller, width: 556)                                   // what the usual island's content area is
    defer { panel.orderOut(nil) }
    _ = await eventually(timeout: 1) { false }                                 // give a (wrong) request every chance to be made
    #expect(controller.reviewFiles == .idle && hub.fileRequests == 0)
}

@Test @MainActor func whenTheIslandIsBigTheChangedFilesLoadAndAreShown() async {
    let hub = FilesHub()
    let controller = GitHubController(api: hub, tokens: SavedToken(), refreshInterval: 0)
    await controller.start()
    await controller.openReview(hub.pull)
    let panel = host(controller, width: 1100)
    defer { panel.orderOut(nil) }
    let loaded = await eventually { if case .loaded = controller.reviewFiles { return true } else { return false } }
    #expect(loaded && hub.fileRequests == 1)
}

@Test @MainActor func theFilesOfAReviewAreAskedForOnlyOnceHoweverOftenThePanelResizes() async {
    let hub = FilesHub()
    let controller = GitHubController(api: hub, tokens: SavedToken(), refreshInterval: 0)
    await controller.start()
    await controller.openReview(hub.pull)
    let panel = host(controller, width: 1100)
    defer { panel.orderOut(nil) }
    _ = await eventually { if case .loaded = controller.reviewFiles { return true } else { return false } }
    panel.setContentSize(NSSize(width: 556, height: 420))
    panel.setContentSize(NSSize(width: 1100, height: 420))
    _ = await eventually(timeout: 0.6) { false }
    #expect(hub.fileRequests == 1)
}

@Test func theWidthThatShowsTheFilesIsBetweenTheUsualIslandAndAMaxIslandOnASmallScreen() {
    // The usual island's content is 556 wide (620 less its padding): never enough. Max is 80 % of the screen less the same padding:
    // a 1280-wide screen gives 960, and focus mode (95 %) more.
    let usualContent = IslandMetrics.expandedSize.width - 2 * (18 + NotchShape.expanded.top)
    let smallScreenMax = 1280 * 0.8 - 64
    #expect(PullRequestReviewView.sideBySideWidth > usualContent)
    #expect(PullRequestReviewView.sideBySideWidth < smallScreenMax)
}

// MARK: What is drawn

/// How many separate green bands (the added lines) there are down one column of the picture: one per file that shows its changes.
private func greenBands(_ rep: NSBitmapImageRep, x: Int) -> Int {
    var bands = 0, inBand = false
    for y in 0..<rep.pixelsHigh {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let green = c.greenComponent > c.redComponent * 2 && c.greenComponent > c.blueComponent * 1.3 && c.greenComponent > 0.07
        if green && !inBand { bands += 1 }
        inBand = green
    }
    return bands
}

/// The review panel drawn at `size` (tall enough for every file to be on screen), in a window nobody sees.
@MainActor private func draw(_ controller: GitHubController, size: CGSize = CGSize(width: 1300, height: 1700)) -> (NSHostingView<AnyView>, NSWindow) {
    _ = NSApplication.shared
    let content = PullRequestReviewView(controller: controller).padding(18).frame(width: size.width, height: size.height)
        .background(Color.black).preferredColorScheme(.dark)
    let host = NSHostingView(rootView: AnyView(content))
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false                                       // closing must not release it a second time (ARC owns it)
    window.contentView = host
    return (host, window)
}

@MainActor private func addedLineBands(in host: NSView) -> Int {
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
    host.cacheDisplay(in: host.bounds, to: rep)
    return greenBands(rep, x: Int(Double(rep.pixelsWide) * 0.9))
}

private func firstField(in view: NSView) -> FocusingTextField? {
    if let field = view as? FocusingTextField { return field }
    for child in view.subviews { if let found = firstField(in: child) { return found } }
    return nil
}

/// What typing in the box does, without a keyboard: the text is put in and the box says it changed.
@MainActor private func type(_ text: String, into host: NSView) {
    guard let field = firstField(in: host) else { return }
    field.stringValue = text
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
}

@MainActor private func reviewing(_ paths: [String]) async -> (GitHubController, FilesHub) {
    let hub = FilesHub()
    hub.paths = paths
    let controller = GitHubController(api: hub, tokens: SavedToken(), refreshInterval: 0)
    await controller.start()
    await controller.openReview(hub.pull)
    await controller.loadReviewFiles()
    return (controller, hub)
}

@Test @MainActor func everyFilesChangesAreDrawnNotOnlyTheFirstOnes() async {
    // Each file numbers its hunks and lines from 0: with no id that is unique across the list, only the first file's rows were
    // built and every other file showed its name bar with an empty box under it.
    let (controller, _) = await reviewing(["a/one.yaml", "a/two.yaml", "b/three.yaml", "b/four.yaml"])
    let (host, window) = draw(controller)
    defer { window.close() }
    let all = await eventually(timeout: 15) { addedLineBands(in: host) == 4 }
    #expect(all, "drawn changes: \(addedLineBands(in: host)) of 4 files")
}

@Test @MainActor func typingAFileNameShowsOnlyThoseFilesAndClearingTheBoxShowsAllOfThemAgain() async {
    let (controller, _) = await reviewing(["api/routes/alpha.yaml", "api/routes/beta.yaml", "web/gamma.yaml", "web/delta.yaml"])
    let (host, window) = draw(controller)
    defer { window.close() }
    #expect(await eventually(timeout: 15) { addedLineBands(in: host) == 4 })

    type("web/", into: host)                                              // a folder: two files
    #expect(await eventually(timeout: 15) { addedLineBands(in: host) == 2 })
    type("GAMMA", into: host)                                             // a name, in capitals: one file
    #expect(await eventually(timeout: 15) { addedLineBands(in: host) == 1 })
    type("no-such-file", into: host)                                      // nothing matches: no changes shown at all
    #expect(await eventually(timeout: 15) { addedLineBands(in: host) == 0 })
    type("", into: host)                                                  // cleared: every file again
    #expect(await eventually(timeout: 15) { addedLineBands(in: host) == 4 })
}

@Test @MainActor func theFilterBoxWaitsToBeClickedInsteadOfTakingTheKeyboard() async {
    let (controller, _) = await reviewing(["a/one.yaml", "a/two.yaml"])
    let (host, window) = draw(controller, size: CGSize(width: 1300, height: 700))
    defer { window.close() }
    _ = await eventually(timeout: 15) { firstField(in: host) != nil }
    #expect(firstField(in: host)?.focusesOnAppear == false)                // opening the files must not grab typing from your other app
}
