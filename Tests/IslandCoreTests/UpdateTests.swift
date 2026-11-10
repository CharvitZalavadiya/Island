import CryptoKit
import Foundation
import Testing
@testable import IslandCore

private func version(_ text: String) -> AppVersion { AppVersion(text)! }

@Test func versionsAreComparedNumberByNumberNotLikeText() {
    #expect(version("1.0.0") < version("1.0.1"))
    #expect(version("1.9.0") < version("1.10.0"))             // 10 is more than 9 (as text it would be less)
    #expect(version("1.2.3") < version("2.0.0"))
    #expect(version("0.9.9") < version("1.0.0"))
    #expect(!(version("1.0.0") < version("1.0.0")))
    #expect(version("1.0.1") > version("1.0.0") && version("1.1.0") > version("1.0.9"))
}

@Test func aVersionMayHaveALeadingVAndAMissingPartAndMeansTheSame() {
    #expect(version("v1.2") == version("1.2.0"))
    #expect(version("V1.2.3") == version("1.2.3"))
    #expect(version("1") == version("1.0.0"))
    #expect(version("1.2.3.0") == version("1.2.3"))
    #expect(version("1.2.3.1") > version("1.2.3"))
    #expect(version("1.2").description == "1.2.0" && version("v2.0.1").description == "2.0.1")
    #expect(Set([version("1.2"), version("1.2.0"), version("v1.2.0.0")]).count == 1)       // equal versions hash alike
}

@Test func thingsThatAreNotVersionsAreNotAcceptedSoNothingOddIsEverOffered() {
    for text in ["", "v", "1.2.3-beta", "1.2.3+build5", "latest", "1..2", "1.2.x", ".1", "1.2.3.4.5", "١.٢.٣", "1 2 3", "-1.0.0"] {
        #expect(AppVersion(text) == nil, "\(text)")
    }
}

/// The shape of GitHub's real answer for this repository's v1.0.0 (trimmed to the fields that matter).
private let realRelease = Data("""
{"tag_name":"v1.0.0","name":"v1.0.0","draft":false,"prerelease":false,
 "html_url":"https://github.com/CharvitZalavadiya/Island/releases/tag/v1.0.0","published_at":"2026-11-10T09:19:56Z",
 "body":"## What is new\\n\\n- First release.\\n\\n## Install\\n\\n1. Download the disk image.\\n2. Drag Island to Applications.",
 "assets":[
  {"name":"Island-1.0.0.dmg.sha256","size":83,"content_type":"application/octet-stream","browser_download_url":"https://github.com/CharvitZalavadiya/Island/releases/download/v1.0.0/Island-1.0.0.dmg.sha256"},
  {"name":"Island-1.0.0.dmg","size":6345728,"content_type":"application/x-apple-diskimage","browser_download_url":"https://github.com/CharvitZalavadiya/Island/releases/download/v1.0.0/Island-1.0.0.dmg"}]}
""".utf8)

@Test func aRealReleaseAnswerIsReadWithItsDiskImageAndChecksum() throws {
    let release = try UpdateDecoding.release(from: realRelease)
    #expect(release.version == version("1.0.0") && release.tag == "v1.0.0")
    #expect(release.dmgName == "Island-1.0.0.dmg" && release.dmgSize == 6_345_728)
    #expect(release.dmgURL.absoluteString == "https://github.com/CharvitZalavadiya/Island/releases/download/v1.0.0/Island-1.0.0.dmg")
    #expect(release.checksumURL?.lastPathComponent == "Island-1.0.0.dmg.sha256")     // found although it is listed first
    #expect(release.pageURL.absoluteString == "https://github.com/CharvitZalavadiya/Island/releases/tag/v1.0.0")
    #expect(release.publishedAt != nil)
}

@Test func theReleaseNotesShownInSettingsStopBeforeTheInstallGuide() throws {
    let release = try UpdateDecoding.release(from: realRelease)
    #expect(release.whatsNew == "## What is new\n\n- First release.")
    #expect(!release.whatsNew.contains("Drag Island"))
    #expect(UpdateNotes.whatsNew(from: "Fixes.\n\n### install\nsteps") == "Fixes.")        // any heading level, any capitals
    #expect(UpdateNotes.whatsNew(from: "Just notes, no guide.") == "Just notes, no guide.")
    #expect(UpdateNotes.whatsNew(from: "## Install\nonly the guide") == "")
    #expect(UpdateNotes.whatsNew(from: "- Better installer.\n- Install button fixed.") == "- Better installer.\n- Install button fixed.")   // a word is not a heading
}

