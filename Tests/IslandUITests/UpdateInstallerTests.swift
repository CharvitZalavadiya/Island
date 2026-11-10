import Foundation
import Network
import Testing
import IslandCore
@testable import IslandUI

// These run the real thing: real disk images, real code signatures, the real swap script, and a small web server on this Mac's
// loopback standing in for GitHub. They share a few system tools (hdiutil), so they run one at a time.

// MARK: Building a pretend Island

private func tempFolder(_ name: String = "update") -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-\(name)-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try! process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// This Mac's kind of processor, and the other kind.
private let thisMac: String = { var s = utsname(); uname(&s); return withUnsafePointer(to: &s.machine) { $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) } } }()
private let otherMac = thisMac == "arm64" ? "x86_64" : "arm64"

/// A tiny app bundle that looks like Island: an Info.plist, a real program (for the kinds of processor asked for), signed ad-hoc.
@discardableResult
private func makeApp(
    in folder: URL, version: String, bundleID: String = "com.charvit.Island", archs: [String]? = nil, sign: Bool = true
) throws -> URL {
    let app = folder.appendingPathComponent("Island.app", isDirectory: true)
    let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundleVersion": "1",
        "CFBundleExecutable": "Island", "CFBundlePackageType": "APPL", "CFBundleName": "Island",
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    let source = folder.appendingPathComponent("main-\(UUID().uuidString).c")
    try "int main(void) { return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
    let kinds = archs ?? ["arm64", "x86_64"]
    let build = run("/usr/bin/clang", kinds.flatMap { ["-arch", $0] } + ["-o", macOS.appendingPathComponent("Island").path, source.path])
    precondition(build.status == 0, "could not build the stand-in program: \(build.output)")
    try? FileManager.default.removeItem(at: source)
    if sign { precondition(run("/usr/bin/codesign", ["--force", "--sign", "-", app.path]).status == 0) }
    return app
}

/// A disk image holding `app` (and nothing else but a README), like the real one.
private func makeDMG(containing app: URL?, named name: String, in folder: URL) throws -> URL {
    let stage = folder.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    if let app { try FileManager.default.copyItem(at: app, to: stage.appendingPathComponent("Island.app")) }   // (a plain copy keeps the signature)
    try "read me".write(to: stage.appendingPathComponent("READ ME FIRST.txt"), atomically: true, encoding: .utf8)
    let dmg = folder.appendingPathComponent(name)
    let made = run("/usr/bin/hdiutil", ["create", "-srcfolder", stage.path, "-volname", "Island", "-format", "UDZO", "-ov", dmg.path])
    precondition(made.status == 0, "could not make a disk image: \(made.output)")
    return dmg
}

private func installedVersion(_ app: URL) -> String? {
    guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return plist["CFBundleShortVersionString"] as? String
}

// MARK: A web server that stands in for GitHub

