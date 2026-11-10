import Foundation
import Testing

// The scripts the release workflow runs, tried here so that "only a new version is released" cannot quietly break.

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@discardableResult
private func runScript(_ path: String, _ arguments: [String], in directory: URL = repoRoot) -> (status: Int32, output: String, error: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [path] + arguments
    process.currentDirectoryURL = directory
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
