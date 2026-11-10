import Testing
import AppKit
import SwiftUI
import IslandCore
@testable import IslandUI

// MARK: A small stand-in for GitHub

private final class Hub: GitHubAPI, @unchecked Sendable {
    let blog = GitHubRepo(id: 4, fullName: "octocat/blog", owner: "octocat", name: "blog", defaultBranch: "master")
    var pull: GitHubPullRequest { GitHubPullRequest(number: 482, title: "Friend's change", url: URL(string: "https://github.com/octocat/blog/pull/482")!, repoFullName: "octocat/blog", authorLogin: "ravi-k") }
    func account(token: String) async throws -> GitHubAccount { GitHubAccount(login: "jane") }
    func repos(token: String) async throws -> [GitHubRepo] { [GitHubRepo(id: 1, fullName: "acme/finance", owner: "acme", name: "finance")] }
    func repo(token: String, _ ref: GitHubRepoRef) async throws -> GitHubRepo {
        guard ref.fullName.lowercased() == "octocat/blog" else { throw GitHubError.notFound }
        return blog
    }
    func branches(token: String, _ repo: GitHubRepoRef) async throws -> [GitHubBranch] { [] }
    func branch(token: String, _ repo: GitHubRepoRef, name: String) async throws -> GitHubBranch { throw GitHubError.notFound }
    func compare(token: String, _ repo: GitHubRepoRef, base: String, head: String) async throws -> GitHubComparison { throw GitHubError.notFound }
    func pullRequestTemplate(token: String, _ repo: GitHubRepoRef) async throws -> String? { nil }
    func createPullRequest(token: String, _ repo: GitHubRepoRef, title: String, head: String, base: String, body: String, draft: Bool) async throws -> GitHubPullRequest { throw GitHubError.notFound }
    func openPullRequest(token: String, _ repo: GitHubRepoRef, head: String, base: String) async throws -> GitHubPullRequest? { nil }
    func pullRequestLists(token: String) async throws -> GitHubPullRequestLists { GitHubPullRequestLists(mine: [], review: []) }
    func searchPullRequests(token: String, query: String) async throws -> [GitHubPullRequest] { [] }
    func pullRequest(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequest? { number == 482 ? pull : nil }
    func pullRequestDetails(token: String, _ repo: GitHubRepoRef, number: Int) async throws -> GitHubPullRequestDetails { GitHubPullRequestDetails(pullRequest: pull, commits: 2) }
    func submitReview(token: String, _ repo: GitHubRepoRef, number: Int, event: GitHubReviewEvent, body: String) async throws -> GitHubReview { throw GitHubError.notFound }
}

private final class StoredToken: TokenStoring {
    func load() -> String? { "t" }
    func save(_ token: String) -> Bool { true }
    func delete() {}
}

/// Waits (up to `timeout`) for something that should happen in a window, letting the run loop turn meanwhile.
@MainActor private func eventually(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try? await Task.sleep(nanoseconds: 15_000_000)
    }
    return condition()
}

private func firstSearchField(in view: NSView) -> FocusingTextField? {
    if let field = view as? FocusingTextField { return field }
    for child in view.subviews { if let found = firstSearchField(in: child) { return found } }
    return nil
}

/// The island's own kind of window (a non-activating panel), far off every screen, holding `content`.
@MainActor private func hostInPanel<V: View>(_ content: V) -> (IslandPanel, NSHostingView<some View>) {
    _ = NSApplication.shared
    let framed = content.padding(17).frame(width: 520, height: 262).background(Color.black).preferredColorScheme(.dark)
    let hosting = NSHostingView(rootView: framed)
    hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 262)
    let panel = IslandPanel()
    panel.setFrame(NSRect(x: -6000, y: -6000, width: 520, height: 262), display: false)
    panel.contentView = hosting
    panel.orderBack(nil)
    return (panel, hosting)
}

@MainActor private func makeModel() -> IslandModel {
    IslandModel(settings: SettingsStore(store: FileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("v-\(UUID()).json"), defaultValue: Settings())))
}

// MARK: Tests

@Test @MainActor func theRepositoryPickersSearchBoxTakesTheKeyboardByItself() async {
    let controller = GitHubController(api: Hub(), tokens: StoredToken(), refreshInterval: 0)
    await controller.start()
    let model = makeModel()
    model.selectedTab = .github
    // The tab bar sits above the picker, as in the island: the keyboard must not end up on its first tab (Pomodoro).
    let (panel, _) = hostInPanel(VStack(spacing: 10) {
        TabBar(model: model, openSettings: {})
        PickerList(controller: controller, kind: .searchRepository, onDone: {})
    })
    defer { panel.orderOut(nil) }
    let focused = await eventually { (panel.firstResponder as? NSTextView)?.delegate is FocusingTextField }
    #expect(focused, "the search box did not take the keyboard; focus is on \\(String(describing: panel.firstResponder))")
    #expect(model.selectedTab == .github)                                       // and no tab was switched on the way
}

