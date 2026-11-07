import Foundation
import Darwin

/// Reports new screenshots that appear in a folder.
///
/// macOS marks a real screenshot with the extended attribute `kMDItemIsScreenCapture`, sometimes a moment after the file
/// appears, so a new file is re-checked a few times before it is written off as something else. Files that were already in
/// the folder when watching started, and hidden temporary files, are ignored. Everything runs on the watcher's own queue,
/// and `onNewScreenshot` is called there.
final class ScreenshotWatcher: @unchecked Sendable {
    private let folder: URL
    private let onNewScreenshot: (URL) -> Void
    private let isScreenshot: (URL) -> Bool
    private let queue = DispatchQueue(label: "dev.island.screenshot-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var attempts: [String: Int] = [:]
    private var scanScheduled = false

    private static let maxAttempts = 8

    init(
        folder: URL,
        onNewScreenshot: @escaping (URL) -> Void,
        isScreenshot: @escaping (URL) -> Bool = ScreenshotWatcher.hasScreenCaptureMarker
    ) {
        self.folder = folder
        self.onNewScreenshot = onNewScreenshot
        self.isScreenshot = isScreenshot
    }

    func start() {
        queue.async { [self] in
            guard source == nil else { return }
            known = Set(visibleNames())
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else { return }  // no access to the folder: nothing to watch
            let newSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: .write, queue: queue)
            newSource.setEventHandler { [weak self] in self?.scheduleScan(after: 0.3) }
            newSource.setCancelHandler { close(descriptor) }
            source = newSource
            newSource.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            source?.cancel()
            source = nil
        }
    }

    static func hasScreenCaptureMarker(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    // MARK: Internals (all on `queue`)

    private func scheduleScan(after delay: TimeInterval) {
        guard !scanScheduled else { return }
        scanScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            scanScheduled = false
            scan()
        }
    }

    private func scan() {
        let names = visibleNames()
        let current = Set(names)
        known.formIntersection(current)
        attempts = attempts.filter { current.contains($0.key) }

        for name in names where !known.contains(name) {
            let url = folder.appendingPathComponent(name)
            if isScreenshot(url) {
                known.insert(name)
                attempts[name] = nil
                onNewScreenshot(url)
            } else {
                let tries = (attempts[name] ?? 0) + 1
                if tries >= Self.maxAttempts {
                    known.insert(name)
                    attempts[name] = nil
                } else {
                    attempts[name] = tries
                }
            }
        }
        if !attempts.isEmpty { scheduleScan(after: 0.25) }
    }

    private func visibleNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
    }
}