private final class FileServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "island.test.updates")
    private var listener: NWListener?
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var served: [String] = []

    func add(_ path: String, _ data: Data) { lock.lock(); files[path] = data; lock.unlock() }
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return served }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        final class Once: @unchecked Sendable { var done = false }
        let once = Once()
        return try await withCheckedThrowingContinuation { (started: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                if case .ready = state { once.done = true; started.resume(returning: listener.port?.rawValue ?? 0) }
                if case .failed(let error) = state { once.done = true; started.resume(throwing: error) }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener?.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { connection.cancel(); return }
            let path = text.components(separatedBy: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            self.lock.lock(); self.served.append(path); let body = self.files[path]; self.lock.unlock()
            let status = body == nil ? "404 Not Found" : "200 OK"
            let bytes = body ?? Data("not found".utf8)
            let head = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

/// Everything one scenario needs: an installed old Island in a pretend Applications folder, a release on the server, an installer.
private struct Scene {
    let root: URL
    let applications: URL
    let installed: URL
    let server: FileServer
    let port: UInt16
    let release: UpdateRelease
    let installer: AppUpdateInstaller

    /// - Parameters:
    ///   - newApp: how the pretend new version is built (default: a good Island 9.9.9)
    ///   - checksum: what the server says the checksum is (default: the real one)
    ///   - dmgFromApp: whether the disk image holds an app at all
    static func make(
        installedVersion: String = "1.0.0", releaseVersion: String = "9.9.9", appVersion: String? = nil, bundleID: String = "com.charvit.Island",
        archs: [String]? = nil, includeApp: Bool = true, tamperSignature: Bool = false, wrongChecksum: Bool = false, omitChecksum: Bool = false,
        allowAnyHost: Bool = true, installedParent: String = "Applications"
    ) async throws -> Scene {
        _ = installedVersion
        let root = tempFolder()
        let applications = root.appendingPathComponent(installedParent, isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let installed = try makeApp(in: applications, version: installedVersion)

        let building = root.appendingPathComponent("building", isDirectory: true)
        try FileManager.default.createDirectory(at: building, withIntermediateDirectories: true)
        let newApp: URL? = includeApp ? try makeApp(in: building, version: appVersion ?? releaseVersion, bundleID: bundleID, archs: archs) : nil
        if tamperSignature, let newApp {
            let resources = newApp.appendingPathComponent("Contents/Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try Data("changed after signing".utf8).write(to: resources.appendingPathComponent("extra.txt"))   // a new file the signature never saw
        }
        let dmg = try makeDMG(containing: newApp, named: "Island-\(releaseVersion).dmg", in: building)
        let realHash = try FileChecksum.sha256(of: dmg)

        let server = FileServer()
        let port = try await server.start()
        server.add("/Island-\(releaseVersion).dmg", try Data(contentsOf: dmg))
        let shown = wrongChecksum ? String(repeating: "0", count: 64) : realHash
        server.add("/Island-\(releaseVersion).dmg.sha256", Data("\(shown)  Island-\(releaseVersion).dmg\n".utf8))

        let release = UpdateRelease(
            version: AppVersion(releaseVersion)!, tag: "v\(releaseVersion)", notes: "notes", pageURL: URL(string: "https://github.com/o/r/releases/tag/v\(releaseVersion)")!,
            dmgName: "Island-\(releaseVersion).dmg", dmgURL: URL(string: "http://127.0.0.1:\(port)/Island-\(releaseVersion).dmg")!,
            checksumURL: omitChecksum ? nil : URL(string: "http://127.0.0.1:\(port)/Island-\(releaseVersion).dmg.sha256")!)
        let installer = AppUpdateInstaller(
            installedApp: installed, currentVersion: AppVersion(installedVersion)!, workDirectory: root.appendingPathComponent("work", isDirectory: true),
            allowAnyHost: allowAnyHost, openCommand: "/bin/echo", waitSeconds: 10)
        return Scene(root: root, applications: applications, installed: installed, server: server, port: port, release: release, installer: installer)
    }

    func cleanUp() {
        server.stop()
        run("/bin/chmod", ["-R", "u+w", root.path])
        try? FileManager.default.removeItem(at: root)
    }

    var stagedApps: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: applications.path)) ?? []).filter { $0.hasPrefix(".Island-update-") }
    }
}

private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
    var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

private func eventually(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
}

private func failure(_ work: () async throws -> Void) async -> UpdateError? {
    do { try await work(); return nil } catch { return error as? UpdateError }
}

// MARK: Tests

@Suite(.serialized) struct UpdateInstallerTests {
    @Test func aGoodUpdateIsDownloadedCheckedStagedAndSwappedInAfterIslandQuitsThenOpened() async throws {
        let scene = try await Scene.make()
        defer { scene.cleanUp() }
        let progress = Progress()

        let prepared = try await scene.installer.prepare(scene.release) { progress.add($0) }
        #expect(installedVersion(prepared.newApp) == "9.9.9")                        // the new app is waiting next to the old one...
        #expect(prepared.newApp.deletingLastPathComponent() == scene.applications)   // ...on the same disk, so the swap is a rename
        #expect(installedVersion(scene.installed) == "1.0.0")                        // and the old one has not been touched
        #expect(progress.all.last == 1 && progress.all == progress.all.sorted())     // progress only ever went forward, to 100%
        #expect(scene.server.requests.contains("/Island-9.9.9.dmg") && scene.server.requests.contains("/Island-9.9.9.dmg.sha256"))
        #expect(run("/usr/bin/codesign", ["--verify", "--deep", "--strict", prepared.newApp.path]).status == 0)
        #expect(run("/bin/sh", ["-c", "mount | grep -c '\(prepared.workDirectory.path)/mount' || true"]).output.trimmingCharacters(in: .whitespacesAndNewlines) == "0")   // the disk image was closed again

        // Island is "running" (a stand-in process); the swap only happens once it has quit.
        let island = Process()
        island.executableURL = URL(fileURLWithPath: "/bin/sleep")
        island.arguments = ["300"]
        try island.run()
        try scene.installer.relaunch(prepared, processID: island.processIdentifier, extraArguments: ["--support-dir", "/tmp/island-x"])
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(installedVersion(scene.installed) == "1.0.0")                        // still waiting for Island to quit

        island.terminate()
        island.waitUntilExit()
        #expect(await eventually { installedVersion(scene.installed) == "9.9.9" })    // now the new one is in the old one's place
        let log = prepared.workDirectory.appendingPathComponent("update.log")
        // (The script says "opening Island" just before the opening command writes its own line, so wait for that line itself.)
        let opened = "\(scene.installed.path) --args --support-dir /tmp/island-x"            // opened again, the way it was started (echo stands in for `open -n`)
        #expect(await eventually { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").contains(opened) })
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(text.contains("the new version is in place") && text.contains("opening Island"))
        #expect(scene.stagedApps.isEmpty)                                            // nothing left behind...
        #expect(!FileManager.default.fileExists(atPath: prepared.backupApp.path))    // ...not even the old copy
        #expect(run("/usr/bin/codesign", ["--verify", "--deep", "--strict", scene.installed.path]).status == 0)
    }

    @Test func aDownloadThatDoesNotMatchItsChecksumIsThrownAwayAndNothingIsTouched() async throws {
        let scene = try await Scene.make(wrongChecksum: true)
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        #expect(error == .checksumMismatch)
        #expect(installedVersion(scene.installed) == "1.0.0" && scene.stagedApps.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: scene.root.appendingPathComponent("work/9.9.9").path))    // the download itself was deleted
    }

    @Test func aReleaseWithoutAChecksumIsRefusedBeforeAnythingIsDownloaded() async throws {
        let scene = try await Scene.make(omitChecksum: true)
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        #expect(error == .noChecksum)
        #expect(!scene.server.requests.contains("/Island-9.9.9.dmg"))                // not even asked for
    }

    @Test func aDiskImageThatHoldsSomeOtherAppIsRefused() async throws {
        let scene = try await Scene.make(bundleID: "com.example.NotIsland")
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        #expect(error == .notAUsableUpdate("it is not Island"))
        #expect(installedVersion(scene.installed) == "1.0.0" && scene.stagedApps.isEmpty)
    }

    @Test func anAppThatSaysItIsAnotherVersionThanTheReleaseIsRefused() async throws {
        let scene = try await Scene.make(releaseVersion: "9.9.9", appVersion: "9.9.8")
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        if case .notAUsableUpdate(let why)? = error { #expect(why.contains("9.9.8")) } else { Issue.record("accepted: \(String(describing: error))") }
        #expect(scene.stagedApps.isEmpty)
    }

    @Test func aVersionThatIsNotNewerThanTheRunningOneIsRefused() async throws {
        let scene = try await Scene.make(installedVersion: "9.9.9", releaseVersion: "9.9.9")
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        if case .notAUsableUpdate? = error {} else { Issue.record("accepted: \(String(describing: error))") }
        #expect(!scene.server.requests.contains("/Island-9.9.9.dmg"))                // refused before downloading
    }

    @Test func aDiskImageWithNoAppInItIsRefused() async throws {
        let scene = try await Scene.make(includeApp: false)
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        #expect(error == .notAUsableUpdate("the disk image has no Island.app"))
        #expect(scene.stagedApps.isEmpty)
    }

    @Test func anAppWhoseSignatureIsDamagedIsRefused() async throws {
        let scene = try await Scene.make(tamperSignature: true)
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        #expect(error == .notAUsableUpdate("its signature is damaged"))
        #expect(installedVersion(scene.installed) == "1.0.0" && scene.stagedApps.isEmpty)
    }

    @Test func anAppWithoutCodeForThisKindOfMacIsRefusedSoIslandNeverFailsToStartAfterAnUpdate() async throws {
        let scene = try await Scene.make(archs: [otherMac])
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        if case .notAUsableUpdate(let why)? = error { #expect(why.contains(thisMac)) } else { Issue.record("accepted: \(String(describing: error))") }
        #expect(installedVersion(scene.installed) == "1.0.0" && scene.stagedApps.isEmpty)
    }

    @Test func downloadsOnlyComeFromGitHubOverHttpsUnlessTestingOrUsingTheFeedSwitch() async throws {
        let scene = try await Scene.make(allowAnyHost: false)
        defer { scene.cleanUp() }
        let error = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }     // the address is http://127.0.0.1
        #expect(error == .badAddress("127.0.0.1"))
        #expect(scene.server.requests.isEmpty)                                       // never contacted

        func trusted(_ text: String) -> Bool { AppUpdateInstaller.isTrustedDownload(URL(string: text)!) }
        #expect(trusted("https://github.com/CharvitZalavadiya/Island/releases/download/v1.0.0/Island-1.0.0.dmg"))
        #expect(trusted("https://objects.githubusercontent.com/github-production-release-asset/x"))
        #expect(trusted("https://release-assets.githubusercontent.com/x") && trusted("https://api.github.com/x"))
        for bad in ["http://github.com/x", "https://github.com.evil.example/x", "https://evilgithub.com/x", "https://evil.example/github.com", "https://githubusercontent.com.evil.example/x", "ftp://github.com/x", "https://example.com/Island.dmg"] {
            #expect(!trusted(bad), "\(bad)")
        }
    }

    @Test func anAppThatCannotReplaceItselfWhereItIsSaysSoBeforeDownloadingAnything() async throws {
        // In a folder it cannot write to (a read-only place).
        let locked = try await Scene.make()
        defer { locked.cleanUp() }
        run("/bin/chmod", ["555", locked.applications.path])
        let readOnly = await failure { _ = try await locked.installer.prepare(locked.release) { _ in } }
        if case .cannotReplaceHere(let why)? = readOnly { #expect(why.contains(locked.applications.path)) } else { Issue.record("accepted: \(String(describing: readOnly))") }
        #expect(!locked.server.requests.contains("/Island-9.9.9.dmg"))

        // Running from a place macOS made up when an app is opened straight from Downloads.
        let scene = try await Scene.make(installedParent: "AppTranslocation/ABC/d")
        defer { scene.cleanUp() }
        let translocated = await failure { _ = try await scene.installer.prepare(scene.release) { _ in } }
        if case .cannotReplaceHere(let why)? = translocated { #expect(why.contains("Applications")) } else { Issue.record("accepted: \(String(describing: translocated))") }
    }

    @Test func ifTheNewAppCannotBeMovedInTheOldOneIsPutBackAndIslandStillOpens() async throws {
        let scene = try await Scene.make()
        defer { scene.cleanUp() }
        let work = scene.root.appendingPathComponent("work/broken", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        // A prepared update whose new app has vanished, so the second move fails.
        let prepared = PreparedUpdate(
            version: AppVersion("9.9.9")!, installedApp: scene.installed, newApp: scene.applications.appendingPathComponent(".Island-update-gone.app"),
            backupApp: scene.applications.appendingPathComponent(".Island-previous.app"), workDirectory: work)
        let island = Process()
        island.executableURL = URL(fileURLWithPath: "/bin/sleep")
        island.arguments = ["300"]
        try island.run()
        try scene.installer.relaunch(prepared, processID: island.processIdentifier)
        island.terminate()
        island.waitUntilExit()
        let log = work.appendingPathComponent("update.log")
        #expect(await eventually { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").contains("opening Island") })
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(text.contains("putting the old one back"))
        #expect(installedVersion(scene.installed) == "1.0.0")                         // the old Island is back where it was
        #expect(!FileManager.default.fileExists(atPath: prepared.backupApp.path))
    }

    @Test func ifIslandNeverQuitsNothingIsChangedAndTheStagedAppIsRemoved() async throws {
        let scene = try await Scene.make()
        defer { scene.cleanUp() }
        let prepared = try await scene.installer.prepare(scene.release) { _ in }
        let island = Process()
        island.executableURL = URL(fileURLWithPath: "/bin/sleep")
        island.arguments = ["300"]
        try island.run()
        defer { island.terminate() }
        let impatient = AppUpdateInstaller(installedApp: scene.installed, currentVersion: AppVersion("1.0.0")!, workDirectory: scene.root.appendingPathComponent("work"), allowAnyHost: true, openCommand: "/bin/echo", waitSeconds: 1)
        try impatient.relaunch(prepared, processID: island.processIdentifier)
        let log = prepared.workDirectory.appendingPathComponent("update.log")
        #expect(await eventually(timeout: 30) { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").contains("did not quit") })
        #expect(installedVersion(scene.installed) == "1.0.0")
        #expect(await eventually { scene.stagedApps.isEmpty })
    }

    @Test func aPreparedUpdateThatWillNotBeUsedCanBeDiscarded() async throws {
        let scene = try await Scene.make()
        defer { scene.cleanUp() }
        let prepared = try await scene.installer.prepare(scene.release) { _ in }
        #expect(!scene.stagedApps.isEmpty)
        scene.installer.discard(prepared)
        #expect(scene.stagedApps.isEmpty && !FileManager.default.fileExists(atPath: prepared.workDirectory.path))
        #expect(installedVersion(scene.installed) == "1.0.0")
    }
}
