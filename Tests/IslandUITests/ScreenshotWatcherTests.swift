import Testing
import Foundation
import Darwin
@testable import IslandUI

private let markerName = "com.apple.metadata:kMDItemIsScreenCapture"

/// Receives callbacks from the watcher's own queue.
private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var names: [String] { lock.lock(); defer { lock.unlock() }; return urls.map(\.lastPathComponent) }
}

private func makeFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("island-watch-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Marks a file the way macOS marks a real screenshot.
private func markAsScreenshot(_ url: URL) {
    let value: [UInt8] = [1]
    #expect(setxattr(url.path, markerName, value, value.count, 0, 0) == 0)
}

private func startWatcher(on folder: URL, into received: Received) -> ScreenshotWatcher {
    let watcher = ScreenshotWatcher(folder: folder) { received.add($0) }
    watcher.start()
    return watcher
}

/// Waits up to `seconds` for `condition`, without blocking the main thread.
private func wait(upTo seconds: Double, until condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline, !condition() {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
}

@Test func aNewScreenshotIsReported() async throws {
    let folder = makeFolder()
    let received = Received()
    let watcher = startWatcher(on: folder, into: received)
    defer { watcher.stop() }
    try await Task.sleep(nanoseconds: 300_000_000)

    let shot = folder.appendingPathComponent("Screenshot 2026-10-31 at 10.00.00.png")
    try Data([0]).write(to: shot)
    markAsScreenshot(shot)

    await wait(upTo: 5) { !received.names.isEmpty }
    #expect(received.names == ["Screenshot 2026-10-31 at 10.00.00.png"])
}

@Test func aFileThatWasAlreadyThereWhenWatchingStartedIsIgnored() async throws {
    let folder = makeFolder()
    let old = folder.appendingPathComponent("Screenshot old.png")
    try Data([0]).write(to: old)
    markAsScreenshot(old)

    let received = Received()
    let watcher = startWatcher(on: folder, into: received)
    defer { watcher.stop() }
    try await Task.sleep(nanoseconds: 300_000_000)

    let fresh = folder.appendingPathComponent("Screenshot new.png")
    try Data([0]).write(to: fresh)
    markAsScreenshot(fresh)

    await wait(upTo: 5) { !received.names.isEmpty }
    #expect(received.names == ["Screenshot new.png"])
}

@Test func anOrdinaryNewFileIsNotReported() async throws {
    let folder = makeFolder()
    let received = Received()
    let watcher = startWatcher(on: folder, into: received)
    defer { watcher.stop() }
    try await Task.sleep(nanoseconds: 300_000_000)

    try Data([0]).write(to: folder.appendingPathComponent("notes.txt"))
    try await Task.sleep(nanoseconds: 3_000_000_000)
    #expect(received.names.isEmpty)
}

@Test func aScreenshotThatGetsItsMarkerALittleLaterIsStillReported() async throws {
    let folder = makeFolder()
    let received = Received()
    let watcher = startWatcher(on: folder, into: received)
    defer { watcher.stop() }
    try await Task.sleep(nanoseconds: 300_000_000)

    let shot = folder.appendingPathComponent("Screenshot late.png")
    try Data([0]).write(to: shot)
    try await Task.sleep(nanoseconds: 700_000_000)
    markAsScreenshot(shot)

    await wait(upTo: 5) { !received.names.isEmpty }
    #expect(received.names == ["Screenshot late.png"])
}

@Test func aHiddenTemporaryFileIsReportedOnlyOnceItIsRenamedToItsRealName() async throws {
    let folder = makeFolder()
    let received = Received()
    let watcher = startWatcher(on: folder, into: received)
    defer { watcher.stop() }
    try await Task.sleep(nanoseconds: 300_000_000)

    let temporary = folder.appendingPathComponent(".Screenshot tmp.png")
    try Data([0]).write(to: temporary)
    markAsScreenshot(temporary)
    try await Task.sleep(nanoseconds: 800_000_000)
    #expect(received.names.isEmpty)

    try FileManager.default.moveItem(at: temporary, to: folder.appendingPathComponent("Screenshot final.png"))
    await wait(upTo: 5) { !received.names.isEmpty }
    #expect(received.names == ["Screenshot final.png"])
}

@Test func aScreenshotIsReportedOnlyOnce() async throws {
    let folder = makeFolder()
    let received = Received()
    let watcher = startWatcher(on: folder, into: received)
    defer { watcher.stop() }
    try await Task.sleep(nanoseconds: 300_000_000)

    let shot = folder.appendingPathComponent("Screenshot once.png")
    try Data([0]).write(to: shot)
    markAsScreenshot(shot)
    await wait(upTo: 5) { !received.names.isEmpty }
    // Unrelated activity in the folder must not report it again.
    try Data([0]).write(to: folder.appendingPathComponent("other.txt"))
    try await Task.sleep(nanoseconds: 1_500_000_000)
    #expect(received.names == ["Screenshot once.png"])
}
