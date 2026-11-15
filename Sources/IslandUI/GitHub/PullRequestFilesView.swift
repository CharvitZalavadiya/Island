import AppKit
import SwiftUI
import IslandCore

/// "Files changed", as on GitHub's website: the files in a list on the left, and every file's changes one under another on the
/// right, with the line numbers before and after, additions in green and removals in red. A file's name bar stays at the top
/// while its changes scroll under it. A click on a file in the list goes to it; a click on a name bar folds its changes away.
///
/// It is shown by the review panel when the island is big enough (Max and focus mode), and loads the files only then.
struct PullRequestFilesView: View {
    @Bindable var controller: GitHubController
    /// The file last picked in the list.
    @State private var selected: String?
    @State private var collapsed: Set<String> = []
    /// What is typed in the filter box: only the files whose name has it are shown, in the list and below.
    @State private var filter = ""

    var body: some View {
        Group {
            switch controller.reviewFiles {
            case .idle, .loading:
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading the changed files…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                VStack(spacing: 8) {
                    Text("Couldn't load the changed files.").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    PillButton(title: "Try again", height: 28) { Task { await controller.loadReviewFiles() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let files):
                if files.isEmpty {
                    Text("This pull request changes no files.").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content(files)
                }
            }
        }
        // Asked for when this appears (the island got big enough), and again for another pull request.
        .task(id: controller.reviewTarget?.id) { await controller.loadReviewFiles() }
    }

    // MARK: The files and their changes

    private func content(_ files: [GitHubChangedFile]) -> some View {
        let shown = GitHubFileFilter.files(files, matching: filter)
        return VStack(spacing: 8) {
            summary(files, shown: shown)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 8) {
                    filterBox
                    if shown.isEmpty {
                        Spacer(minLength: 0)
                    } else {
                        fileList(shown)
                    }
                }
                .frame(width: 210)
                if shown.isEmpty {
                    noMatch(of: files.count)
                } else {
                    changes(shown)
                }
            }
        }
    }

