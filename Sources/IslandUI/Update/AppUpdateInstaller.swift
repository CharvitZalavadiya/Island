import Foundation
import IslandCore

/// An update that has been downloaded, checked and put next to the installed app, ready to be swapped in.
struct PreparedUpdate: Equatable, Sendable {
    var version: AppVersion
    var installedApp: URL
    /// The new app, beside the installed one (on the same disk, so moving it into place is instant and cannot half-finish).
    var newApp: URL
    var backupApp: URL
    var workDirectory: URL
}

/// What the controller needs from an installer; tests use a stand-in.
protocol UpdateInstalling: Sendable {
    func prepare(_ release: UpdateRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> PreparedUpdate
    func relaunch(_ prepared: PreparedUpdate, processID: Int32, extraArguments: [String]) throws
    func discard(_ prepared: PreparedUpdate)
}

/// Downloads a release's disk image, makes sure it is the right one, and swaps it in for the running app.
///
/// What is checked before anything of the old app is touched: the download matches the checksum published with the release;
/// the app inside is Island (same bundle identifier), is the version the release says and newer than this one, has the code for
/// this kind of Mac, and its signature is intact. The swap itself is done by a small script after Island has quit, which puts
/// the old app back if the new one cannot be moved in.
final class AppUpdateInstaller: UpdateInstalling, @unchecked Sendable {
    let installedApp: URL
    private let session: URLSession
    private let currentVersion: AppVersion
    private let bundleIdentifier: String
    private let workDirectory: URL
    /// Only a test (or the `--update-feed` switch) may download from somewhere other than GitHub.
    private let allowAnyHost: Bool
    private let openCommand: String
    private let waitSeconds: Int

    init(
        session: URLSession = URLSession(configuration: .ephemeral), installedApp: URL = Bundle.main.bundleURL,
        currentVersion: AppVersion, bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.charvit.Island",
        workDirectory: URL? = nil, allowAnyHost: Bool = false, openCommand: String = "open", waitSeconds: Int = 30
    ) {
        self.session = session
        self.installedApp = installedApp
        self.currentVersion = currentVersion
        self.bundleIdentifier = bundleIdentifier
        self.allowAnyHost = allowAnyHost
        self.openCommand = openCommand
        self.waitSeconds = waitSeconds
        self.workDirectory = workDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(bundleIdentifier, isDirectory: true).appendingPathComponent("Updates", isDirectory: true)
    }

    // MARK: Preparing

    func prepare(_ release: UpdateRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> PreparedUpdate {
        try checkInstallLocation()
        try checkAddress(release.dmgURL)
        guard let checksumURL = release.checksumURL else { throw UpdateError.noChecksum }
        try checkAddress(checksumURL)
        guard release.version > currentVersion else { throw UpdateError.notAUsableUpdate("it is not newer than the version you have") }

        let fileManager = FileManager.default
        let folder = workDirectory.appendingPathComponent(release.version.description, isDirectory: true)
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // 1. Download, and check against the checksum published with the release.
        let dmg = folder.appendingPathComponent(release.dmgName)
        try await Downloader.download(release.dmgURL, to: dmg, configuration: session.configuration, progress: progress)
        let expected = try await publishedChecksum(at: checksumURL)
        guard try FileChecksum.sha256(of: dmg) == expected else {
            try? fileManager.removeItem(at: folder)
            throw UpdateError.checksumMismatch
        }

        // 2. Open the disk image, copy the app out next to the installed one, close it again.
        let mountPoint = folder.appendingPathComponent("mount", isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attached = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mountPoint.path])
        guard attached.status == 0 else { throw UpdateError.installFailed("the disk image would not open (\(attached.output.trimmingCharacters(in: .whitespacesAndNewlines)))") }
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let source = mountPoint.appendingPathComponent("Island.app")
        guard fileManager.fileExists(atPath: source.path) else { throw UpdateError.notAUsableUpdate("the disk image has no Island.app") }
        let parent = installedApp.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".Island-update-\(release.version).app")
        try? fileManager.removeItem(at: staged)
        let copied = try run("/usr/bin/ditto", [source.path, staged.path])
        guard copied.status == 0 else {
            try? fileManager.removeItem(at: staged)
            throw UpdateError.installFailed("the new version could not be copied next to the old one")
        }

        // 3. Make sure what was copied is really a usable Island, before the old one is touched.
        do { try verify(staged, expecting: release.version) } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
        _ = try? run("/usr/bin/xattr", ["-cr", staged.path])

        return PreparedUpdate(
            version: release.version, installedApp: installedApp, newApp: staged,
            backupApp: parent.appendingPathComponent(".Island-previous.app"), workDirectory: folder)
    }

