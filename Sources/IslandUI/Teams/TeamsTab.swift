import AppKit
import SwiftUI
import IslandCore

/// The Teams tab (a trial): sign in, your chats, and a chat's messages with GitHub pull requests that open for review.
struct TeamsTab: View {
    @Bindable var controller: TeamsController

    var body: some View {
        VStack(spacing: 10) {
            if controller.connection == .connected, let message = controller.message {
                TeamsMessageBar(message: message, controller: controller)
            }
            content
        }
        .foregroundStyle(.white)
        // Teams is only asked about while the tab is on screen.
        .task { await controller.start() }
        .onDisappear { controller.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if !controller.isReady {
            Color.clear.frame(maxHeight: .infinity)   // Island has not yet looked for a saved sign-in
        } else if controller.connection != .connected {
            TeamsConnectCard(controller: controller)
        } else if controller.openChat != nil {
            TeamsChatView(controller: controller)
        } else {
            TeamsChatList(controller: controller)
        }
    }
}

// MARK: Connecting

/// Where a person connects Teams: the Application ID of an app they registered in their own Microsoft account, then sign in.
struct TeamsConnectCard: View {
    @Bindable var controller: TeamsController

    var body: some View {
        let waiting = controller.connection == .connecting
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: TeamsStyle.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(IslandTheme.teams)
                Text("Connect Microsoft Teams").font(.system(size: 15, weight: .bold))
            }
            Text("See your chats here and open the GitHub pull requests people send you. Island only reads your chats; it never sends anything.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                step("1", "Register an app in Microsoft Entra (New registration, “this organizational directory only”).")
                step("2", "Authentication: add platform “Mobile and desktop applications” with the address http://localhost.")
                step("3", "API permissions: Microsoft Graph, Delegated: Chat.Read and User.Read. Then paste the Application (client) ID here.")
            }

            HStack(spacing: 8) {
                field("key.fill", $controller.clientID, "Application (client) ID", onSubmit: connect)
                field("building.2", $controller.tenant, "Tenant (optional)", onSubmit: connect).frame(width: 150)
            }

            HStack(spacing: 8) {
                PillButton(title: "Open Entra", tint: IslandTheme.teams) { NSWorkspace.shared.open(TeamsRequests.registrationURL) }
                Spacer(minLength: 0)
                if waiting {
                    Text("Finish in your browser. If it shows an error, cancel and check the ID.").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(2).multilineTextAlignment(.trailing)
                    PillButton(title: "Cancel", height: 30) { controller.cancelSignIn() }
                } else {
                    Button(action: connect) {
                        Text("Sign in")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 16)
                            .frame(height: 30)
                            .background(IslandTheme.teams.opacity(canConnect ? 1 : 0.4), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConnect)
                }
            }

            if let message = controller.message { TeamsMessageBar(message: message, controller: controller) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canConnect: Bool {
        !controller.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.connection != .connecting
    }

    private func connect() {
        guard canConnect else { return }
        Task { await controller.signIn() }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number).font(.system(size: 10, weight: .bold)).foregroundStyle(IslandTheme.teams).frame(width: 9)
            Text(text).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(_ symbol: String, _ text: Binding<String>, _ placeholder: String, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(IslandTheme.teams)
            SearchField(text: text, placeholder: placeholder, focusesOnAppear: false, onSubmit: onSubmit)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color.white.opacity(0.1), in: Capsule())
    }
}

// MARK: The chat list

struct TeamsChatList: View {
    @Bindable var controller: TeamsController

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    SearchField(text: $controller.filter, placeholder: "Search people and groups", focusesOnAppear: false)
                    if !controller.filter.isEmpty {
                        Button { controller.filter = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Color.white.opacity(0.1), in: Capsule())
                TeamsMenu(controller: controller)
            }

