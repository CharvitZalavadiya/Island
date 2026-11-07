import AppKit
import SwiftUI
import IslandCore

/// The review panel for one pull request (usually a colleague's): what it is, where you and the others stand on it, a box
/// for a comment, and Approve, Request changes and Comment. Approving and asking for changes speak for you to the whole
/// team, so they take two presses: the first turns the button into "Sure?" and the second (within a few seconds) sends.
struct PullRequestReviewView: View {
    @Bindable var controller: GitHubController

    var body: some View {
        if let target = controller.reviewTarget {
            VStack(spacing: 8) {
                header(target)
                // What there is to read scrolls; the actions below it never do.
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        chips(target)
                        standing
                        outcome
                        if let reason = controller.reviewBlockReason { note(reason, color: IslandTheme.keepAwake) }
                        commentBox
                        description
                    }
                }
                .scrollIndicators(.hidden)
                actions(target)
            }
        }
    }

    // MARK: The top

    private func header(_ target: GitHubPullRequest) -> some View {
        let pull = controller.reviewedPullRequest ?? target
        return HStack(alignment: .top, spacing: 10) {
            Button { controller.closeReview() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to the list")

            VStack(alignment: .leading, spacing: 2) {
                Text(pull.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: meta(pull)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                if let head = pull.headBranch, let base = pull.baseBranch { branches(head: head, base: base) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func meta(_ pull: GitHubPullRequest) -> String {
        var parts = ["\(pull.repoFullName) #\(pull.number)"]
        if let author = pull.authorLogin { parts.append("by \(author)") }
        return parts.joined(separator: " · ")
    }

    /// Where the change is going and where it comes from, on a line of its own: `staging ← feature/login`. The base
    /// stays whole; a very long branch name gives way in its middle.
    private func branches(head: String, base: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: base).layoutPriority(1)
            Image(systemName: "arrow.left").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            Text(verbatim: head).truncationMode(.middle)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
    }

    // MARK: What it is

    /// The state of the checks and of the reviews, the size of the change, and a conflict warning, as small chips. The
    /// checks and the review decision come from the list the pull request was opened from; the size loads on opening.
    private func chips(_ target: GitHubPullRequest) -> some View {
        let pull = controller.reviewedPullRequest ?? target
        return HStack(spacing: 6) {
            switch target.checks {
            case .passing: chip("Checks passing", symbol: "checkmark.circle.fill", color: IslandTheme.tasks)
            case .failing: chip("Checks failing", symbol: "xmark.circle.fill", color: IslandTheme.danger)
            case .pending: chip("Checks running", symbol: "clock.fill", color: IslandTheme.keepAwake)
            case nil: EmptyView()
            }
            if pull.state == .merged { chip("Merged", symbol: "arrow.triangle.merge", color: IslandTheme.github) }
            if pull.state == .closed { chip("Closed", symbol: "xmark.circle", color: IslandTheme.danger) }
            if pull.isDraft { chip("Draft", symbol: "pencil", color: .white.opacity(0.7)) }
            if target.hasConflicts || controller.reviewDetails?.hasConflicts == true {
                chip("Conflicts", symbol: "exclamationmark.triangle.fill", color: IslandTheme.danger)
            }
            if let details = controller.reviewDetails {
                Text(verbatim: "\(details.commits) commit\(details.commits == 1 ? "" : "s") · \(details.changedFiles) file\(details.changedFiles == 1 ? "" : "s")")
                    .foregroundStyle(.white.opacity(0.6))
                Text(verbatim: "+\(details.additions)").foregroundStyle(IslandTheme.tasks)
                Text(verbatim: "−\(details.deletions)").foregroundStyle(IslandTheme.danger)
            } else if controller.isLoadingReview {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .lineLimit(1)
    }

    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .fixedSize()
    }

    // MARK: Where everyone stands

    @ViewBuilder
    private var standing: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let mine = controller.myStanding {
                switch mine.verdict {
                case .approved: line("You approved this pull request.", color: IslandTheme.tasks, bold: true)
                case .changesRequested: line("You asked for changes on this pull request.", color: IslandTheme.focus, bold: true)
                case .dismissed: line("Your earlier review was dismissed.", color: .white.opacity(0.6), bold: false)
                default: EmptyView()
                }
            }
            if let details = controller.reviewDetails {
                if !details.approvers.isEmpty { line("Approved by \(names(details.approvers)).", color: IslandTheme.tasks.opacity(0.9), bold: false) }
                if !details.changeRequesters.isEmpty { line("Changes requested by \(names(details.changeRequesters)).", color: IslandTheme.focus, bold: false) }
            }
        }
        .padding(.horizontal, 4)
    }

    private func line(_ text: String, color: Color, bold: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: bold ? .bold : .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "ravi, priya and sam".
    private func names(_ list: [String]) -> String {
        list.count <= 1 ? (list.first ?? "") : list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "")
    }

    /// What was just sent.
    @ViewBuilder
    private var outcome: some View {
        if case .done(let event) = controller.reviewSubmission {
            switch event {
            case .approve: note("✓ Approved. Your approval is on the pull request.", color: IslandTheme.tasks, bold: true)
            case .requestChanges: note("✓ Changes requested. The author has been asked to change it.", color: IslandTheme.focus, bold: true)
            case .comment: note("✓ Comment sent.", color: IslandTheme.accent, bold: true)
            }
        }
    }

    private func note(_ text: String, color: Color, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: bold ? .bold : .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: What to read and write

    @ViewBuilder
    private var description: some View {
        if let details = controller.reviewDetails {
            let text = details.body.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(text.isEmpty ? "No description." : text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(text.isEmpty ? 0.35 : 0.7))
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var commentBox: some View {
        ZStack(alignment: .topLeading) {
            ToolTextView(text: $controller.reviewComment, isEditable: true)
            if controller.reviewComment.isEmpty {
                Text("Leave a comment (needed to request changes)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.leading, ToolTextView.inset.width)
                    .padding(.top, ToolTextView.inset.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 54)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: The actions

    private func actions(_ target: GitHubPullRequest) -> some View {
        let sending: GitHubReviewEvent? = { if case .submitting(let event) = controller.reviewSubmission { event } else { nil } }()
        return HStack(spacing: 8) {
            iconButton("doc.on.doc", help: "Copy the link") { controller.copyLink(of: target) }
            iconButton("arrow.up.right", help: "Open on GitHub") { NSWorkspace.shared.open(target.url) }
            Spacer(minLength: 0)
            actionButton(.comment, title: "Comment", sendingTitle: "Sending…", color: nil, sending: sending)
            actionButton(.requestChanges, title: "Request changes", sendingTitle: "Sending…", color: IslandTheme.focus, sending: sending)
            actionButton(.approve, title: "Approve", sendingTitle: "Approving…", color: IslandTheme.tasks, sending: sending)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// One of the three actions. A coloured one is solid once pressed ("Sure?"), so it is clear which is about to be sent.
    private func actionButton(_ event: GitHubReviewEvent, title: String, sendingTitle: String, color: Color?, sending: GitHubReviewEvent?) -> some View {
        let enabled = controller.canSubmit(event)
        let asking = controller.confirming == event
        let busy = sending == event
        let label = busy ? sendingTitle : (asking ? "Sure? \(title)" : title)
        return Button { Task { await controller.pressReviewButton(event) } } label: {
            HStack(spacing: 5) {
                if busy { ProgressView().controlSize(.mini) }
                Text(label)
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: 30)
            .foregroundStyle(asking ? Color.black : (color == nil ? Color.white : color!))
            .background(asking ? (color ?? Color.white) : (color?.opacity(0.18) ?? Color.white.opacity(0.14)), in: Capsule())
            .opacity(enabled || busy ? 1 : 0.35)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(helpText(for: event, enabled: enabled))
    }

    private func helpText(for event: GitHubReviewEvent, enabled: Bool) -> String {
        switch event {
        case .approve: return "Approve this pull request (press twice)"
        case .requestChanges: return enabled ? "Ask the author to change something (press twice)" : "Write a comment first: say what needs changing"
        case .comment: return enabled ? "Leave a comment without approving or rejecting" : "Write a comment first"
        }
    }
}
