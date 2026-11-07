import AppKit
import Foundation
import Observation
import IslandCore

/// The GitHub tab: the connection, the form for a new pull request, and the person's own pull requests.
///
/// - Connecting takes a personal access token (pasted from GitHub's settings), checks it with GitHub, and keeps it in the
///   Keychain. Nothing is read from the Keychain until the tab is first opened.
/// - A new pull request: choose a repository (any the account can push to), a base branch (the default is offered) and the
///   branch to merge, and Island shows how many commits and files it carries, fills in a title, and the repository's
///   pull request template as the description. Creating it gives the link to copy.
/// - A token GitHub stops accepting is forgotten and the connect screen comes back.
@Observable
@MainActor
final class GitHubController {
    enum Connection: Equatable {
        case disconnected
        /// A pasted token is being checked.
        case connecting
        case connected
    }

    enum Section: Hashable {
        case newPullRequest
        case mine
        case reviewRequests
        case search
    }

    enum Comparison: Equatable {
        case none
        case loading
        case ready(GitHubComparison)
        case failed(String)
    }

    enum Creation: Equatable {
        case idle
        case creating
        case created(GitHubPullRequest)
    }

    struct Message: Equatable {
        var text: String
        var isError: Bool
        /// A button that goes with the message (such as authorising a token for single sign-on).
        var action: Action?

        struct Action: Equatable {
            var title: String
            var url: URL
        }
    }

    var section: Section = .newPullRequest
    private(set) var connection: Connection = .disconnected
    private(set) var account: GitHubAccount?
    private(set) var message: Message?
    /// True once Island has looked for a saved token, so the view shows neither screen until it knows which one is right.
    private(set) var isReady = false

    // The new pull request
    private(set) var repos: [GitHubRepo] = []
    private(set) var reposLoaded = false
    private(set) var reposLoading = false
    private(set) var repo: GitHubRepo?
    private(set) var branches: [GitHubBranch] = []
    private(set) var branchesLoading = false
    private(set) var base: String?
    private(set) var head: String?
    private(set) var title = ""
    private(set) var body = ""
    var isDraft = false
    private(set) var comparison: Comparison = .none
    /// The pull request that already exists for the chosen branches, when creating one was refused for that reason.
    private(set) var existingPullRequest: GitHubPullRequest?
    private(set) var creation: Creation = .idle
    /// Whether a lookup of a typed repository or branch is under way.
    private(set) var isLookingUp = false

    // The person's pull requests
    private(set) var myPullRequests: [GitHubPullRequest] = []
    private(set) var reviewRequests: [GitHubPullRequest] = []
    private(set) var listsLoaded = false
    private(set) var listsLoading = false

    // Searching one repository's pull requests (its repository is chosen separately from the New PR form's)
    private(set) var searchRepo: GitHubRepo?
    /// Search only the open ones, or every one (closed and merged too).
    var searchOpenOnly = true
    private(set) var searchResults: [GitHubPullRequest] = []
    private(set) var isSearching = false
    /// True once a search has answered for the current repository.
    private(set) var searchLoaded = false
    @ObservationIgnored private var searchGeneration = 0

    /// The pull request whose link was just copied (the button says "Copied" for a moment).
    private(set) var copiedID: String?

    @ObservationIgnored private let api: GitHubAPI
    @ObservationIgnored private let tokens: TokenStoring
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let writeToClipboard: (String) -> Void
    @ObservationIgnored private let refreshInterval: TimeInterval
    @ObservationIgnored private let copiedSeconds: TimeInterval
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var tokenLoaded = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pausedUntil = Date.distantPast
    @ObservationIgnored private var titleEdited = false
    @ObservationIgnored private var bodyEdited = false
    /// Bumped whenever the repository or either branch changes, so a late answer about an earlier choice is ignored.
    @ObservationIgnored private var choiceGeneration = 0
    @ObservationIgnored private var copiedGeneration = 0

