import Foundation
import Testing
@testable import IslandCore

// The "Files changed" data: GitHub's patches turned into numbered lines, and the file list around them. The real patches in
// GitHubDiffFixtures.swift are checked against the counts GitHub itself reported for them.

private func lines(_ hunks: [GitHubDiffHunk]) -> [GitHubDiffLine] { hunks.flatMap(\.lines) }

private func count(_ kind: GitHubDiffLine.Kind, in hunks: [GitHubDiffHunk]) -> Int { lines(hunks).filter { $0.kind == kind }.count }

private let realFiles = [real_modifiedThreeHunks, real_modifiedFourHunks, real_addedFile]

// MARK: Real patches

@Test func theLinesOfARealPatchAddUpToWhatGitHubCounted() {
    for file in realFiles {
        let hunks = GitHubDiff.hunks(fromPatch: file.patch)
        #expect(count(.added, in: hunks) == file.additions, "\(file.filename): added lines")
        #expect(count(.removed, in: hunks) == file.deletions, "\(file.filename): removed lines")
    }
}

@Test func everyHunkOfARealPatchHasTheLineCountsItsHeaderPromises() throws {
    for file in realFiles {
        for hunk in GitHubDiff.hunks(fromPatch: file.patch) {
            // "@@ -a,b +c,d @@": b lines come from the old file (context + removed), d lines go to the new one (context + added).
            let numbers = hunk.header.split(separator: " ")
            let oldCount = Int(numbers[1].dropFirst().split(separator: ",").dropFirst().first ?? "1") ?? 1
            let newCount = Int(numbers[2].dropFirst().split(separator: ",").dropFirst().first ?? "1") ?? 1
            let context = hunk.lines.filter { $0.kind == .context }.count
            let removed = hunk.lines.filter { $0.kind == .removed }.count
            let added = hunk.lines.filter { $0.kind == .added }.count
            #expect(context + removed == oldCount, "\(file.filename) \(hunk.header): old side")
            #expect(context + added == newCount, "\(file.filename) \(hunk.header): new side")
        }
    }
}

@Test func lineNumbersInARealPatchRunOnFromTheHeaderAndSkipTheOtherSide() throws {
    let hunks = GitHubDiff.hunks(fromPatch: real_modifiedThreeHunks.patch)
    #expect(hunks.count == 3)
    let first = try #require(hunks.first)
    #expect(first.header == "@@ -2,8 +2,8 @@")
    #expect(first.lines.first == GitHubDiffLine(id: 0, kind: .context, text: "description: |", oldNumber: 2, newNumber: 2))
    let removed = first.lines.filter { $0.kind == .removed }
    let added = first.lines.filter { $0.kind == .added }
    #expect(removed.map(\.oldNumber) == [5, 6] && removed.allSatisfy { $0.newNumber == nil })      // a removed line has no new number
    #expect(added.map(\.newNumber) == [5, 6] && added.allSatisfy { $0.oldNumber == nil })          // and an added line has no old one
    #expect(removed.first?.text.hasPrefix("  and applies the minimal correct end-state labels") == true)   // the "-" is gone, its indent stays
    #expect(hunks[1].header == "@@ -42,8 +42,8 @@ permissions:")                                         // the section name stays in the header
    #expect(hunks[1].lines.first?.oldNumber == 42)
}

@Test func lineIdsAreUniqueAcrossAllTheHunksOfAFile() {
    for file in realFiles {
        let ids = lines(GitHubDiff.hunks(fromPatch: file.patch)).map(\.id)
        #expect(Set(ids).count == ids.count && ids == Array(0..<ids.count), "\(file.filename)")
    }
    #expect(GitHubDiff.hunks(fromPatch: real_modifiedFourHunks.patch).map(\.id) == [0, 1, 2, 3])
}

@Test func aNewFileIsOneHunkOfAddedLinesNumberedFromOne() throws {
    let hunks = GitHubDiff.hunks(fromPatch: real_addedFile.patch)
    let hunk = try #require(hunks.first)
    #expect(hunks.count == 1 && hunk.header == "@@ -0,0 +1,25 @@")
    #expect(hunk.lines.allSatisfy { $0.kind == .added && $0.oldNumber == nil })
    #expect(hunk.lines.map(\.newNumber) == (1...25).map { $0 })
}

// MARK: Shapes the real samples did not have

@Test func theNoNewlineMarkerBelongsToTheLineAboveAndHasNoNumbers() {
    let hunks = GitHubDiff.hunks(fromPatch: "@@ -1,2 +1,2 @@\n one\n-two\n\\ No newline at end of file\n+three\n\\ No newline at end of file")
    let all = lines(hunks)
    #expect(all.map(\.kind) == [.context, .removed, .note, .added, .note])
    #expect(all[2].text == "\\ No newline at end of file" && all[2].oldNumber == nil && all[2].newNumber == nil)
    #expect(all[3].newNumber == 2 && all[1].oldNumber == 2)                      // the notes did not use up a line number
}

