import AppKit
import SwiftUI
import IslandCore

/// A list of pull requests (the person's own open ones, or the ones waiting for their review), each with a button to copy
/// its link and one to open it.
struct PullRequestListView: View {
    let controller: GitHubController
    let pullRequests: [GitHubPullRequest]
    let emptyText: String

    var body: some View {
        if pullRequests.isEmpty {
            VStack {
                Spacer()
                if !controller.listsLoaded {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading pull requests…").font(.callout).foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    Text(emptyText).font(.callout).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(pullRequests) { PullRequestRow(controller: controller, pullRequest: $0) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// One pull request: its title, where it is and how long ago it changed. The buttons on the right appear while the pointer
/// is on the row; a right click offers the same and "Copy as Markdown".
struct PullRequestRow: View {
    let controller: GitHubController
    let pullRequest: GitHubPullRequest
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pullRequest.isDraft ? Color.white.opacity(0.45) : IslandTheme.tasks)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(pullRequest.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(pullRequest.repoFullName) #\(pullRequest.number)")
                    if let updated = pullRequest.updatedAt { Text("· \(Self.relative(updated))") }
                    if pullRequest.isDraft {
                        Text("Draft")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Shown only while the pointer is on the row, so the row keeps its shape. "Copied" keeps it on for a moment.
            let copied = controller.copiedID == pullRequest.id
            HStack(spacing: 6) {
                Button { controller.copyLink(of: pullRequest) } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copied ? IslandTheme.tasks : IslandTheme.github)
                        .frame(width: 26, height: 26)
                        .background(IslandTheme.github.opacity(0.18), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy the link")
                Button { NSWorkspace.shared.open(pullRequest.url) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(IslandTheme.github)
                        .frame(width: 26, height: 26)
                        .background(IslandTheme.github.opacity(0.18), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open on GitHub")
            }
            .opacity(hovering || copied ? 1 : 0)
            .allowsHitTesting(hovering || copied)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy link") { controller.copyLink(of: pullRequest) }
            Button("Copy as Markdown") { controller.copyMarkdown(of: pullRequest) }
            Button("Open on GitHub") { NSWorkspace.shared.open(pullRequest.url) }
        }
    }

    /// "2 hr. ago", "3 days ago".
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
