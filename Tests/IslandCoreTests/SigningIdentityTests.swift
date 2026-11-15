import Foundation
import Testing

// Which certificate a local build is signed with. macOS keeps the permissions the person gave the app (calendar, camera,
// folders) only for builds signed by the same identity, so the choice must not flip between builds.

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let personal = "E1DD388E790C96B269FED9C72E63AC8C9A1C4367"
private let work = "A1B6B5AA7638C85FC07BE44CF01FA3E4518B9D92"
private let other = "0123456789ABCDEF0123456789ABCDEF01234567"

private func listing(_ identities: [(hash: String, name: String)]) -> String {
    var text = "  Policy: Code Signing\n  Matching identities\n"
    for (index, identity) in identities.enumerated() { text += "  \(index + 1)) \(identity.hash) \"\(identity.name)\"\n" }
    return text + "     \(identities.count) valid identities found\n"
}

private let personalIdentity = (hash: personal, name: "Apple Development: Someone One (AAAAAAAAAA)")
private let workIdentity = (hash: work, name: "Apple Development: someone@example.com (BBBBBBBBBB)")

/// Runs the script with `input` on its standard input and a pin file in a fresh folder (or the given one).
private func choose(
    from input: String, pin: String? = nil, in folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("island-sign-\(UUID().uuidString)")
) -> (chosen: String, pinned: String, warnings: String, folder: URL) {
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pinFile = folder.appendingPathComponent("pin")
    if let pin { try! pin.write(to: pinFile, atomically: true, encoding: .utf8) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["scripts/signing-identity.sh", pinFile.path]
    process.currentDirectoryURL = repoRoot
    let stdin = Pipe(), out = Pipe(), err = Pipe()
    process.standardInput = stdin
    process.standardOutput = out
    process.standardError = err
    try! process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try! stdin.fileHandleForWriting.close()
    let chosen = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let warnings = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    let pinned = (try? String(contentsOf: pinFile, encoding: .utf8)) ?? ""
    return (chosen.trimmingCharacters(in: .whitespacesAndNewlines), pinned.trimmingCharacters(in: .whitespacesAndNewlines),
        warnings.trimmingCharacters(in: .whitespacesAndNewlines), folder)
}

@Test func withNothingRememberedTheFirstAppleDevelopmentIdentityIsUsedAndRemembered() {
    let result = choose(from: listing([personalIdentity, workIdentity]))
    #expect(result.chosen == "\(personal)\t\(personalIdentity.name)")
    #expect(result.pinned == result.chosen)                        // remembered for the next build
    #expect(result.warnings.isEmpty)                               // the very first time is not a change
}

@Test func theRememberedIdentityWinsEvenWhenAnotherIsListedFirst() {
    // The keychain listing can come in another order one day; the build must keep signing with the same certificate.
    let result = choose(from: listing([workIdentity, personalIdentity]), pin: "\(personal)\t\(personalIdentity.name)")
    #expect(result.chosen == "\(personal)\t\(personalIdentity.name)")
    #expect(result.warnings.isEmpty)
}

@Test func theRememberedHashMatchesInAnyLetterCase() {
    let result = choose(from: listing([workIdentity, personalIdentity]), pin: "\(personal.lowercased())\t\(personalIdentity.name)")
    #expect(result.chosen.hasPrefix(personal))
}

@Test func whenTheRememberedIdentityIsGoneTheFirstOneIsUsedAndTheChangeIsSaidOutLoud() {
    let result = choose(from: listing([workIdentity]), pin: "\(personal)\t\(personalIdentity.name)")
    #expect(result.chosen == "\(work)\t\(workIdentity.name)")
    #expect(result.pinned == result.chosen)
    #expect(result.warnings.contains("changed") && result.warnings.contains("ask for the permissions again"))
    #expect(result.warnings.contains(personalIdentity.name) && result.warnings.contains(workIdentity.name))
}

@Test func onlyAppleDevelopmentIdentitiesAreConsidered() {
    let input = listing([(other, "Developer ID Application: Someone (CCCCCCCCCC)"), (other, "Mac Developer: Someone (DDDDDDDDDD)"), workIdentity])
    #expect(choose(from: input).chosen == "\(work)\t\(workIdentity.name)")
    #expect(choose(from: listing([(other, "Developer ID Application: Someone (CCCCCCCCCC)")])).chosen.isEmpty)
}

@Test func noIdentityMeansNothingIsChosenAndNothingIsRemembered() {
    let result = choose(from: listing([]))
    #expect(result.chosen.isEmpty && result.pinned.isEmpty && result.warnings.isEmpty)
    #expect(choose(from: "").chosen.isEmpty)
}

@Test func ifTheOnlyIdentityYouUsedBeforeDisappearsItIsSaidAndTheMemoryIsKept() {
    let result = choose(from: listing([]), pin: "\(personal)\t\(personalIdentity.name)")
    #expect(result.chosen.isEmpty)
    #expect(result.warnings.contains("no longer available") && result.warnings.contains(personalIdentity.name))
    #expect(result.pinned == "\(personal)\t\(personalIdentity.name)")          // so it is recognised when the certificate comes back
}

@Test func theSameIdentityTwiceSaysNothing() {
    let first = choose(from: listing([personalIdentity, workIdentity]))
    let second = choose(from: listing([workIdentity, personalIdentity]), pin: first.pinned, in: first.folder)
    #expect(second.chosen == first.chosen && second.warnings.isEmpty)
}

@Test func namesWithBracketsAtSignsAndSpacesComeThroughWhole() {
    let name = "Apple Development: first.last+tag@example.co.in (A1B2C3D4E5)"
    #expect(choose(from: listing([(personal, name)])).chosen == "\(personal)\t\(name)")
}

@Test func linesThatAreNotIdentitiesAreIgnored() {
    let noise = "Policy: Code Signing\n     0 valid identities found\n  CSSMERR_TP_CERT_EXPIRED\n  9) not-a-hash \"Apple Development: Fake\"\n"
    #expect(choose(from: noise).chosen.isEmpty)
}

// MARK: The build script uses it

@Test func theBuildScriptSignsWithTheRememberedIdentityByItsHashAndNotWithWhicheverIsFirst() throws {
    let script = try String(contentsOf: repoRoot.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
    #expect(script.contains("scripts/signing-identity.sh build/.signing-identity"))
    #expect(!script.contains("| head -1)\""))                                       // the old "take the first one" line is gone
    #expect(script.contains("ID=\"${CHOSEN%%$'\\t'*}\""))                              // signs by hash
    #expect(script.contains("note_other_copies"))                                   // and says when another copy is signed differently
    // The identity is picked before anything is signed.
    let picked = try #require(script.range(of: "signing-identity.sh")).lowerBound
    let signed = try #require(script.range(of: "codesign \"${SIGN[@]}\"")).lowerBound
    #expect(picked < signed)
}

@Test func theRememberedIdentityFileStaysOutOfGit() throws {
    let ignore = try String(contentsOf: repoRoot.appendingPathComponent(".gitignore"), encoding: .utf8)
    #expect(ignore.split(separator: "\n").contains("build/"))                       // build/.signing-identity lives in build/
}
