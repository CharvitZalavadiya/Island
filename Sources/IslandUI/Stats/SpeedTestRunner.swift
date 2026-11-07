import Foundation
import IslandCore

enum SpeedTestState: Equatable {
    case idle, running
    case finished(SpeedTestResult)
    case failed(String)
}

/// Runs the speed test. The real one is `SystemSpeedTest`; tests use a fake.
protocol SpeedTestRunning: Sendable {
    func run() async -> SpeedTestState
}

/// Runs the `networkQuality` tool that ships with macOS and reads its JSON. Cancelling the task stops the tool.
final class SystemSpeedTest: SpeedTestRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func run() async -> SpeedTestState {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async { continuation.resume(returning: self.runBlocking()) }
            }
        } onCancel: {
            lock.withLock {
                cancelled = true
                process?.terminate()
            }
        }
    }

    private func runBlocking() -> SpeedTestState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        // -c: machine-readable output; -M: give up after 30 seconds whatever happens.
        process.arguments = ["-c", "-M", "30"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        let alreadyCancelled = lock.withLock { () -> Bool in
            if cancelled { return true }
            self.process = process
            return false
        }
        guard !alreadyCancelled else { return .idle }
        do { try process.run() } catch { return .failed("The speed test could not start.") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if let result = SpeedTestResult.parse(json: data) { return .finished(result) }
        return .failed("The speed test did not finish. Check that you are online.")
    }
}