    init(
        api: GitHubAPI = URLSessionGitHubAPI(), tokens: TokenStoring = KeychainTokenStore(forService: "github"),
        now: @escaping () -> Date = Date.init, refreshInterval: TimeInterval = 120, copiedSeconds: TimeInterval = 1.5,
        writeToClipboard: @escaping (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.api = api
        self.tokens = tokens
        self.now = now
        self.refreshInterval = refreshInterval
        self.copiedSeconds = copiedSeconds
        self.writeToClipboard = writeToClipboard
    }

    // MARK: What the form offers

    /// Repositories a pull request can start from, matching what was typed, the most recently pushed first.
    func pickableRepos(matching query: String) -> [GitHubRepo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return repos.filter { $0.canTakePullRequests && (needle.isEmpty || $0.fullName.lowercased().contains(needle)) }
    }

    /// Branches matching what was typed. The base branch is left out of the "merge from" list (it cannot merge into
    /// itself), and the repository's default branch comes first.
    func branches(matching query: String, excludingBase: Bool) -> [GitHubBranch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let defaultName = repo?.defaultBranch
        return branches
            .filter { (!excludingBase || $0.name != base) && (needle.isEmpty || $0.name.lowercased().contains(needle)) }
            .sorted { lhs, rhs in
                if (lhs.name == defaultName) != (rhs.name == defaultName) { return lhs.name == defaultName }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether Create can be pressed: a repository, two different branches, a title, and nothing under way.
    var canCreate: Bool {
        guard connection == .connected, repo != nil, let base, let head, base != head, !trimmedTitle.isEmpty, creation != .creating else {
            return false
        }
        if case .ready(let comparison) = comparison { return comparison.hasChanges }
        if case .loading = comparison { return false }
        return true
    }

    // MARK: Opening and closing the tab

    /// The tab is on screen: look for a saved token, check who it is, and load what the current section shows.
    func start() async {
        loadTokenIfNeeded()
        guard connection == .connected else { return }
        scheduleTimer()
        if account == nil { await refreshAccount() }
        guard connection == .connected else { return }
        await loadForCurrentSection()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Loads what the section on screen needs (the repositories for a new pull request, the lists for the others).
    func loadForCurrentSection() async {
        switch section {
        case .newPullRequest:
            // The repositories to choose from, and the person's own pull requests (their counts show in the header).
            async let repositories: Void = loadRepos()
            async let pullRequests: Void = loadListsIfNeeded()
            _ = await (repositories, pullRequests)
        case .mine, .reviewRequests:
            await refreshLists()
        case .search:
            await loadRepos()
            // Searching starts in the repository the new pull request is for, if one was chosen.
            if searchRepo == nil, let repo { selectSearchRepo(repo) }
        }
    }

    // MARK: Connecting

    func connect(token pasted: String) async {
        let candidate = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, connection != .connecting else { return }
        connection = .connecting
        message = nil
        do {
            let who = try await api.account(token: candidate)
            guard tokens.save(candidate) else {
                connection = .disconnected
                message = Message(text: "Island couldn't save the token in your Keychain, so it didn't connect.", isError: true)
                return
            }
            token = candidate
            tokenLoaded = true
            isReady = true
            account = who
            connection = .connected
            scheduleTimer()
            await loadForCurrentSection()
        } catch {
            connection = .disconnected
            message = connectMessage(for: error)
        }
    }

    /// Forgets the token and everything loaded with it.
    func disconnect() {
        stop()
        tokens.delete()
        token = nil
        tokenLoaded = true
        isReady = true
        reset()
        connection = .disconnected
    }

    func dismissMessage() { message = nil }

    // MARK: Choosing the repository and branches

    func loadRepos() async {
        guard connection == .connected, let token, !reposLoading, !reposLoaded, now() >= pausedUntil else { return }
        reposLoading = true
        defer { reposLoading = false }
        do {
            repos = try await api.repos(token: token)
            reposLoaded = true
        } catch is CancellationError {
        } catch {
            handle(error, doing: "load your repositories")
        }
    }

    func selectRepo(_ chosen: GitHubRepo) async {
        guard connection == .connected, let token else { return }
        choiceGeneration += 1
        let generation = choiceGeneration
        repo = chosen
        base = chosen.defaultBranch
        head = nil
        branches = []
        comparison = .none
        existingPullRequest = nil
        creation = .idle
        message = nil
        // A different repository starts a different pull request: whatever was typed or filled in belongs to the old one.
        title = ""
        body = ""
        titleEdited = false
        bodyEdited = false
        branchesLoading = true
        do {
            async let loadedBranches = api.branches(token: token, chosen.reference)
            async let template = api.pullRequestTemplate(token: token, chosen.reference)
            let (list, templateText) = try await (loadedBranches, template)
            guard generation == choiceGeneration else { return }
            branches = list
            if !bodyEdited, body.isEmpty, let templateText { body = templateText }
        } catch is CancellationError {
        } catch {
            if generation == choiceGeneration { handle(error, doing: "load that repository's branches") }
        }
        if generation == choiceGeneration { branchesLoading = false }
    }

    /// A repository typed or pasted in as `owner/name` or a link: looked up, and chosen if a pull request can start there.
    func selectRepo(typed text: String) async {
        guard connection == .connected, let token, let reference = GitHubRepoRef.parse(text) else {
            message = Message(text: "Type a repository as owner/name, or paste its link.", isError: true)
            return
        }
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let found = try await api.repo(token: token, reference)
            guard found.canTakePullRequests else {
                message = Message(text: Self.cannotTakePullRequests(found), isError: true)
                return
            }
            if !repos.contains(where: { $0.id == found.id }) { repos.insert(found, at: 0) }
            await selectRepo(found)
        } catch {
            handle(error, doing: "look up \(reference.fullName)", notFound: "GitHub can't find \(reference.fullName), or your token can't see it.")
        }
    }

    /// Why a pull request cannot start from this repository.
    private static func cannotTakePullRequests(_ repo: GitHubRepo) -> String {
        if repo.isArchived { return "\(repo.fullName) is archived, so it can't take pull requests." }
        if repo.canPush == false {
            return "You don't have write access to \(repo.fullName), so a pull request can't start from one of its branches."
        }
        return "\(repo.fullName) isn't taking pull requests."
    }

    /// Back to the beginning: no repository, no branches, nothing typed.
    func resetForm() {
        choiceGeneration += 1
        repo = nil
        base = nil
        head = nil
        branches = []
        branchesLoading = false
        title = ""
        body = ""
        titleEdited = false
        bodyEdited = false
        isDraft = false
        comparison = .none
        existingPullRequest = nil
        creation = .idle
        message = nil
    }

    func selectBase(_ name: String) async {
        guard base != name else { return }
        base = name
        await choiceChanged()
    }

    func selectHead(_ name: String) async {
        guard head != name else { return }
        head = name
        await choiceChanged()
    }

    /// A branch typed in that the list did not show (a repository can have more branches than are listed): checked with
    /// GitHub, and chosen if it exists.
    func useTypedBranch(_ text: String, asHead: Bool) async {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connection == .connected, let token, let repo, !name.isEmpty else { return }
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let found = try await api.branch(token: token, repo.reference, name: name)
            if !branches.contains(where: { $0.name == found.name }) { branches.append(found) }
            if asHead { await selectHead(found.name) } else { await selectBase(found.name) }
        } catch {
            handle(error, doing: "look up that branch", notFound: "There's no branch called “\(name)” in \(repo.fullName).")
        }
    }

    /// The title typed by the person: from now on it is theirs, and picking another branch no longer replaces it.
    func setTitle(_ text: String) {
        title = text
        titleEdited = !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func setBody(_ text: String) {
        body = text
        bodyEdited = !text.isEmpty
    }

    // MARK: Creating

    /// Opens the pull request. On success its link is ready to copy.
    func createPullRequest() async {
        guard canCreate, let token, let repo, let base, let head else { return }
        creation = .creating
        message = nil
        existingPullRequest = nil
        do {
            let created = try await api.createPullRequest(
                token: token, repo.reference, title: trimmedTitle, head: head, base: base, body: body, draft: isDraft)
            creation = .created(created)
            await refreshLists()   // it now shows under My PRs
        } catch GitHubError.validation(let reason) where reason.lowercased().contains("already exists") {
            creation = .idle
            existingPullRequest = try? await api.openPullRequest(token: token, repo.reference, head: head, base: base)
            message = Message(
                text: existingPullRequest == nil
                    ? "A pull request for this branch already exists."
                    : "A pull request from \(head) into \(base) already exists (#\(existingPullRequest?.number ?? 0)). Its link is below.",
                isError: false)
        } catch {
            creation = .idle
            handle(error, doing: "create the pull request")
        }
    }

    /// After a pull request was created: back to an empty form for the same repository.
    func startAnother() {
        creation = .idle
        head = nil
        title = ""
        body = ""
        titleEdited = false
        bodyEdited = false
        isDraft = false
        comparison = .none
        existingPullRequest = nil
        message = nil
        choiceGeneration += 1
    }

    // MARK: Copying

    func copyLink(of pullRequest: GitHubPullRequest) {
        copy(pullRequest.url.absoluteString, id: pullRequest.id)
    }

    func copyMarkdown(of pullRequest: GitHubPullRequest) {
        copy(pullRequest.markdownLink, id: pullRequest.id + "#markdown")
    }

    func copyTitleAndLink(of pullRequest: GitHubPullRequest) {
        copy(pullRequest.titleAndLink, id: pullRequest.id + "#title")
    }

    private func copy(_ text: String, id: String) {
        writeToClipboard(text)
        copiedID = id
        copiedGeneration += 1
        let generation = copiedGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(copiedSeconds * 1_000_000_000))
            if generation == copiedGeneration { copiedID = nil }
        }
    }

    // MARK: The person's pull requests

    func refreshLists() async {
        guard connection == .connected, let token, !listsLoading, now() >= pausedUntil else { return }
        listsLoading = true
        defer { listsLoading = false }
        do {
            let lists = try await api.pullRequestLists(token: token)
            myPullRequests = lists.mine
            reviewRequests = lists.review
            listsLoaded = true
            if message?.isError == true { message = nil }
        } catch is CancellationError {
        } catch {
            handle(error, doing: nil)
        }
    }

    /// Loads the lists only if they have not been loaded yet (the New PR view wants them just to know which branches
    /// already have a pull request).
    private func loadListsIfNeeded() async {
        if !listsLoaded { await refreshLists() }
    }

    // MARK: Searching a repository's pull requests

    /// Every repository the account can reach that can hold pull requests to look at (a read-only one can be searched
    /// too, unlike one a new pull request can start from), matching what was typed.
    func searchableRepos(matching query: String) -> [GitHubRepo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return repos.filter { !$0.isDisabled && (needle.isEmpty || $0.fullName.lowercased().contains(needle)) }
    }

    func selectSearchRepo(_ chosen: GitHubRepo) {
        searchGeneration += 1
        searchRepo = chosen
        searchResults = []
        searchLoaded = false
        isSearching = false
    }

    /// A repository typed or pasted in for searching.
    func selectSearchRepo(typed text: String) async {
        guard connection == .connected, let token, let reference = GitHubRepoRef.parse(text) else {
            message = Message(text: "Type a repository as owner/name, or paste its link.", isError: true)
            return
        }
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let found = try await api.repo(token: token, reference)
            guard !found.isDisabled else {
                message = Message(text: "\(found.fullName) is disabled.", isError: true)
                return
            }
            if !repos.contains(where: { $0.id == found.id }) { repos.insert(found, at: 0) }
            selectSearchRepo(found)
        } catch {
            handle(error, doing: "look up \(reference.fullName)", notFound: "GitHub can't find \(reference.fullName), or your token can't see it.")
        }
    }