    /// The box to type a file's name in. It waits to be clicked (the keyboard is not taken from the app you are in), and the
    /// small cross, or emptying it, brings every file back.
    private var filterBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            SearchField(text: $filter, placeholder: "Filter files by name", focusesOnAppear: false, onCancel: { filter = "" })
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: 18, height: 18).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Show all the files again")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.white.opacity(0.1), in: Capsule())
    }

    private func noMatch(of count: Int) -> some View {
        VStack(spacing: 8) {
            Text("No file matches “\(filter.trimmingCharacters(in: .whitespaces))”.")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
            PillButton(title: "Show all \(count) files", height: 28) { filter = "" }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The totals are for the whole pull request, as on GitHub; while filtering it also says how many are shown.
    private func summary(_ files: [GitHubChangedFile], shown: [GitHubChangedFile]) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(files.count) file\(files.count == 1 ? "" : "s") changed").foregroundStyle(.white.opacity(0.7))
            Text(verbatim: "+\(files.reduce(0) { $0 + $1.additions })").foregroundStyle(IslandTheme.tasks)
            Text(verbatim: "−\(files.reduce(0) { $0 + $1.deletions })").foregroundStyle(IslandTheme.danger)
            if shown.count != files.count {
                Text(verbatim: "· showing \(shown.count)").foregroundStyle(IslandTheme.accent)
            }
            Spacer(minLength: 0)
            Button {
                collapsed = collapsed.isEmpty ? Set(shown.map(\.id)) : []
            } label: {
                Text(collapsed.isEmpty ? "Fold all" : "Unfold all")
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .semibold))
    }

    private func fileList(_ files: [GitHubChangedFile]) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(files) { file in
                    Button {
                        collapsed.remove(file.id)
                        selected = file.id
                    } label: {
                        HStack(spacing: 7) {
                            StatusBadge(status: file.status)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: file.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                if !file.directory.isEmpty {
                                    Text(verbatim: file.directory).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                                        .lineLimit(1).truncationMode(.head)
                                }
                            }
                            Spacer(minLength: 0)
                            if file.additions + file.deletions > 0 {
                                VStack(alignment: .trailing, spacing: 0) {
                                    if file.additions > 0 { Text(verbatim: "+\(file.additions)").foregroundStyle(IslandTheme.tasks) }
                                    if file.deletions > 0 { Text(verbatim: "−\(file.deletions)").foregroundStyle(IslandTheme.danger) }
                                }
                                .font(.system(size: 9.5, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selected == file.id ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(file.previousFilename.map { "\($0) → \(file.filename)" } ?? file.filename)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func changes(_ files: [GitHubChangedFile]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Every line is a direct child of the lazy stack, so a file with thousands of lines only builds the ones on screen.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(files) { file in
                        Section {
                            if !collapsed.contains(file.id) { FileChanges(file: file) }
                        } header: {
                            fileBar(file).id(file.id)
                        } footer: {
                            Color.clear.frame(height: 10)
                        }
                    }
                }
                .textSelection(.enabled)
            }
            .onChange(of: selected) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    /// A file's name bar, which stays at the top while its changes scroll beneath it.
    private func fileBar(_ file: GitHubChangedFile) -> some View {
        Button {
            if collapsed.contains(file.id) { collapsed.remove(file.id) } else { collapsed.insert(file.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsed.contains(file.id) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 10)
                StatusBadge(status: file.status)
                Group {
                    if let previous = file.previousFilename {
                        Text(verbatim: "\(previous) → \(file.filename)")
                    } else {
                        Text(verbatim: file.filename)
                    }
                }
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(verbatim: "+\(file.additions)").foregroundStyle(IslandTheme.tasks)
                Text(verbatim: "−\(file.deletions)").foregroundStyle(IslandTheme.danger)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // Solid, so the lines scrolling under the bar do not show through it.
            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
        .background(Color.black)
    }
}

/// One letter in a coloured square: what happened to the file.
struct StatusBadge: View {
    let status: GitHubFileStatus

    var body: some View {
        Text(verbatim: letter)
            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: 15, height: 15)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .help(status.rawValue.capitalized)
    }

    private var letter: String {
        switch status {
        case .added: "A"
        case .removed: "D"
        case .modified: "M"
        case .renamed: "R"
        case .copied: "C"
        case .changed, .unchanged: "•"
        }
    }

    private var color: Color {
        switch status {
        case .added: IslandTheme.tasks
        case .removed: IslandTheme.danger
        case .modified: IslandTheme.keepAwake
        case .renamed, .copied: IslandTheme.github
        case .changed, .unchanged: .white.opacity(0.6)
        }
    }
}

/// The changes of one file: its hunks, line by line, or the reason there is nothing to show.
struct FileChanges: View {
    let file: GitHubChangedFile

    var body: some View {
        switch file.availability {
        case .shown:
            // Every file numbers its hunks and lines from 0, and a lazy stack takes equal ids for the same row: without an id that is
            // unique across the whole list, only the first file's rows were ever built and the others showed an empty box.
            ForEach(file.hunks) { hunk in
                HunkHeaderRow(text: hunk.header).id("\(file.id)|hunk \(hunk.id)")
                ForEach(hunk.lines) { line in DiffLineRow(line: line).id("\(file.id)|line \(line.id)") }
            }
        case .noContentChange:
            reason(file.status == .renamed
                ? "Renamed without changes."
                : "No lines changed. The file may be binary, or only its permissions changed.")
        case .tooLargeOrBinary:
            reason("GitHub doesn't send this file's changes: it is binary, or the change is too big. Open the pull request on GitHub to see it.")
        }
    }

    private func reason(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `@@ -12,7 +12,9 @@ func name`, in the colour GitHub gives it, across the width of the file.
struct HunkHeaderRow: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(IslandTheme.accent.opacity(0.85))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IslandTheme.accent.opacity(0.1))
    }
}

/// One line of a diff: the old and the new line number, a + or − (or nothing), and the text, wrapped if it is long.
struct DiffLineRow: View {
    let line: GitHubDiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)
            Text(verbatim: sign)
                .foregroundStyle(signColor)
                .frame(width: 16)
            Text(verbatim: shown)
                .foregroundStyle(line.kind == .note ? Color.white.opacity(0.4) : Color.white.opacity(0.88))
                .italic(line.kind == .note)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 8)
        }
        .font(.system(size: 11, design: .monospaced))
        .background(background)
    }

    /// A tab is shown as four spaces, and an empty line keeps its height.
    private var shown: String {
        line.text.isEmpty ? " " : line.text.replacingOccurrences(of: "\t", with: "    ")
    }

    private func gutter(_ number: Int?) -> some View {
        Text(verbatim: number.map(String.init) ?? "")
            .foregroundStyle(.white.opacity(0.35))
            .frame(width: 42, alignment: .trailing)
            .padding(.trailing, 4)
            .background(gutterBackground)
    }

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context, .note: ""
        }
    }

    private var signColor: Color {
        line.kind == .added ? IslandTheme.tasks : IslandTheme.danger
    }

    private var background: Color {
        switch line.kind {
        case .added: IslandTheme.tasks.opacity(0.13)
        case .removed: IslandTheme.danger.opacity(0.13)
        case .context, .note: .clear
        }
    }

    private var gutterBackground: Color {
        switch line.kind {
        case .added: IslandTheme.tasks.opacity(0.14)
        case .removed: IslandTheme.danger.opacity(0.14)
        case .context, .note: .white.opacity(0.03)
        }
    }
}