/// Something a test can change from outside while a view shows it.
private final class Request: ObservableObject {
    @Published var number = 0
}

@Test @MainActor func aSearchBoxOnlyTakesTheKeyboardWhenToldTo() async {
    struct Probe: View {
        @ObservedObject var request: Request
        @State private var text = ""
        var body: some View {
            SearchField(text: $text, placeholder: "Search", focusesOnAppear: false, focusRequest: request.number)
        }
    }
    let request = Request()
    let (panel, _) = hostInPanel(Probe(request: request))
    defer { panel.orderOut(nil) }
    func searchBoxHasKeyboard() -> Bool { (panel.firstResponder as? NSTextView)?.delegate is FocusingTextField }

    // A box that appears with focusesOnAppear off (the Search section, which must not grab the keyboard just by being
    // opened) leaves it alone...
    try? await Task.sleep(nanoseconds: 400_000_000)
    #expect(!searchBoxHasKeyboard())
    // ...until it is asked (after a repository was chosen, the next thing to do is type).
    request.number += 1
    #expect(await eventually { searchBoxHasKeyboard() }, "asking did not give the search box the keyboard")
}

@Test @MainActor func searchShowsOnlyTheRepositoryBarUntilARepositoryIsChosen() async {
    let controller = GitHubController(api: Hub(), tokens: StoredToken(), refreshInterval: 0)
    await controller.start()
    controller.section = .search
    let (panel, hosting) = hostInPanel(GitHubTab(controller: controller))
    defer { panel.orderOut(nil) }

    try? await Task.sleep(nanoseconds: 400_000_000)       // long enough for a (wrongly) shown box to appear and take the keyboard
    #expect(controller.searchRepo == nil)
    #expect(firstSearchField(in: hosting) == nil, "a second search box is showing before any repository is chosen")

    controller.selectSearchRepo(GitHubRepo(id: 9, fullName: "octocat/blog", owner: "octocat", name: "blog", isPrivate: false))
    let shown = await eventually { firstSearchField(in: hosting) != nil }
    #expect(shown, "the search box should appear once a repository is chosen")
}

@Test @MainActor func pastingAPullRequestLinkIntoTheSearchRepositoryPickerChoosesItsRepositoryAndOpensTheReview() async {
    let controller = GitHubController(api: Hub(), tokens: StoredToken(), refreshInterval: 0)
    await controller.start()
    var closed = false
    let (panel, hosting) = hostInPanel(PickerList(controller: controller, kind: .searchRepository, onDone: { closed = true }))
    defer { panel.orderOut(nil) }

    let appeared = await eventually { firstSearchField(in: hosting) != nil }
    #expect(appeared, "the picker's search box was not shown")
    #expect(controller.searchRepo == nil)

    // Paste: the whole link arrives at once, as AppKit reports it. No Return needed.
    guard let field = firstSearchField(in: hosting) else { return }
    field.stringValue = "https://github.com/octocat/blog/pull/482"
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))

    let opened = await eventually { controller.reviewTarget?.number == 482 }
    #expect(opened, "the review panel did not open; message: \(String(describing: controller.message?.text))")
    #expect(controller.searchRepo?.fullName == "octocat/blog")                  // the repository was chosen too
    #expect(controller.message == nil)
    #expect(closed)                                                             // and the picker got out of the way
}

@Test @MainActor func aPullRequestLinkTypedByHandOnlyOpensWhenReturnIsPressed() async {
    let controller = GitHubController(api: Hub(), tokens: StoredToken(), refreshInterval: 0)
    await controller.start()
    let (panel, hosting) = hostInPanel(PickerList(controller: controller, kind: .searchRepository, onDone: {}))
    defer { panel.orderOut(nil) }
    _ = await eventually { firstSearchField(in: hosting) != nil }
    guard let field = firstSearchField(in: hosting) else { return }

    // One key at a time: "…/pull/4" is already a link to #4, but #482 is what is being typed.
    let link = "https://github.com/octocat/blog/pull/482"
    for end in link.indices {
        field.stringValue = String(link[...end])
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))   // each key is its own event: SwiftUI sees them one by one
    }
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(controller.reviewTarget == nil, "typing opened a pull request before Return")
    #expect(controller.searchRepo == nil)

    _ = field.delegate?.control?(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    let opened = await eventually { controller.reviewTarget?.number == 482 }
    #expect(opened, "Return did not open the pull request")
    #expect(controller.searchRepo?.fullName == "octocat/blog")
}