@Test func aHeaderWithoutCountsIsReadAndAWindowsFileLosesItsCarriageReturns() {
    let hunks = GitHubDiff.hunks(fromPatch: "@@ -3 +3,2 @@ f\r\n-old\r\n+new\r\n+more\r\n")
    #expect(hunks.count == 1 && hunks[0].header == "@@ -3 +3,2 @@ f")
    #expect(lines(hunks).map(\.text) == ["old", "new", "more"])
    #expect(lines(hunks).map(\.oldNumber) == [3, nil, nil] && lines(hunks).map(\.newNumber) == [nil, 3, 4])
}

@Test func aBlankContextLineWhoseSpaceWasTrimmedStillCountsAsALine() {
    let all = lines(GitHubDiff.hunks(fromPatch: "@@ -1,3 +1,3 @@\n a\n\n-b\n+c"))
    #expect(all.map(\.kind) == [.context, .context, .removed, .added])
    #expect(all[1].text.isEmpty && all[1].oldNumber == 2 && all[1].newNumber == 2)
    #expect(all[2].oldNumber == 3 && all[3].newNumber == 3)
}

@Test func aPatchEndingInANewlineGainsNoPhantomLine() {
    #expect(lines(GitHubDiff.hunks(fromPatch: "@@ -1 +1 @@\n-a\n+b\n")).count == 2)
}

@Test func nothingBeforeTheFirstHunkAndNoUnreadableHeaderIsKeptAsDiff() {
    #expect(GitHubDiff.hunks(fromPatch: "").isEmpty)
    #expect(GitHubDiff.hunks(fromPatch: "no hunk here\n+not a line").isEmpty)
    #expect(GitHubDiff.hunks(fromPatch: "diff --git a/x b/x\n@@ -1 +1 @@\n-a\n+b").count == 1)
    #expect(GitHubDiff.hunks(fromPatch: "@@ nonsense @@\n+x").isEmpty)
}

@Test func aCombiningMarkRightAfterTheMarkerDoesNotHideTheMarker() {
    // "+" followed by a combining accent is one character to Swift, but it is still an added line.
    let all = lines(GitHubDiff.hunks(fromPatch: "@@ -1,2 +1,2 @@\n+\u{0301}x\n-\u{0308}y"))
    #expect(all.map(\.kind) == [.added, .removed])
    #expect(all[0].text == "\u{0301}x" && all[1].text == "\u{0308}y")
}

@Test func aPlusOrMinusInsideTheTextIsNotConfusedWithTheMarker() {
    let all = lines(GitHubDiff.hunks(fromPatch: "@@ -1,2 +1,2 @@\n-- a comment\n+++ b\n c"))
    #expect(all.map(\.kind) == [.removed, .added, .context])
    #expect(all[0].text == "- a comment" && all[1].text == "++ b")
}

// MARK: The file list

private func filesJSON(_ entries: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: entries) }

@Test func theFileListCarriesNamesStatusesCountsAndParsedChanges() throws {
    let data = filesJSON([
        ["filename": real_modifiedThreeHunks.filename, "status": real_modifiedThreeHunks.status, "additions": real_modifiedThreeHunks.additions,
            "deletions": real_modifiedThreeHunks.deletions, "changes": 10, "patch": real_modifiedThreeHunks.patch],
        ["filename": real_addedFile.filename, "status": "added", "additions": 25, "deletions": 0, "changes": 25, "patch": real_addedFile.patch],
    ])
    let files = try GitHubDecoding.changedFiles(from: data)
    #expect(files.map(\.filename) == [".github/workflows/issue-triage.md", "pr_body.md"])
    #expect(files.map(\.status) == [.modified, .added])
    #expect(files.map(\.additions) == [5, 25] && files.map(\.deletions) == [5, 0])
    #expect(files[0].hunks.count == 3 && files[0].availability == .shown)
    #expect(files[0].name == "issue-triage.md" && files[0].directory == ".github/workflows/")
    #expect(files[1].name == "pr_body.md" && files[1].directory.isEmpty)
}

@Test func aRenamedFileKnowsItsOldNameAndAHugeOrBinaryOneSaysWhyThereIsNoDiff() throws {
    let data = filesJSON([
        ["filename": "new/Name.swift", "previous_filename": "old/Name.swift", "status": "renamed", "additions": 0, "deletions": 0, "changes": 0],
        ["filename": "logo.png", "status": "modified", "additions": 0, "deletions": 0, "changes": 0],
        ["filename": "Generated.json", "status": "modified", "additions": 4000, "deletions": 3800, "changes": 7800],
        ["filename": "renamed-and-edited.txt", "previous_filename": "a.txt", "status": "renamed", "additions": 1, "deletions": 1, "changes": 2,
            "patch": "@@ -1 +1 @@\n-a\n+b"],
    ])
    let files = try GitHubDecoding.changedFiles(from: data)
    #expect(files[0].status == .renamed && files[0].previousFilename == "old/Name.swift" && files[0].availability == .noContentChange)
    #expect(files[1].availability == .noContentChange && files[1].hunks.isEmpty)       // no patch, no counted lines: binary or permissions
    #expect(files[2].availability == .tooLargeOrBinary && files[2].additions == 4000)  // lines changed but GitHub did not send them
    #expect(files[3].availability == .shown && files[3].previousFilename == "a.txt")
}