    func clearSearchRepo() {
        searchGeneration += 1
        searchRepo = nil
        searchResults = []
        searchLoaded = false
        isSearching = false
    }

    /// Looks for pull requests in the search repository. A number or a link names one pull request; `@name` means the ones
    /// that person opened; nothing at all lists the latest. See `GitHubSearch`.
    func search(_ text: String) async {
        guard connection == .connected, let token, let repo = searchRepo, now() >= pausedUntil else { return }
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        do {
            let found: [GitHubPullRequest]
            switch GitHubSearch.plan(for: text, in: repo.reference, openOnly: searchOpenOnly) {
            case .number(let number):
                found = try await api.pullRequest(token: token, repo.reference, number: number).map { [$0] } ?? []
            case .search(let query):
                found = try await api.searchPullRequests(token: token, query: query)
            }
            guard generation == searchGeneration else { return }   // the person has typed something newer since
            searchResults = found
            searchLoaded = true
            isSearching = false
        } catch is CancellationError {
            if generation == searchGeneration { isSearching = false }
        } catch {
            guard generation == searchGeneration else { return }
            isSearching = false
            handle(error, doing: "search", notFound: "GitHub can't find that repository, or your token can't see it.")
        }
    }

    // MARK: Internals

    private func loadTokenIfNeeded() {
        guard !tokenLoaded else { return }
        tokenLoaded = true
        isReady = true
        if let saved = tokens.load(), !saved.isEmpty {
            token = saved
            connection = .connected
        }
    }