private func release(_ json: String) -> Result<UpdateRelease, UpdateError> {
    do { return .success(try UpdateDecoding.release(from: Data(json.utf8))) } catch { return .failure(error as! UpdateError) }
}

@Test func draftsPreReleasesAndOddTagsAreNeverOffered() {
    let base = #""html_url":"https://github.com/o/r/releases/tag/x","assets":[{"name":"Island-9.9.9.dmg","browser_download_url":"https://github.com/o/r/releases/download/x/Island-9.9.9.dmg"}]"#
    for (name, json) in [
        ("draft", #"{"tag_name":"v9.9.9","draft":true,"prerelease":false,\#(base)}"#),
        ("pre-release", #"{"tag_name":"v9.9.9","draft":false,"prerelease":true,\#(base)}"#),
        ("a tag that is not a version", #"{"tag_name":"nightly","draft":false,"prerelease":false,\#(base)}"#),
        ("a beta tag", #"{"tag_name":"v2.0.0-beta.1","draft":false,"prerelease":false,\#(base)}"#),
        ("no tag", #"{"draft":false,"prerelease":false,\#(base)}"#),
        ("not JSON", "<html>rate limited</html>"),
    ] {
        if case .failure(let error) = release(json) { #expect(error == .unreadable, "\(name)") } else { Issue.record("\(name) was accepted") }
    }
}

@Test func aReleaseWithoutADiskImageCannotBeInstalledAndOneWithoutAChecksumIsStillRead() {
    let noDmg = #"{"tag_name":"v2.0.0","html_url":"https://github.com/o/r/releases/tag/v2.0.0","assets":[{"name":"source.zip","browser_download_url":"https://github.com/o/r/a.zip"}]}"#
    if case .failure(let error) = release(noDmg) { #expect(error == .noInstaller) } else { Issue.record("accepted") }
    let noChecksum = #"{"tag_name":"v2.0.0","html_url":"https://github.com/o/r/releases/tag/v2.0.0","assets":[{"name":"Island-2.0.0.dmg","browser_download_url":"https://github.com/o/r/Island-2.0.0.dmg"}]}"#
    if case .success(let found) = release(noChecksum) { #expect(found.checksumURL == nil && found.dmgName == "Island-2.0.0.dmg") } else { Issue.record("rejected") }
}

@Test func islandsOwnDiskImageIsChosenBeforeAnyOtherAndTheChecksumMustBeTheMatchingOne() throws {
    let json = """
    {"tag_name":"v2.0.0","html_url":"https://github.com/o/r/releases/tag/v2.0.0","assets":[
     {"name":"Other-2.0.0.dmg","browser_download_url":"https://github.com/o/r/Other-2.0.0.dmg"},
     {"name":"Other-2.0.0.dmg.sha256","browser_download_url":"https://github.com/o/r/Other-2.0.0.dmg.sha256"},
     {"name":"Island-2.0.0.dmg.sha256","browser_download_url":"https://github.com/o/r/Island-2.0.0.dmg.sha256"},
     {"name":"Island-2.0.0.dmg","browser_download_url":"https://github.com/o/r/Island-2.0.0.dmg"}]}
    """
    let found = try UpdateDecoding.release(from: Data(json.utf8))
    #expect(found.dmgName == "Island-2.0.0.dmg" && found.checksumURL?.lastPathComponent == "Island-2.0.0.dmg.sha256")
}

@Test func aChecksumFileIsReadWhetherItHasAFileNameOrNot() {
    let hash = String(repeating: "ab", count: 32)
    #expect(ChecksumFile.parse("\(hash)  Island-1.0.0.dmg\n") == hash)
    #expect(ChecksumFile.parse(hash) == hash)
    #expect(ChecksumFile.parse("  \(hash.uppercased())  x") == hash)                  // lowercase, whatever was written
    for bad in ["", "   ", "not-a-hash x", String(repeating: "g", count: 64), String(repeating: "a", count: 63), String(repeating: "a", count: 65)] {
        #expect(ChecksumFile.parse(bad) == nil, "\(bad)")
    }
}

@Test func aFilesChecksumIsTheStandardSHA256() throws {
    let url = makeTempDirectory().appendingPathComponent("abc.txt")
    try Data("abc".utf8).write(to: url)
    #expect(try FileChecksum.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")   // the standard test vector
    let empty = makeTempDirectory().appendingPathComponent("empty")
    try Data().write(to: empty)
    #expect(try FileChecksum.sha256(of: empty) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(throws: (any Error).self) { try FileChecksum.sha256(of: makeTempDirectory().appendingPathComponent("missing")) }
}

@Test func aBigFileIsChecksummedInPiecesAndGivesTheSameAnswerAsAllAtOnce() throws {
    let url = makeTempDirectory().appendingPathComponent("big.bin")
    let data = Data((0..<(3 * (1 << 20) + 12345)).map { UInt8($0 % 251) })            // more than three pieces, not a round size
    try data.write(to: url)
    let expected = Data(SHA256Reference.hash(data)).map { String(format: "%02x", $0) }.joined()
    #expect(try FileChecksum.sha256(of: url) == expected)
}

@Test func theSettingsHaveUpdateChecksOnByDefaultAndOldFilesStillRead() throws {
    #expect(Settings().checkForUpdates && Settings().lastUpdateCheck == nil)
    let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"focusMinutes":50,"launchAtLogin":true}"#.utf8))
    #expect(old.focusMinutes == 50 && old.launchAtLogin && old.checkForUpdates && old.lastUpdateCheck == nil)
    var changed = Settings()
    changed.checkForUpdates = false
    changed.lastUpdateCheck = Date(timeIntervalSince1970: 1_800_000_000)
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(changed))
    #expect(!back.checkForUpdates && back.lastUpdateCheck == changed.lastUpdateCheck)
}

@Test func theUpdateSwitchesAreRecognisedAndOnlyWhenAsked() {
    #expect(LaunchOptions().updateFeedURL == nil && !LaunchOptions().debugUpdateNow)
    let options = LaunchOptions.parse(["Island", "--update-feed", "http://127.0.0.1:8080/latest", "--debug-update-now"])
    #expect(options.updateFeedURL?.absoluteString == "http://127.0.0.1:8080/latest" && options.debugUpdateNow)
    #expect(LaunchOptions.parse(["Island", "--update-feed"]).updateFeedURL == nil)             // an address is needed
    #expect(LaunchOptions.parse(["Island", "--update-feed", "--debug-update-now"]).updateFeedURL == nil)
}

@Test func theUpdateScriptNamesItsArgumentsAndOpensTheAppWithOrWithoutArguments() {
    let script = UpdateScript.text(waitSeconds: 5, openCommand: "/usr/bin/open")
    #expect(script.hasPrefix("#!/bin/bash"))
    #expect(script.contains("seq 1 50"))                                                 // 5 seconds in tenths
    #expect(script.contains(#"mv "$APP" "$BACKUP""#) && script.contains(#"mv "$NEW" "$APP""#))
    #expect(script.contains("/usr/bin/open -n \"$APP\" --args \"$@\"") && script.contains("/usr/bin/open \"$APP\""))
    #expect(UpdateScript.text(waitSeconds: 0).contains("seq 1 10"))                      // always waits at least a second
}

/// Reference SHA-256 through another route (CryptoKit's one-shot hash), to compare the streaming one against.
private enum SHA256Reference {
    static func hash(_ data: Data) -> [UInt8] { Array(SHA256.hash(data: data)) }
}

@Test func releaseNotesBecomePlainTextForTheSettingsWindow() {
    let markdown = "## What's new\n\n- **Updates** from inside Island.\n* Faster `tabs`.\n\n\n\n### Fixed\n- A crash."
    #expect(UpdateNotes.plainText(from: markdown) == "What's new\n\n• Updates from inside Island.\n• Faster tabs.\n\nFixed\n• A crash.")
    #expect(UpdateNotes.plainText(from: "") == "" && UpdateNotes.plainText(from: "\n\n") == "")
    #expect(UpdateNotes.plainText(from: "Plain words.") == "Plain words.")
    #expect(UpdateNotes.plainText(from: "a - b and *c* stay") == "a - b and *c* stay")             // only a line that STARTS as a list item is changed
}
