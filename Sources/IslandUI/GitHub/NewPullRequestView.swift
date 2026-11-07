import AppKit
import SwiftUI
import IslandCore

/// The form for a new pull request. Choosing a repository or a branch swaps the form for a searchable list, so there are
/// no pop-ups to fight with in the island; after the pull request is created the form gives way to its link.
struct NewPullRequestView: View {
    @Bindable var controller: GitHubController

    @State private var picking: PullRequestPicking?
    @State private var descriptionOpen = false
    @State private var showsCommits = false

    var body: some View {
        if case .created(let created) = controller.creation {
            CreatedPullRequestCard(controller: controller, pullRequest: created)
        } else if let picking {
            PickerList(controller: controller, kind: picking, onDone: { self.picking = nil })
        } else {
            form
        }
    }

    // MARK: The form

    private var form: some View {
        VStack(spacing: 8) {
            // The fields scroll when there is not room for them all (an open description is tall)...
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    pickerButton(
                        symbol: "shippingbox", prefix: nil, text: controller.repo?.fullName ?? "Choose a repository",
                        isPlaceholder: controller.repo == nil, loading: controller.reposLoading
                    ) { picking = .repository }

                    if controller.repo == nil {
                        suggestionList(controller.suggestions, heading: "Recently pushed: open a pull request from one")
                        Text(controller.reposLoading ? "Loading your repositories…" : "Or pick the repository to open the pull request in. You can also type owner/name or paste a link.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 4)
                    } else {
                        HStack(spacing: 8) {
                            pickerButton(symbol: nil, prefix: "into", text: controller.base ?? "…", isPlaceholder: controller.base == nil, loading: false) { picking = .base }
                            pickerButton(symbol: nil, prefix: "from", text: controller.head ?? "Choose a branch", isPlaceholder: controller.head == nil, loading: controller.branchesLoading) { picking = .head }
                        }
                        if controller.head == nil, let repo = controller.repo {
                            suggestionList(controller.suggestions(for: repo), heading: "Your recent branches here")
                        }
                        comparisonLine
                        if showsCommits, case .ready(let comparison) = controller.comparison { commitList(comparison) }
                        titleField
                        descriptionArea
                        if let existing = controller.existingPullRequest { ExistingPullRequestRow(controller: controller, pullRequest: existing) }
                    }
                }
            }
            .scrollIndicators(.hidden)

            // ...but Draft and Create stay where they can always be reached.
            if controller.repo != nil { bottomRow }
        }
        // A template may have filled the description in while the form was out of sight (behind the repository list).
        .onAppear { if !controller.body.isEmpty { descriptionOpen = true } }
        .onChange(of: controller.head) { _, _ in showsCommits = false }
        .onChange(of: controller.body) { _, text in
            // A template just filled the description in: show it.
            if !text.isEmpty { descriptionOpen = true }
        }
    }

    private func pickerButton(symbol: String?, prefix: String?, text: String, isPlaceholder: Bool, loading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandTheme.github) }
                if let prefix { Text(prefix).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.45)) }
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isPlaceholder ? Color.white.opacity(0.5) : Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if loading { ProgressView().controlSize(.mini) } else {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var comparisonLine: some View {
        if case .ready(let comparison) = controller.comparison, comparison.hasChanges {
            // Tap to see what the commits are.
            Button { showsCommits.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(IslandTheme.tasks)
                    Text(Self.summary(of: comparison)).foregroundStyle(.white.opacity(0.75))
                    if comparison.behindBy > 0 {
                        Text("· \(comparison.behindBy) behind \(controller.base ?? "the base")").foregroundStyle(IslandTheme.keepAwake)
                    }
                    if !comparison.commitTitles.isEmpty {
                        Image(systemName: showsCommits ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(comparison.behindBy > 0 ? "The base branch has moved on; consider updating the branch first" : "Show the commits")
        } else {
            HStack(spacing: 6) {
                switch controller.comparison {
                case .none:
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.white.opacity(0.4))
                    Text("Choose the branch to merge from.").foregroundStyle(.white.opacity(0.5))
                case .loading:
                    ProgressView().controlSize(.mini)
                    Text("Comparing the branches…").foregroundStyle(.white.opacity(0.5))
                case .ready:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IslandTheme.keepAwake)
                    Text("No new commits on \(controller.head ?? "this branch"): nothing to open a pull request for.")
                        .foregroundStyle(IslandTheme.keepAwake)
                case .failed(let reason):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IslandTheme.danger)
                    Text(reason).foregroundStyle(IslandTheme.danger)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    /// The first few commit titles, so the person can see what is going into the pull request.
    private func commitList(_ comparison: GitHubComparison) -> some View {
        let shown = Array(comparison.commitTitles.prefix(5))
        let hidden = comparison.totalCommits - shown.count
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, title in
                HStack(spacing: 6) {
                    Circle().fill(IslandTheme.github.opacity(0.7)).frame(width: 4, height: 4)
                    Text(title).lineLimit(1).truncationMode(.tail)
                }
            }
            if hidden > 0 { Text("and \(hidden) more").foregroundStyle(.white.opacity(0.4)) }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.65))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Branches the person pushed to recently, one tap from a pull request.
    @ViewBuilder
    private func suggestionList(_ pushes: [GitHubPush], heading: String) -> some View {
        if !pushes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).padding(.horizontal, 4)
                ForEach(pushes) { push in
                    Button { Task { await controller.selectSuggestion(push) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandTheme.github).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(push.branch).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                Text("\(push.repoFullName) · \(PullRequestRow.relative(push.pushedAt))")
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text("Open PR").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(IslandTheme.github)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(IslandTheme.github.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// "3 commits · 5 files changed".
    static func summary(of comparison: GitHubComparison) -> String {
        let commits = "\(comparison.totalCommits) commit\(comparison.totalCommits == 1 ? "" : "s")"
        guard comparison.filesChanged > 0 else { return commits }
        return "\(commits) · \(comparison.filesChanged) file\(comparison.filesChanged == 1 ? "" : "s") changed"
    }

    private var titleField: some View {
        TextField("Title", text: Binding(get: { controller.title }, set: { controller.setTitle($0) }))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color.white.opacity(0.1), in: Capsule())
            .onSubmit { Task { await controller.createPullRequest() } }
    }

    @ViewBuilder
    private var descriptionArea: some View {
        if descriptionOpen {
            ToolTextView(text: Binding(get: { controller.body }, set: { controller.setBody($0) }), isEditable: true)
                .frame(height: 60)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Button { descriptionOpen = true } label: {
                Label("Add a description", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 10) {
            Button { controller.isDraft.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: controller.isDraft ? "checkmark.square.fill" : "square")
                        .foregroundStyle(controller.isDraft ? IslandTheme.github : Color.white.opacity(0.55))
                    Text("Draft").font(.system(size: 12, weight: .medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open it as a draft pull request")

            Spacer(minLength: 0)

            let creating = controller.creation == .creating
            Button { Task { await controller.createPullRequest() } } label: {
                HStack(spacing: 6) {
                    if creating { ProgressView().controlSize(.mini) }
                    Text(creating ? "Creating…" : (controller.isDraft ? "Create draft pull request" : "Create pull request"))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(IslandTheme.github.opacity(controller.canCreate ? 1 : 0.4), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canCreate)
        }
    }
}

// MARK: Choosing from a list

/// A searchable list of repositories or branches, shown in place of the form.
private struct PickerList: View {
    @Bindable var controller: GitHubController
    let kind: PullRequestPicking
    let onDone: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    TextField(placeholder, text: $query)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(submitTyped)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Color.white.opacity(0.1), in: Capsule())
                PillButton(title: "Cancel", height: 30, action: onDone)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    switch kind {
                    case .repository: repositoryRows
                    case .base: branchRows(asHead: false)
                    case .head: branchRows(asHead: true)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { focused = true }
        // Typing needs Island to be the active app; this only happens when the box gets focus.
        .onChange(of: focused) { _, isFocused in
            if isFocused { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    private var placeholder: String {
        switch kind {
        case .repository: "Search, or type owner/name or paste a link"
        case .base, .head: "Search branches, or type a name"
        }
    }

    /// Return in the search box takes what was typed as it is: a repository reference, or a branch name.
    private func submitTyped() {
        switch kind {
        case .repository:
            guard GitHubRepoRef.parse(query) != nil else { return }
            Task { await controller.selectRepo(typed: query) }
            onDone()
        case .base, .head:
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            if let match = controller.branches(matching: "", excludingBase: kind == .head).first(where: { $0.name == text }) {
                choose(match.name)
            } else {
                Task { await controller.useTypedBranch(text, asHead: kind == .head) }
                onDone()
            }
        }
    }

    @ViewBuilder
    private var repositoryRows: some View {
        let repos = controller.pickableRepos(matching: query)
        if GitHubRepoRef.parse(query) != nil, !repos.contains(where: { $0.fullName.lowercased() == GitHubRepoRef.parse(query)?.fullName.lowercased() }) {
            row(title: "Open \(GitHubRepoRef.parse(query)?.fullName ?? query)", subtitle: "Look it up on GitHub", symbol: "magnifyingglass", highlighted: true) {
                Task { await controller.selectRepo(typed: query) }
                onDone()
            }
        }
        if controller.reposLoading && repos.isEmpty {
            ProgressView().controlSize(.small).padding(.top, 20)
        } else if repos.isEmpty {
            note("No repository matches. Type owner/name to look one up.")
        }
        ForEach(repos) { repo in
            row(title: repo.fullName, subtitle: repo.summary, symbol: repo.isPrivate ? "lock.fill" : "shippingbox", highlighted: controller.repo?.id == repo.id) {
                Task { await controller.selectRepo(repo) }
                onDone()
            }
        }
    }

    @ViewBuilder
    private func branchRows(asHead: Bool) -> some View {
        let names = controller.branches(matching: query, excludingBase: asHead)
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, !names.contains(where: { $0.name == typed }) {
            row(title: "Use “\(typed)”", subtitle: "Check it exists on GitHub", symbol: "magnifyingglass", highlighted: true) {
                Task { await controller.useTypedBranch(typed, asHead: asHead) }
                onDone()
            }
        }
        if controller.branchesLoading && names.isEmpty {
            ProgressView().controlSize(.small).padding(.top, 20)
        } else if names.isEmpty && typed.isEmpty {
            note("This repository has no other branches.")
        }
        ForEach(names, id: \.name) { branch in
            row(
                title: branch.name, subtitle: badge(for: branch), symbol: "arrow.triangle.branch",
                highlighted: (asHead ? controller.head : controller.base) == branch.name
            ) { choose(branch.name) }
        }
    }

    private func badge(for branch: GitHubBranch) -> String? {
        if branch.name == controller.repo?.defaultBranch { return "default branch" }
        return branch.isProtected ? "protected" : nil
    }

    private func choose(_ name: String) {
        Task {
            if kind == .head { await controller.selectHead(name) } else { await controller.selectBase(name) }
        }
        onDone()
    }

    private func row(title: String, subtitle: String?, symbol: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandTheme.github)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if highlighted && !title.hasPrefix("Open ") && !title.hasPrefix("Use ") {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(IslandTheme.github)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(highlighted ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).padding(.top, 14)
    }
}

/// What the picker is choosing (shared by the form and the list).
enum PullRequestPicking: Equatable {
    case repository
    case base
    case head
}

// MARK: After creating

/// The pull request that was just created: its link, ready to copy and send.
struct CreatedPullRequestCard: View {
    let controller: GitHubController
    let pullRequest: GitHubPullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(IslandTheme.tasks)
                Text("Pull request #\(pullRequest.number) \(pullRequest.isDraft ? "created as a draft" : "created")")
                    .font(.system(size: 15, weight: .bold))
            }
            Text(pullRequest.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Text("\(pullRequest.repoFullName) · \(pullRequest.headBranch ?? "") → \(pullRequest.baseBranch ?? "")")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(pullRequest.url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.1), in: Capsule())
                PullRequestActions.copyButton(controller: controller, pullRequest: pullRequest, prominent: true)
            }

            HStack(spacing: 8) {
                PillButton(title: "Open in GitHub") { NSWorkspace.shared.open(pullRequest.url) }
                PullRequestActions.copyAsMenu(controller: controller, pullRequest: pullRequest)
                Spacer(minLength: 0)
                PillButton(title: "New pull request", prominent: true, tint: IslandTheme.github) { controller.startAnother() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The pull request that already exists for the branches chosen: its link, so the person is not left at a dead end.
struct ExistingPullRequestRow: View {
    let controller: GitHubController
    let pullRequest: GitHubPullRequest

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull").foregroundStyle(IslandTheme.github)
            VStack(alignment: .leading, spacing: 1) {
                Text("#\(pullRequest.number) \(pullRequest.title)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("Already open").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PullRequestActions.copyButton(controller: controller, pullRequest: pullRequest, prominent: false)
            PillButton(title: "Open") { NSWorkspace.shared.open(pullRequest.url) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(IslandTheme.github.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The "Copy link" and "Copy as Markdown" buttons, which say "Copied" for a moment after being used.
enum PullRequestActions {
    @MainActor
    static func copyButton(controller: GitHubController, pullRequest: GitHubPullRequest, prominent: Bool) -> some View {
        let copied = controller.copiedID == pullRequest.id
        return PillButton(title: copied ? "Copied" : "Copy link", prominent: prominent, tint: IslandTheme.github, height: prominent ? 30 : nil) {
            controller.copyLink(of: pullRequest)
        }
    }

    /// "Copy as…": the title with the link (for a chat), or the link as Markdown (for a document).
    @MainActor
    static func copyAsMenu(controller: GitHubController, pullRequest: GitHubPullRequest) -> some View {
        let copied = controller.copiedID == pullRequest.id + "#markdown" || controller.copiedID == pullRequest.id + "#title"
        return Menu {
            Button("Title and link") { controller.copyTitleAndLink(of: pullRequest) }
            Button("Markdown link") { controller.copyMarkdown(of: pullRequest) }
        } label: {
            Text(copied ? "Copied" : "Copy as…")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.14), in: Capsule())
                .foregroundStyle(Color.white)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