@Test func anUnknownStatusOrAMissingFieldNeverStopsTheListLoading() throws {
    let files = try GitHubDecoding.changedFiles(from: filesJSON([
        ["filename": "a.txt", "status": "some-new-status"], ["status": "added"], ["filename": "b.txt"],
    ]))
    #expect(files.map(\.filename) == ["a.txt", "b.txt"])                                  // the one without a name is dropped
    #expect(files.allSatisfy { $0.status == .modified && $0.additions == 0 })
    #expect(throws: GitHubError.self) { try GitHubDecoding.changedFiles(from: Data("not json".utf8)) }
}

@Test func everyStatusGitHubDocumentsIsKnown() {
    for name in ["added", "removed", "modified", "renamed", "copied", "changed", "unchanged"] { #expect(GitHubFileStatus(rawValue: name) != nil, "\(name)") }
}

// MARK: Filtering the files by name

private let filterFiles = [
    GitHubChangedFile(filename: "hub/apisix/production/routes/activities/activities-routes.yaml"),
    GitHubChangedFile(filename: "hub/apisix/production/routes/default/api-routes.yaml"),
    GitHubChangedFile(filename: "Sources/App/Button.swift"),
    GitHubChangedFile(filename: "Sources/App/Renamed.swift", previousFilename: "Sources/Old/Original.swift", status: .renamed),
    GitHubChangedFile(filename: "README.md"),
]

private func names(_ files: [GitHubChangedFile]) -> [String] { files.map(\.filename) }

@Test func nothingTypedLeavesEveryFileInItsOrder() {
    #expect(GitHubFileFilter.files(filterFiles, matching: "") == filterFiles)
    #expect(GitHubFileFilter.files(filterFiles, matching: "   \t ") == filterFiles)
    #expect(GitHubFileFilter.files([], matching: "x").isEmpty)
}

@Test func aFileNameLeavesOnlyTheFilesWhosePathHasIt() {
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "api-routes")) == ["hub/apisix/production/routes/default/api-routes.yaml"])
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "routes.yaml")).count == 2)
    #expect(names(GitHubFileFilter.files(filterFiles, matching: ".swift")) == ["Sources/App/Button.swift", "Sources/App/Renamed.swift"])
    #expect(GitHubFileFilter.files(filterFiles, matching: "no-such-file").isEmpty)
}

@Test func capitalsAndSurroundingSpacesDoNotMatter() {
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "  BUTTON ")) == ["Sources/App/Button.swift"])
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "readme")) == ["README.md"])
}

@Test func aFolderNameFindsTheFilesInIt() {
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "activities/")) == ["hub/apisix/production/routes/activities/activities-routes.yaml"])
    #expect(GitHubFileFilter.files(filterFiles, matching: "production").count == 2)
}

@Test func everyWordTypedMustMatchSoMoreWordsNarrowItDown() {
    #expect(GitHubFileFilter.files(filterFiles, matching: "routes").count == 2)
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "routes default")) == ["hub/apisix/production/routes/default/api-routes.yaml"])
    #expect(GitHubFileFilter.files(filterFiles, matching: "routes button").isEmpty)
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "app button swift")) == ["Sources/App/Button.swift"])
}

@Test func aRenamedFileIsFoundByItsOldNameToo() {
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "original")) == ["Sources/App/Renamed.swift"])
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "renamed")) == ["Sources/App/Renamed.swift"])
    #expect(names(GitHubFileFilter.files(filterFiles, matching: "old/orig")) == ["Sources/App/Renamed.swift"])
    // The words must all be in ONE of the two names, not one in each.
    #expect(GitHubFileFilter.files(filterFiles, matching: "original button").isEmpty)
}

@Test func filteringKeepsTheOrderAndTheFilesThemselves() {
    let found = GitHubFileFilter.files(filterFiles, matching: "s")
    #expect(found == filterFiles.filter { $0.filename.lowercased().contains("s") || ($0.previousFilename?.lowercased().contains("s") ?? false) })
    #expect(zip(found, found.dropFirst()).allSatisfy { a, b in filterFiles.firstIndex(of: a)! < filterFiles.firstIndex(of: b)! })
}

// MARK: The requests

@Test func theChangedFilesAreAskedForExactly() throws {
    let repo = GitHubRepoRef(fullName: "acme/app")
    let files = GitHubRequests.pullRequestFiles(token: "tok", repo, number: 7, page: 2)
    #expect(files.url?.absoluteString == "https://api.github.com/repos/acme/app/pulls/7/files?per_page=100&page=2")
    #expect(files.httpMethod == nil || files.httpMethod == "GET")
    #expect(files.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(GitHubRequests.pullRequestFiles(token: "tok", repo, number: 7).url?.absoluteString.hasSuffix("page=1") == true)
}
