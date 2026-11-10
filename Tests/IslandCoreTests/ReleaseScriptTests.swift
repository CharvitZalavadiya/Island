import Foundation
import Testing

// The scripts the release workflow runs, tried here so that "only a new version is released" cannot quietly break.

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@discardableResult
private func runScript(
    _ path: String, _ arguments: [String], in directory: URL = repoRoot, environment: [String: String] = [:]
) -> (status: Int32, output: String, error: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [path] + arguments
    process.currentDirectoryURL = directory
    if !environment.isEmpty {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try! process.run()
    let output = out.fileHandleForReading.readDataToEndOfFile()
    let error = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

private func decide(_ version: String, released: [String]) -> (status: Int32, output: String, error: String) {
    runScript(".github/scripts/release-decision.sh", [version] + released)
}

@Test func aVersionNobodyHasReleasedIsPublishedAndOneAlreadyReleasedNeverIs() {
    #expect(decide("1.1.0", released: ["v1.0.0"]).output == "release")
    #expect(decide("1.1.0", released: []).output == "release")                             // the very first release
    #expect(decide("1.0.1", released: ["v1.0.0"]).output == "release")
    #expect(decide("2.0.0", released: ["v1.0.0", "v1.9.9"]).output == "release")

    // The same version again (another merge into main without raising it): nothing is published, and it is not an error.
    let again = decide("1.1.0", released: ["v1.0.0", "v1.1.0"])
    #expect(again.output == "skip" && again.status == 0)
    #expect(decide("1.1.0", released: ["v1.1.0"]).output == "skip")
    #expect(decide("1.1.0", released: ["1.1.0"]).output == "skip")                         // a tag with or without the "v"
    // An old version that WAS released (the file was put back, say) is also just skipped: no release, and no failure.
    let old = decide("1.0.0", released: ["v1.0.0", "v1.1.0", "v1.2.0"])
    #expect(old.output == "skip" && old.status == 0)
}

@Test func versionsAreComparedAsNumbersWhenDecidingWhatIsNew() {
    #expect(decide("1.10.0", released: ["v1.9.0"]).output == "release")                    // 1.10 comes after 1.9
    #expect(decide("1.9.0", released: ["v1.10.0"]).status != 0)
    #expect(decide("10.0.0", released: ["v9.9.9"]).output == "release")
    #expect(decide("1.2.10", released: ["v1.2.9"]).output == "release")
}

@Test func aVersionLowerThanOneAlreadyReleasedIsRefusedSoTheLatestReleaseNeverGoesBackwards() {
    let result = decide("1.0.5", released: ["v1.0.0", "v1.1.0"])
    #expect(result.status != 0 && result.output.isEmpty)
    #expect(result.error.contains("1.0.5") && result.error.contains("1.1.0") && result.error.contains("lower"))
}

@Test func tagsThatAreNotVersionsAreIgnoredAndAnythingThatIsNotAVersionIsRefused() {
    #expect(decide("1.1.0", released: ["nightly", "junk", "v1.0.0", "v2.0-beta"]).output == "release")
    for bad in ["1.2", "v1.2.3", "1.2.3-beta", "", "latest", "1.2.3.4"] {
        #expect(decide(bad, released: ["v1.0.0"]).status != 0, "\(bad)")
    }
    #expect(runScript(".github/scripts/release-decision.sh", []).status != 0)               // a version is required
}

// MARK: Release notes

private func notes(_ version: String, changelog: String) -> (status: Int32, output: String, error: String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString)", isDirectory: true)
    let scripts = directory.appendingPathComponent(".github/scripts", isDirectory: true)
    try! FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
    try! FileManager.default.copyItem(at: repoRoot.appendingPathComponent(".github/scripts/release-notes.sh"), to: scripts.appendingPathComponent("release-notes.sh"))
    try! changelog.write(to: directory.appendingPathComponent("CHANGELOG.md"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: directory) }
    return runScript(".github/scripts/release-notes.sh", [version], in: directory)
}

private let sampleChangelog = """
# Changelog

## [Unreleased]
- someday

## [1.2.0] - 2026-12-01
- bracketed, with a date

## 1.1.0
- plain heading
- second line

## 1.10.0
- ten

## 1.2.0-beta
- not the same as 1.2.0
"""

@Test func theReleaseNotesAreThatVersionsSectionOfTheChangelogFollowedByTheInstallGuide() {
    let plain = notes("1.1.0", changelog: sampleChangelog)
    #expect(plain.status == 0)
    #expect(plain.output.hasPrefix("- plain heading\n- second line"))
    #expect(!plain.output.contains("bracketed") && !plain.output.contains("ten\n"))          // only its own section
    #expect(plain.output.contains("## Install") && plain.output.contains("Island-1.1.0.dmg"))
    #expect(plain.output.contains("Open Anyway") && plain.output.contains("xattr -dr com.apple.quarantine"))
    #expect(plain.output.contains("Install and restart") && plain.output.contains("Versions before 1.1.0 cannot update themselves"))
}

@Test func theChangelogHeadingMayBeBracketedWithADateAndVersionsAreNotMistakenForOneAnother() {
    #expect(notes("1.2.0", changelog: sampleChangelog).output.hasPrefix("- bracketed, with a date"))
    #expect(notes("1.10.0", changelog: sampleChangelog).output.hasPrefix("- ten"))
    #expect(notes("1.1.0", changelog: sampleChangelog).output.contains("Island-1.1.0.dmg"))
    for missing in ["1.1", "1.1.1", "2.0.0", "1.2.0-beta1"] {                              // "1.1" must not pick up 1.1.0 or 1.10.0
        let result = notes(missing, changelog: sampleChangelog)
        #expect(result.status != 0, "\(missing)")
    }
}

@Test func releasingWithoutNotesFailsWithAnInstructionAndPublishesNothing() {
    let missing = notes("3.0.0", changelog: sampleChangelog)
    #expect(missing.status != 0 && missing.output.isEmpty)
    #expect(missing.error.contains("CHANGELOG.md has no '## 3.0.0' section"))
    let empty = notes("1.1.0", changelog: "# Changelog\n\n## 1.1.0\n\n   \n## 1.0.0\n- old\n")     // a heading with nothing under it
    #expect(empty.status != 0)
}

@Test func theRealChangelogHasNotesForTheVersionInTheVersionFile() throws {
    let versionFile = try String(contentsOf: repoRoot.appendingPathComponent("Sources/IslandCore/Version.swift"), encoding: .utf8)
    let match = try #require(versionFile.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression))
    let version = String(versionFile[match])
    let result = runScript(".github/scripts/release-notes.sh", [version])
    #expect(result.status == 0, "CHANGELOG.md needs a '## \(version)' section: \(result.error)")
}

// MARK: Only a merged pull request into main releases

/// A stand-in for the `gh` command that answers `gh api <path>` from files, so the script can be tried without GitHub.
/// `answers[i]` is what the (i + 1)th question gets (the last one repeats); `fails` makes every question fail.
private func askingTheSource(_ answers: [String], fails: Bool = false, tries: Int = 3) throws
    -> (status: Int32, output: String, error: String, questions: Int)
{
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fake-gh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for (index, answer) in answers.enumerated() {
        try answer.write(to: folder.appendingPathComponent("answer-\(index + 1).json"), atomically: true, encoding: .utf8)
    }
    let log = folder.appendingPathComponent("questions.log")
    let gh = """
    #!/bin/bash
    echo "$@" >> "\(log.path)"
    if [ "\(fails ? 1 : 0)" = "1" ]; then echo "gh: HTTP 500" >&2; exit 1; fi
    n=$(wc -l < "\(log.path)" | tr -d ' ')
    file="\(folder.path)/answer-$n.json"
    [ -f "$file" ] || file="\(folder.path)/answer-\(answers.count).json"
    cat "$file"
    """
    let ghURL = folder.appendingPathComponent("gh")
    try gh.write(to: ghURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghURL.path)

    let result = runScript(
        ".github/scripts/release-source.sh", ["owner/island", "abc123"],
        environment: [
            "PATH": folder.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"),
            "RELEASE_SOURCE_TRIES": String(tries), "RELEASE_SOURCE_WAIT": "0",
        ])
    let questions = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").count
    return (result.status, result.output, result.error, questions)
}

private let none = "[]"
private let mergedIntoMain = #"[{"number":8,"merged_at":null,"base":{"ref":"main"}},{"number":7,"merged_at":"2026-11-10T12:00:00Z","base":{"ref":"main"}}]"#
private let mergedIntoDev = #"[{"number":5,"merged_at":"2026-11-10T12:00:00Z","base":{"ref":"dev"}}]"#
private let stillOpen = #"[{"number":9,"merged_at":null,"base":{"ref":"main"}}]"#

@Test func aCommitThatCameInThroughAMergedPullRequestIntoMainMayRelease() throws {
    let result = try askingTheSource([mergedIntoMain])
    #expect(result.status == 0 && result.output == "pull-request 7")        // the open one (#8) is not the one that was merged
    #expect(result.questions == 1)                                           // found at once: not asked again
}

@Test func aCommitWithNoPullRequestIsADirectPushAndNeverReleasesButIsAskedAboutAFewTimesFirst() throws {
    let result = try askingTheSource([none], tries: 3)
    #expect(result.status == 0 && result.output == "direct-push")
    #expect(result.questions == 3)
}

@Test func aPullRequestThatIsOnlyOpenOrWasMergedIntoAnotherBranchDoesNotCount() throws {
    #expect(try askingTheSource([stillOpen]).output == "direct-push")
    #expect(try askingTheSource([mergedIntoDev]).output == "direct-push")    // dev is not main
}

@Test func aPullRequestGitHubLinksALittleLateIsStillFound() throws {
    let result = try askingTheSource([none, none, mergedIntoMain], tries: 5)
    #expect(result.output == "pull-request 7" && result.questions == 3)
}

@Test func ifGitHubCannotBeAskedTheRunFailsInsteadOfGuessing() throws {
    let result = try askingTheSource([none], fails: true, tries: 2)
    #expect(result.status == 2)
    #expect(result.output.isEmpty, "it must not say direct-push when it does not know")
    #expect(result.error.contains("could not ask GitHub"))
    #expect(result.questions == 2)
}

@Test func theSourceScriptNeedsTheRepositoryAndTheCommit() {
    #expect(runScript(".github/scripts/release-source.sh", []).status == 64)
    #expect(runScript(".github/scripts/release-source.sh", ["owner/island"]).status == 64)
}

@Test func onlyTheReleaseWorkflowCanPublishAndOnlyFromMainAfterAMergedPullRequest() throws {
    let release = try String(contentsOf: repoRoot.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
    let ci = try String(contentsOf: repoRoot.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)

    // It starts on pushes to main only (a merge is one), plus the manual button, which does nothing on any other branch.
    let triggerStart = try #require(release.range(of: "\non:\n"))
    let triggerEnd = try #require(release.range(of: "\npermissions:"))
    let triggers = String(release[triggerStart.upperBound..<triggerEnd.lowerBound])
    #expect(triggers.contains("branches: [main]") && !triggers.contains("dev"))
    #expect(release.contains("if: github.ref == 'refs/heads/main'"))

    // A new version is released only after asking where the change came from, before anything is built or published.
    let asks = try #require(release.range(of: "release-source.sh"))
    let builds = try #require(release.range(of: "scripts/release.sh"))
    let publishes = try #require(release.range(of: "gh release create"))
    #expect(asks.lowerBound < builds.lowerBound && builds.lowerBound < publishes.lowerBound)
    #expect(release.contains("pull-requests: read"))

    // The CI workflow (dev pushes, pull requests) can test and check notes but cannot publish anything.
    #expect(!ci.contains("gh release create") && !ci.contains("gh release edit") && !ci.contains("contents: write"))
}