            let chats = controller.visibleChats
            if chats.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    if controller.chatsLoading || !controller.chatsLoaded {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading your chats…").font(.callout).foregroundStyle(.white.opacity(0.5))
                        }
                    } else {
                        Text(controller.filter.isEmpty ? "No chats yet." : "Nobody matches.").font(.callout).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(chats) { chat in TeamsChatRow(controller: controller, chat: chat) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct TeamsChatRow: View {
    let controller: TeamsController
    let chat: TeamsChat
    @State private var hovering = false

    var body: some View {
        let title = controller.title(of: chat)
        Button { Task { await controller.open(chat) } } label: {
            HStack(spacing: 10) {
                TeamsAvatar(name: title, isGroup: chat.kind != .oneOnOne)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if let preview = chat.preview {
                        Text(verbatim: previewLine(preview)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if chat.preview?.mentionsPullRequest == true {
                    Image(systemName: TeamsStyle.pullRequestSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(IslandTheme.github)
                        .help("A pull request was shared here")
                }
                if let date = chat.lastActivity {
                    Text(verbatim: TeamsTime.label(date, now: Date())).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)).lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(hovering ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func previewLine(_ preview: TeamsPreview) -> String {
        guard let sender = preview.sender, !sender.isEmpty else { return preview.text }
        return "\(sender.split(separator: " ").first.map(String.init) ?? sender): \(preview.text)"
    }
}

// MARK: One chat

struct TeamsChatView: View {
    @Bindable var controller: TeamsController

    var body: some View {
        if let chat = controller.openChat {
            VStack(spacing: 8) {
                header(chat)
                if controller.messages.isEmpty {
                    VStack {
                        Spacer()
                        if controller.messagesLoading || !controller.messagesLoaded {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Loading messages…").font(.callout).foregroundStyle(.white.opacity(0.5))
                            }
                        } else {
                            Text("No messages to show.").font(.callout).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(controller.messages) { TeamsMessageRow(controller: controller, message: $0) }
                                Color.clear.frame(height: 1).id("end")
                            }
                        }
                        .scrollIndicators(.hidden)
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: controller.messages.last?.id) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func header(_ chat: TeamsChat) -> some View {
        HStack(spacing: 10) {
            Button { controller.closeChat() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to your chats")

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: controller.title(of: chat)).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Text(verbatim: subtitle(chat)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if controller.messagesLoading { ProgressView().controlSize(.mini) }
            Button { controller.openInTeams(chat) } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open this chat in Teams")
        }
    }

    private func subtitle(_ chat: TeamsChat) -> String {
        switch chat.kind {
        case .oneOnOne: "Chat"
        case .meeting: "Meeting chat"
        case .group, .other: "Group · \(chat.members.count) people"
        }
    }
}

struct TeamsMessageRow: View {
    let controller: TeamsController
    let message: TeamsMessage

    var body: some View {
        let mine = controller.isMine(message)
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: mine ? "You" : (message.senderName ?? "Someone")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    if let date = message.date {
                        Text(verbatim: TeamsTime.label(date, now: Date(), withTime: true)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                    }
                }
                if !message.runs.isEmpty {
                    Text(Self.attributed(message.runs))
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if message.runs.isEmpty, !message.attachmentNames.isEmpty {
                    Text(verbatim: message.attachmentNames.joined(separator: ", ")).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(message.pullRequests.indices, id: \.self) { index in pullRequestChip(message.pullRequests[index]) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((mine ? IslandTheme.teams.opacity(0.22) : Color.white.opacity(0.07)), in: RoundedRectangle(cornerRadius: 12))
            // A click on a link in the words: a pull request opens for review here, anything else (and any Command-click)
            // in the browser.
            .environment(\.openURL, OpenURLAction { url in
                controller.activate(url, commandHeld: NSEvent.modifierFlags.contains(.command))
                return .handled
            })
            if !mine { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private func pullRequestChip(_ link: TeamsPullRequestLink) -> some View {
        Button {
            controller.activate(link.url, commandHeld: NSEvent.modifierFlags.contains(.command))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: TeamsStyle.pullRequestSymbol).font(.system(size: 10, weight: .bold))
                Text(verbatim: link.label).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text("Review").font(.system(size: 10.5, weight: .medium)).foregroundStyle(IslandTheme.github.opacity(0.8))
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(IslandTheme.github)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(IslandTheme.github.opacity(0.16), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Click to review it in the GitHub tab · ⌘-click to open it in your browser")
    }

    static func attributed(_ runs: [TeamsRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if let url = run.url {
                piece.link = url
                piece.foregroundColor = IslandTheme.link
                piece.underlineStyle = .single
            }
            result += piece
        }
        return result
    }
}

// MARK: Pieces

enum TeamsStyle {
    static let symbol = "bubble.left.and.bubble.right.fill"
    static let pullRequestSymbol = "arrow.triangle.pull"
}

/// A round badge with a person's initials (or two people for a group), in a colour that stays the same for the same name.
struct TeamsAvatar: View {
    let name: String
    let isGroup: Bool

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.28))
            if isGroup {
                Image(systemName: "person.2.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            } else {
                Text(verbatim: initials).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return letters.isEmpty ? "?" : letters
    }

    private var color: Color {
        let palette: [Color] = [IslandTheme.teams, IslandTheme.link, IslandTheme.tasks, IslandTheme.focus, IslandTheme.swatch, IslandTheme.scan, IslandTheme.clipboard]
        // Not `hashValue`: that changes every launch, and a person's colour should not.
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}

struct TeamsMessageBar: View {
    let message: TeamsController.Message
    let controller: TeamsController

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
                PillButton(title: action.title, prominent: true, tint: IslandTheme.teams) { NSWorkspace.shared.open(action.url) }
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

/// The "…" menu: who is signed in, refresh, open Teams, sign out.
struct TeamsMenu: View {
    let controller: TeamsController

    var body: some View {
        Menu {
            Button(controller.account.map { "Signed in as \($0.displayName)" } ?? "Signed in to Teams") {}
                .disabled(true)
            Divider()
            Button("Refresh now") { Task { await controller.refreshChats() } }
            Button("Open Teams on the web") {
                if let url = URL(string: "https://teams.microsoft.com") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Sign out of Teams", role: .destructive) { controller.disconnect() }
        } label: {
            Group {
                if controller.chatsLoading { ProgressView().controlSize(.mini) } else {
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
        .help("Teams options")
    }
}