    private func checkInstallLocation() throws {
        let fileManager = FileManager.default
        let path = installedApp.path
        if path.contains("/AppTranslocation/") {
            throw UpdateError.cannotReplaceHere("Island is running from a temporary place (macOS does that to apps opened straight from Downloads or a disk image). Drag Island into your Applications folder, open it from there, and update again.")
        }
        let parent = installedApp.deletingLastPathComponent().path
        guard fileManager.isWritableFile(atPath: parent), fileManager.isWritableFile(atPath: path) else {
            throw UpdateError.cannotReplaceHere("Island can't replace itself in \(parent). Download the new version from the release page and drag it over the old one.")
        }
    }

    /// Downloads only come from GitHub (over https), unless this is a test or `--update-feed` is in use.
    private func checkAddress(_ url: URL) throws {
        guard !allowAnyHost else { return }
        guard Self.isTrustedDownload(url) else { throw UpdateError.badAddress(url.host ?? url.absoluteString) }
    }

    /// An https address on GitHub itself or on its download servers (github.com, *.github.com, *.githubusercontent.com).
    static func isTrustedDownload(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    private func publishedChecksum(at url: URL) async throws -> String {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(from: url) } catch { throw UpdateError.network(error.localizedDescription) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8), let hash = ChecksumFile.parse(text) else {
            throw UpdateError.noChecksum
        }
        return hash
    }

    private func verify(_ app: URL, expecting version: AppVersion) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw UpdateError.notAUsableUpdate("it has no readable Info.plist") }
        guard plist["CFBundleIdentifier"] as? String == bundleIdentifier else { throw UpdateError.notAUsableUpdate("it is not Island") }
        guard let text = plist["CFBundleShortVersionString"] as? String, let found = AppVersion(text), found == version else {
            throw UpdateError.notAUsableUpdate("it says it is version \(plist["CFBundleShortVersionString"] as? String ?? "?"), not \(version)")
        }
        guard found > currentVersion else { throw UpdateError.notAUsableUpdate("it is not newer than the version you have") }
        let executableName = plist["CFBundleExecutable"] as? String ?? "Island"
        let executable = app.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw UpdateError.notAUsableUpdate("its program is missing") }

        // The code has to include this Mac's kind of processor, or the new Island would not start at all.
        var system = utsname()
        uname(&system)
        let machine = withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) } }
        let archs = try run("/usr/bin/lipo", ["-archs", executable.path])
        guard archs.status == 0, archs.output.split(whereSeparator: \.isWhitespace).contains(Substring(machine)) else {
            throw UpdateError.notAUsableUpdate("it does not include code for this Mac (\(machine))")
        }
        let signature = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard signature.status == 0 else { throw UpdateError.notAUsableUpdate("its signature is damaged") }
    }

    // MARK: Swapping

    func relaunch(_ prepared: PreparedUpdate, processID: Int32, extraArguments: [String] = []) throws {
        let fileManager = FileManager.default
        let script = prepared.workDirectory.appendingPathComponent("finish-update.sh")
        try UpdateScript.text(waitSeconds: waitSeconds, openCommand: openCommand).write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let logURL = prepared.workDirectory.appendingPathComponent("update.log")
        fileManager.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")   // the script must outlive the app that starts it
        process.arguments = ["/bin/bash", script.path, "\(processID)", prepared.installedApp.path, prepared.newApp.path, prepared.backupApp.path] + extraArguments
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw UpdateError.installFailed("the installer could not be started") }
    }

    /// Throws away a prepared update that will not be used (the person cancelled, or something failed after preparing).
    func discard(_ prepared: PreparedUpdate) {
        try? FileManager.default.removeItem(at: prepared.newApp)
        try? FileManager.default.removeItem(at: prepared.workDirectory)
    }

    // MARK: Helpers

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { throw UpdateError.installFailed("\((tool as NSString).lastPathComponent) could not run") }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()   // read before waiting, or a chatty tool would fill the pipe and hang
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}

/// A download with progress, to a file.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    private init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func download(_ url: URL, to destination: URL, configuration: URLSessionConfiguration, progress: @escaping @Sendable (Double) -> Void) async throws {
        let downloader = Downloader(destination: destination, progress: progress)
        let session = URLSession(configuration: configuration, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            finish(.failure(UpdateError.network("the download answered with an error")))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)   // the temporary file is gone after this method returns
            finish(.success(()))
        } catch {
            finish(.failure(UpdateError.installFailed("the download could not be saved")))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(UpdateError.network(error.localizedDescription))) }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        continuation?.resume(with: result)
        continuation = nil
    }
}
