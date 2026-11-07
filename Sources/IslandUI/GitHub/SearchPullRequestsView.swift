import AppKit
import SwiftUI
import IslandCore

/// Search one repository's pull requests: pick the repository, then type. It finds a pull request by words from its title,
/// by number (`482`, `#482`, or a pasted link), by who opened it (`@ravi`) or by branch (`branch:feature/login`). Each result
/// has a button to copy its link and one to open it, so a colleague's "can you review my PR?" is a few keystrokes.
struct SearchPullRequestsView: View {
    @Bindable var controller: GitHubController
    @State private var query = ""
    @State private var choosingRepository = false
    @FocusState private var focused: Bool

    /// What a search depends on: when any of it changes, the previous search is dropped and a new one starts.
    private struct SearchKey: Equatable {
        var query: String
        var openOnly: Bool
        var repositoryID: Int?
    }

    var body: some View {
        if choosingRepository {
            PickerList(controller: controller, kind: .searchRepository, onDone: { choosingRepository = false })
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
                Text(controller.reposLoading ? "Loading your repositories…" : "Pick a repository, then search its pull requests: by title, number, or @author.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        TextField("Title, #number, @author or branch:name", text: $query)
                            .textFieldStyle(.plain)
                            .focused($focused)
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
                    .help("Try: login form · 482 · #482 · a pull request link · @ravi · branch:feature/login")
                    PillSwitch(selection: $controller.searchOpenOnly, options: [(true, "Open"), (false, "All")], tint: IslandTheme.github)
                }
                results
            }
        }
        // Typing needs Island to be the active app; this only happens when the box gets focus.
        .onChange(of: focused) { _, isFocused in
            if isFocused { NSApp.activate(ignoringOtherApps: true) }
        }
        // A search starts a moment after the last key, and again whenever the repository or Open/All changes. The
        // empty search (nothing typed yet) lists the latest, so the tab is useful the moment a repository is chosen.
        .task(id: SearchKey(query: query, openOnly: controller.searchOpenOnly, repositoryID: controller.searchRepo?.id)) {
            guard controller.searchRepo != nil else { return }
            if !query.isEmpty {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            await controller.search(query)
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
