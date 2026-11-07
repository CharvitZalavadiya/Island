import AppKit
import SwiftUI
import IslandCore

/// The GitHub tab: connect an account, open a pull request in any repository the account can push to (any base branch,
/// any branch to merge), copy its link to send to someone, and look at your own open pull requests and the ones waiting
/// for your review.
struct GitHubTab: View {
    @Bindable var controller: GitHubController

    var body: some View {
        VStack(spacing: 10) {
            if controller.isReady, controller.connection == .connected { header }
            if let message = controller.message { GitHubMessageBar(message: message, controller: controller) }
            content
        }
        .foregroundStyle(.white)
        // GitHub is only asked about while the tab is on screen.
        .task { await controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.section) { _, _ in
            Task { await controller.loadForCurrentSection() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !controller.isReady {
            // Island has not yet looked for a saved token: show neither screen for the moment it takes.
            Color.clear.frame(maxHeight: .infinity)
        } else if controller.connection != .connected {
            GitHubConnectCard(controller: controller)
        } else {
            switch controller.section {
            case .newPullRequest:
                NewPullRequestView(controller: controller)
            case .mine:
                PullRequestListView(
                    controller: controller, pullRequests: controller.myPullRequests,
                    emptyText: "You have no open pull requests.")
            case .reviewRequests:
                PullRequestListView(
                    controller: controller, pullRequests: controller.reviewRequests,
                    emptyText: "Nobody is waiting on your review.", showsAuthor: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PillSwitch(
                selection: $controller.section,
                options: [
                    (.newPullRequest, "New PR"),
                    (.mine, controller.myPullRequests.isEmpty ? "My PRs" : "My PRs \(controller.myPullRequests.count)"),
                    (.reviewRequests, controller.reviewRequests.isEmpty ? "Reviews" : "Reviews \(controller.reviewRequests.count)"),
                ],
                tint: IslandTheme.github)
            Spacer(minLength: 4)
            GitHubMenu(controller: controller)
        }
    }
}

// MARK: Connecting

/// Where a person connects their own GitHub account: paste a personal access token.
struct GitHubConnectCard: View {
    @Bindable var controller: GitHubController
    @State private var token = ""
    @FocusState private var focused: Bool

    var body: some View {
        let connecting = controller.connection == .connecting
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                GitHubMarkView(size: 20).foregroundStyle(.white)
                Text("Connect GitHub").font(.system(size: 15, weight: .bold))
            }
            Text("Open pull requests in any repository you can push to, see your open and review-requested ones, and copy their links. Island needs a personal access token with the “repo” permission.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            PillButton(title: "Make a token on GitHub", tint: IslandTheme.github) {
                NSWorkspace.shared.open(GitHubRequests.newTokenURL)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").font(.system(size: 11)).foregroundStyle(IslandTheme.github)
                    SecureField("Paste your token", text: $token)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(connect)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.1), in: Capsule())

                PillButton(title: "Paste", height: 30) {
                    if let text = NSPasteboard.general.string(forType: .string) { token = text }
                }
                Button(action: connect) {
                    HStack(spacing: 6) {
                        if connecting { ProgressView().controlSize(.mini) }
                        Text(connecting ? "Connecting…" : "Connect")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(IslandTheme.github.opacity(canConnect ? 1 : 0.4), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canConnect)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 9)).padding(.top, 2)
                Text("The token stays in your Mac's Keychain and is only ever sent to GitHub. If your repositories belong to an organization that uses single sign-on, authorize the token for it on GitHub's token page (Configure SSO).")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Typing needs Island to be the active app; this only happens when the box gets focus.
        .onChange(of: focused) { _, isFocused in
            if isFocused { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    private var canConnect: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.connection != .connecting
    }

    private func connect() {
        guard canConnect else { return }
        let pasted = token
        Task {
            await controller.connect(token: pasted)
            // Once it is kept in the Keychain Island has no use for a copy here.
            if controller.connection == .connected { token = "" }
        }
    }
}

// MARK: Messages and the menu

/// A line telling the person something went wrong (or just something to know), with a button when there is one to press.
struct GitHubMessageBar: View {
    let message: GitHubController.Message
    let controller: GitHubController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(message.isError ? IslandTheme.keepAwake : IslandTheme.accent)
            Text(message.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action = message.action {
                PillButton(title: action.title, prominent: true, tint: IslandTheme.github) { NSWorkspace.shared.open(action.url) }
            }
            Button { controller.dismissMessage() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((message.isError ? IslandTheme.keepAwake : IslandTheme.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The "…" menu: who is connected, refresh, open GitHub, disconnect.
struct GitHubMenu: View {
    let controller: GitHubController

    var body: some View {
        Menu {
            Button(controller.account.map { "Connected as \($0.login)" } ?? "Connected to GitHub") {}
                .disabled(true)
            Divider()
            Button("Refresh now") { Task { await controller.refreshLists() } }
            Button("Open GitHub pull requests") {
                if let url = URL(string: "https://github.com/pulls") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Disconnect GitHub", role: .destructive) { controller.disconnect() }
        } label: {
            Group {
                if controller.listsLoading || controller.reposLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.1), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("GitHub options")
    }
}
