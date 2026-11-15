import Foundation

/// How one file changed in a pull request, as GitHub's "Files changed" tab words it.
public enum GitHubFileStatus: String, Equatable, Sendable {
    case added, removed, modified, renamed, copied, changed, unchanged
}

/// One line of a diff, with the line numbers it has before and after the change (a line that was added has no old number).
public struct GitHubDiffLine: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case context, added, removed
        /// "\ No newline at end of file", which belongs to the line above it.
        case note
    }

    /// Unique within its file, so a list of them can be built from every hunk of the file together.
    public var id: Int
    public var kind: Kind
    public var text: String
    public var oldNumber: Int?
    public var newNumber: Int?
}

/// A run of changes with the lines around it, under a header like `@@ -12,7 +12,9 @@ func name`.
public struct GitHubDiffHunk: Equatable, Sendable, Identifiable {
    public var id: Int
    public var header: String
    public var lines: [GitHubDiffLine]
}

/// Whether there are changed lines to show for a file, and if not, why.
public enum GitHubDiffAvailability: Equatable, Sendable {
    case shown
    /// Renamed, moved, or only its permissions changed: no line changed, so GitHub sends no diff.
    case noContentChange
    /// Lines changed, but GitHub did not send them: the file is binary, or the change is too big to send.
    case tooLargeOrBinary
}

/// One file of a pull request: its name, what happened to it, its size in lines, and the changes themselves.
public struct GitHubChangedFile: Equatable, Sendable, Identifiable {
    public var id: String { filename }
    public var filename: String
    public var previousFilename: String?
    public var status: GitHubFileStatus
    public var additions: Int
    public var deletions: Int
    public var hunks: [GitHubDiffHunk]
    public var availability: GitHubDiffAvailability

    public init(
        filename: String, previousFilename: String? = nil, status: GitHubFileStatus = .modified, additions: Int = 0, deletions: Int = 0,
        hunks: [GitHubDiffHunk] = [], availability: GitHubDiffAvailability? = nil
    ) {
        self.filename = filename
        self.previousFilename = previousFilename
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.hunks = hunks
        self.availability = availability ?? (hunks.isEmpty ? (additions + deletions == 0 ? .noContentChange : .tooLargeOrBinary) : .shown)
    }

    /// The last part of the path: `Button.swift`.
    public var name: String { filename.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? filename }

    /// The folders, with the slash that follows them: `Sources/UI/`; empty for a file at the top.
    public var directory: String { String(filename.dropLast(name.count)) }
}

public enum GitHubDiff {
    /// The hunks of the patch GitHub sends for one file (a unified diff, from its first `@@` line on). Lenient: lines before the
    /// first hunk header, or a header it cannot read, are skipped rather than failing the whole file.
    public static func hunks(fromPatch patch: String) -> [GitHubDiffHunk] {
        // Split on the newline itself: Swift reads "\r\n" as ONE character, so splitting on "\n" would not cut a Windows file's lines.
        var pieces = patch.components(separatedBy: "\n")
        if pieces.last?.isEmpty == true { pieces.removeLast() }          // a patch that ends with a newline has no extra empty line

        var hunks: [GitHubDiffHunk] = []
        var header: String?
        var lines: [GitHubDiffLine] = []
        var oldNumber = 0, newNumber = 0
        var nextID = 0

        func finishHunk() {
            if let header { hunks.append(GitHubDiffHunk(id: hunks.count, header: header, lines: lines)) }
            header = nil
            lines = []
        }
        func add(_ kind: GitHubDiffLine.Kind, _ text: String, old: Int?, new: Int?) {
            lines.append(GitHubDiffLine(id: nextID, kind: kind, text: text, oldNumber: old, newNumber: new))
            nextID += 1
        }

        for piece in pieces {
            var line = piece
            if line.hasSuffix("\r") { line.removeLast() }                 // a file with Windows line endings
            if line.hasPrefix("@@"), let start = startNumbers(inHeader: line) {
                finishHunk()
                header = line
                oldNumber = start.old
                newNumber = start.new
                continue
            }
            guard header != nil else { continue }
            // The marker is the first scalar, not the first character: a combining mark right after it would otherwise join it.
            guard let marker = line.unicodeScalars.first else {            // a blank context line whose space was trimmed
                add(.context, "", old: oldNumber, new: newNumber)
                oldNumber += 1
                newNumber += 1
                continue
            }
            let text = String(line.unicodeScalars.dropFirst())
            switch marker {
            case "+":
                add(.added, text, old: nil, new: newNumber)
                newNumber += 1
            case "-":
                add(.removed, text, old: oldNumber, new: nil)
                oldNumber += 1
            case "\\":
                add(.note, line, old: nil, new: nil)
            case " ":
                add(.context, text, old: oldNumber, new: newNumber)
                oldNumber += 1
                newNumber += 1
            default:                                                       // not a diff line at all: keep it, unnumbered
                add(.note, line, old: nil, new: nil)
            }
        }
        finishHunk()
        return hunks
    }

    /// The line each side starts at, from `@@ -12,7 +12,9 @@ …` (a count is left out when it is 1: `@@ -3 +3,2 @@`).
    private static func startNumbers(inHeader header: String) -> (old: Int, new: Int)? {
        let parts = header.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "@@", parts[1].hasPrefix("-"), parts[2].hasPrefix("+") else { return nil }
        func start(_ part: Substring) -> Int? { part.dropFirst().split(separator: ",", omittingEmptySubsequences: false).first.flatMap { Int($0) } }
        guard let old = start(parts[1]), let new = start(parts[2]) else { return nil }
        return (old, new)
    }
}

/// The file filter of the "Files changed" view: typing part of a file's name (or folder) leaves only the files that match.
public enum GitHubFileFilter {
    /// The files whose path contains every word typed, ignoring capitals (`routes act` finds `routes/activities/x.yaml`); a
    /// renamed file also matches by the name it had before. Nothing typed, or only spaces, leaves all of them, in their order.
    public static func files(_ files: [GitHubChangedFile], matching text: String) -> [GitHubChangedFile] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return files }
        return files.filter { file in
            let paths = [file.filename.lowercased()] + (file.previousFilename.map { [$0.lowercased()] } ?? [])
            return paths.contains { path in words.allSatisfy { path.contains($0) } }
        }
    }
}
