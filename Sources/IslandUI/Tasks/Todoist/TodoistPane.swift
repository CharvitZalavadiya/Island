import AppKit
import SwiftUI
import IslandCore

/// What the Tasks tab shows while its source is Todoist: the connect card until a token has been accepted, then the
/// person's own Todoist tasks.
struct TodoistPane: View {
    @Bindable var todoist: TodoistController

    var body: some View {
        if !todoist.isReady {
            // Island has not yet looked for a saved token: show neither screen for the moment it takes.
            Color.clear.frame(maxHeight: .infinity)
        } else if todoist.connection == .connected {
            TodoistTasksView(todoist: todoist)
        } else {
            TodoistConnectCard(todoist: todoist)
        }
    }
}

// MARK: Connecting

/// Where a person connects their own Todoist account: paste the token from Todoist's settings.
struct TodoistConnectCard: View {
    @Bindable var todoist: TodoistController
    @State private var token = ""
    @FocusState private var focused: Bool

    var body: some View {
        let connecting = todoist.connection == .connecting
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(IslandTheme.todoist)
                Text("Connect your Todoist").font(.system(size: 15, weight: .bold))
            }
            Text("See your Todoist tasks here, add new ones and tick them off. To connect, copy your personal API token from Todoist (Settings, Integrations, Developer) and paste it below.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            PillButton(title: "Open Todoist's token page", tint: IslandTheme.todoist) {
                NSWorkspace.shared.open(TodoistRequests.tokenSettingsURL)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").font(.system(size: 11)).foregroundStyle(IslandTheme.todoist)
                    SecureField("Paste your API token", text: $token)
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
                    .background(IslandTheme.todoist.opacity(canConnect ? 1 : 0.4), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canConnect)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 9)).padding(.top, 2)
                Text("The token stays on this Mac, in a file only your account can read, and is only ever sent to Todoist. You can disconnect any time.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.5))

            if let message = todoist.message { TodoistMessageBar(message: message, todoist: todoist, retry: false) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Typing needs Island to be the active app; this only happens when the box gets focus.
        .onChange(of: focused) { _, isFocused in
            if isFocused { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    private var canConnect: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && todoist.connection != .connecting
    }

    private func connect() {
        guard canConnect else { return }
        let pasted = token
        Task {
            await todoist.connect(token: pasted)
            // Once it is saved Island has no use for a copy here.
            if todoist.connection == .connected { token = "" }
        }
    }
}

// MARK: Tasks

struct TodoistTasksView: View {
    @Bindable var todoist: TodoistController

    var body: some View {
        VStack(spacing: 10) {
            if todoist.mode == .active {
                TaskComposer(placeholder: "Add a task, e.g. Call mom tomorrow 6pm") { title, due in
                    await todoist.add(title: title, due: due)
                }
            }
            if let message = todoist.message { TodoistMessageBar(message: message, todoist: todoist, retry: true) }

            let tasks = todoist.visible
            if tasks.isEmpty {
                Spacer()
                if !todoist.hasLoaded {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading your Todoist tasks…").font(.callout).foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(tasks) { task in
                            TodoistRow(
                                task: task, projectName: todoist.projectName(for: task), busy: todoist.busy.contains(task.id),
                                onToggle: { Task { await todoist.toggle(task) } })
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

extension TodoistTasksView {
    fileprivate var emptyText: String {
        if todoist.mode == .active { return "Nothing to do in Todoist. Add a task above." }
        if todoist.completedUnavailable { return "Todoist doesn't share completed tasks for this account.\nTasks you tick off here will show up in this list." }
        return "Nothing completed in the last \(TodoistController.completedDays) days."
    }
}

/// One Todoist task: a checkbox ringed in the task's priority colour, the title (struck through once done) with its
/// project under it, and when it is due.
struct TodoistRow: View {
    let task: TodoistTask
    let projectName: String?
    let busy: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isCompleted ? IslandTheme.tasks : priorityColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(busy ? 0.5 : 1)
            .help(task.isCompleted ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 1) {
                Text(task.content)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(task.isCompleted, color: .white.opacity(0.5))
                    .foregroundStyle(task.isCompleted ? Color.white.opacity(0.4) : Color.white)
                    .lineLimit(2)
                if let projectName {
                    Text(projectName)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            dueLabel

            // Opens the task in Todoist; shown only while the pointer is on the row, so the row keeps its shape.
            Button {
                if let url = task.webURL { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IslandTheme.todoist)
                    .frame(width: 24, height: 24)
                    .background(IslandTheme.todoist.opacity(0.18), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help("Open in Todoist")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
    }

    /// Todoist's colours for its priorities: P1 red, P2 orange, P3 blue, otherwise plain.
    private var priorityColor: Color {
        switch task.priority {
        case 4: IslandTheme.danger
        case 3: IslandTheme.focus
        case 2: IslandTheme.link
        default: Color.white.opacity(0.55)
        }
    }

    @ViewBuilder
    private var dueLabel: some View {
        if task.isCompleted {
            if let completedAt = task.completedAt {
                Text(TaskDue.dayLabel(for: completedAt, now: Date()).text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
                    .fixedSize()
            }
        } else if let due = task.due {
            let label = due.hasTime ? TaskDue.label(for: due.date, now: Date()) : TaskDue.dayLabel(for: due.date, now: Date())
            HStack(spacing: 4) {
                Image(systemName: due.isRecurring ? "arrow.triangle.2.circlepath" : "clock")
                Text(label.text)
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(label.isOverdue ? IslandTheme.danger : Color.white.opacity(0.6))
        }
    }
}

// MARK: Messages and the menu

/// A line telling the person something went wrong (or right), with Retry when trying again could help.
struct TodoistMessageBar: View {
    let message: TodoistController.Message
    let todoist: TodoistController
    let retry: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(message.isError ? IslandTheme.keepAwake : IslandTheme.accent)
            Text(message.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if retry { PillButton(title: "Retry") { Task { await todoist.refresh() } } }
            Button { todoist.dismissMessage() } label: {
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

/// The "…" menu beside the Local | Todoist switch: who is connected, refresh, open Todoist, disconnect.
struct TodoistMenu: View {
    let todoist: TodoistController

    var body: some View {
        Menu {
            Button(todoist.accountName.map { "Connected as \($0)" } ?? "Connected to Todoist") {}
                .disabled(true)
            Divider()
            Button("Refresh now") { Task { await todoist.refresh() } }
            Button("Open Todoist") {
                if let url = URL(string: "https://app.todoist.com/app") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Disconnect Todoist", role: .destructive) { todoist.disconnect() }
        } label: {
            Group {
                if todoist.isLoading {
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
        .help("Todoist options")
    }
}
