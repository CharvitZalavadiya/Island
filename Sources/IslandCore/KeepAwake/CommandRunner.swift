import Foundation

public struct CommandResult: Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs an external command. Keep-awake goes through this so tests can substitute a fake and never touch real power settings.
public protocol CommandRunner {
    func run(_ executable: String, _ args: [String]) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ args: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        // Nothing to read from, so `sudo -n` can never sit waiting for input.
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self))
    }
}