    private func refreshAccount() async {
        guard let token else { return }
        do {
            account = try await api.account(token: token)
        } catch is CancellationError {
        } catch {
            handle(error, doing: nil)
        }
    }

    private func scheduleTimer() {
        guard timer == nil, refreshInterval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.section != .newPullRequest else { return }
                await self.refreshLists()
            }
        }
    }

    private func reset() {
        account = nil
        message = nil
        repos = []
        reposLoaded = false
        reposLoading = false
        repo = nil
        branches = []
        branchesLoading = false
        base = nil
        head = nil
        title = ""
        body = ""
        titleEdited = false
        bodyEdited = false
        isDraft = false
        comparison = .none
        existingPullRequest = nil
        creation = .idle
        isLookingUp = false
        myPullRequests = []
        reviewRequests = []
        listsLoaded = false
        listsLoading = false
        searchRepo = nil
        searchResults = []
        searchLoaded = false
        isSearching = false
        searchGeneration += 1
        copiedID = nil
        pausedUntil = .distantPast
        choiceGeneration += 1
    }

    /// The repository or a branch changed: look at how the two branches compare, and fill in the title.
    private func choiceChanged() async {
        choiceGeneration += 1
        let generation = choiceGeneration
        existingPullRequest = nil
        message = nil
        creation = .idle
        guard let token, let repo, let base, let head else {
            comparison = .none
            return
        }
        guard base != head else {
            comparison = .failed("Pick two different branches.")
            return
        }
        comparison = .loading
        do {
            let result = try await api.compare(token: token, repo.reference, base: base, head: head)
            guard generation == choiceGeneration else { return }
            comparison = .ready(result)
            if result.hasChanges, !titleEdited {
                // One commit: its first line says it best. Several: the branch name, made readable.
                let fromCommit = result.totalCommits == 1 ? result.firstCommitMessage.map(GitHubText.firstLine(of:)) : nil
                title = (fromCommit?.isEmpty == false ? fromCommit : nil) ?? GitHubText.title(fromBranch: head)
            }
        } catch is CancellationError {
        } catch {
            guard generation == choiceGeneration else { return }
            if case GitHubError.notFound = error {
                comparison = .failed("GitHub couldn't compare these branches.")
            } else if case GitHubError.unauthorized = error {
                comparison = .none
                handle(error, doing: nil)
            } else {
                comparison = .none
                handle(error, doing: "compare the branches")
            }
        }
    }

    private func handle(_ error: Error, doing action: String?, notFound: String? = nil) {
        switch error as? GitHubError {
        case .unauthorized:
            stop()
            tokens.delete()
            token = nil
            reset()
            connection = .disconnected
            message = Message(
                text: "GitHub no longer accepts this token (it may have expired or been revoked). Paste a new one to reconnect.",
                isError: true)
        case .sso(let url):
            message = Message(
                text: "Your organisation requires this token to be authorised for single sign-on before it can use its repositories.",
                isError: true,
                action: Message.Action(title: "Authorise in GitHub", url: url ?? URL(string: "https://github.com/settings/tokens")!))
        case .rateLimited(let until):
            pausedUntil = until ?? now().addingTimeInterval(60)
            let when = until.map { " It resets at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
            message = Message(text: "GitHub's request limit was reached.\(when)", isError: true)
        case .forbidden(let detail):
            let hint = (detail?.contains("not accessible") == true) ? " Give the token the “repo” permission, or access to this repository." : ""
            message = Message(text: "GitHub says this token isn't allowed to do that.\(hint)", isError: true)
        case .notFound:
            message = Message(text: notFound ?? "GitHub can't find that, or your token can't see it.", isError: true)
        case .validation(let reason):
            message = Message(text: reason, isError: true)
        case .network:
            message = Message(
                text: action.map { "Couldn't reach GitHub, so Island couldn't \($0)." } ?? "Couldn't reach GitHub.", isError: true)
        default:
            message = Message(text: action.map { "GitHub wouldn't let Island \($0). Try again." } ?? "GitHub had a problem. Try again in a moment.", isError: true)
        }
    }

    private func connectMessage(for error: Error) -> Message {
        switch error as? GitHubError {
        case .unauthorized:
            return Message(text: "GitHub didn't accept that token. Make a new one (the button above fills in what's needed) and paste it here.", isError: true)
        case .network:
            return Message(text: "Couldn't reach GitHub. Check your internet connection and try again.", isError: true)
        case .rateLimited:
            return Message(text: "GitHub is asking for a short break. Try again in a minute.", isError: true)
        case .sso(let url):
            return Message(
                text: "Your organisation requires this token to be authorised for single sign-on.", isError: true,
                action: Message.Action(title: "Authorise in GitHub", url: url ?? URL(string: "https://github.com/settings/tokens")!))
        default:
            return Message(text: "GitHub had a problem. Try again in a moment.", isError: true)
        }
    }
}
