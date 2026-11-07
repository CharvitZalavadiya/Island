import AppKit
import SwiftUI
import IslandCore

/// Search one repository's pull requests: pick the repository, then type. It finds a pull request by words from its title,
/// by number (`482`, `#482`), by who opened it (`@ravi`) or by branch (`branch:feature/login`). Paste a pull request link
/// into the repository picker (or, once a repository is chosen, into the search box) and that repository is chosen and the
/// pull request opens for review straight away, so a colleague's "can you review my PR?" is one paste.
/// With no repository chosen the picker is the only bar: there is nothing to search yet.
struct SearchPullRequestsView: View {
    @Bindable var controller: GitHubController
    @State private var query = ""
    @State private var choosingRepository = false
    /// Bumped to hand the keyboard to the search box (after a repository was chosen).
    @State private var focusRequest = 0
    /// The link that was last handed to `openPullRequest`, so changing the search key (choosing its repository) does not
    /// open it a second time.
    @State private var handledLink: String?

    /// What a search depends on: when any of it changes, the previous search is dropped and a new one starts.
    private struct SearchKey: Equatable {
        var query: String
        var openOnly: Bool
        var repositoryID: Int?
    }

    var body: some View {
        if choosingRepository {
            PickerList(controller: controller, kind: .searchRepository, onDone: {
                choosingRepository = false
                focusRequest += 1   // the next thing to do is type: the search box takes the keyboard
            })
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { choosingRepository = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox").font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandTheme.github)
                        Text(controller.searchRepo?.fullName ?? "Choose a repository to search")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(controller.searchRepo == nil ? Color.white.opacity(0.5) : Color.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if controller.reposLoading { ProgressView().controlSize(.mini) } else {
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
                if controller.searchRepo != nil {
                    Button { controller.clearSearchRepo(); query = "" } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.1), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose another repository")
                }
            }

            if controller.searchRepo == nil {
                Text(controller.reposLoading ? "Loading your repositories…" : "Choose a repository above to search its pull requests. Paste a pull request link there to review it straight away.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                searchRow
                results
            }
        }
        // A search starts a moment after the last key, and again whenever the repository or Open/All changes. The
        // empty search (nothing typed yet) lists the latest, so the tab is useful the moment a repository is chosen.
        .task(id: SearchKey(query: query, openOnly: controller.searchOpenOnly, repositoryID: controller.searchRepo?.id)) {
            // A pasted pull request link is not searched for: its repository is chosen and it opens for review at once.
            if GitHubPullRequestReference.parse(query) != nil {
                guard handledLink != query else { return }
                handledLink = query
                let link = query
                // Not part of this task: choosing the repository changes the search key, which would cancel it.
                Task { @MainActor in _ = await controller.openPullRequest(link: link) }
                return
            }
            handledLink = nil
            guard controller.searchRepo != nil else { return }
            if !query.isEmpty {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            await controller.search(query)
        }
    }

    /// The box under the repository: words, `#482`, `@ravi`, `branch:name`, or a pull request link; Open | All beside it.
    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                SearchField(
                    text: $query,
                    placeholder: "Title, #number, @author, or branch:name",
                    focusesOnAppear: false, focusRequest: focusRequest)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color.white.opacity(0.1), in: Capsule())
            .help("Try: login form · 482 · #482 · @ravi · branch:feature/login · or paste a pull request link")
            PillSwitch(selection: $controller.searchOpenOnly, options: [(true, "Open"), (false, "All")], tint: IslandTheme.github)
        }
    }

    @ViewBuilder
    private var results: some View {
        if controller.searchResults.isEmpty {
            VStack(spacing: 4) {
                Spacer()
                if controller.isSearching || !controller.searchLoaded {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching…").font(.callout).foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Text(query.isEmpty ? "No pull requests here." : "No pull requests match.")
                        .font(.callout).foregroundStyle(.white.opacity(0.5))
                    if controller.searchOpenOnly {
                        Text("Only open ones are searched. Switch to All to include closed and merged.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(controller.searchResults) { PullRequestRow(controller: controller, pullRequest: $0, showsAuthor: true) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
