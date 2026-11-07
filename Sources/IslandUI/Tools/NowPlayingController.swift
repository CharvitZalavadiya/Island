import AppKit
import Observation
import IslandCore

/// Something that reports what is playing and can press the player's keys. The real one asks macOS through a helper;
/// tests use a stand-in.
@MainActor
protocol NowPlayingBackend: AnyObject {
    /// Starts reporting. `onReading` and `onEnd` may be called from any thread. Returns nil (with a reason) when the
    /// reports cannot be started.
    func startReporting(
        onReading: @escaping @Sendable (NowPlayingReading) -> Void, onEnd: @escaping @Sendable () -> Void
    ) -> Result<NowPlayingReporting, NowPlayingBackendError>
    func send(_ command: NowPlayingCommand)
    /// Moves the playing position to `seconds`.
    func seek(to seconds: TimeInterval)
}

@MainActor
protocol NowPlayingReporting: AnyObject {
    func stop()
}

struct NowPlayingBackendError: Error, Equatable {
    var message: String
}

/// The player on the Tools tab: what is playing, and the play/pause, next and previous keys.
///
/// It only listens while the Tools tab is on screen. Everything it knows comes from the system's Now Playing, so it
/// follows whatever app is playing (Music, Spotify, a video in the browser) without Island knowing about any of them.
@Observable
@MainActor
final class NowPlayingController {
    enum Status: Equatable {
        case stopped
        /// Asked, no answer yet.
        case starting
        case running
        case unavailable(String)
    }

    /// Why the helper is wanted. It runs while there is at least one reason, and not otherwise.
    enum Reason: Hashable {
        /// The Tools tab is on screen.
        case player
        /// The minimal view shows what is playing.
        case minimalView
    }

    private(set) var status: Status = .stopped
    private(set) var track: NowPlayingTrack?

    @ObservationIgnored private let backend: NowPlayingBackend
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var reporting: NowPlayingReporting?
    @ObservationIgnored private var reasons: Set<Reason> = []
    /// Bumped on every start so a late answer from an earlier start is ignored.
    @ObservationIgnored private var generation = 0
    /// Until this time a report that still shows the old position is not allowed to pull the bar back after a seek.
    @ObservationIgnored private var holdPositionUntil = Date.distantPast

    init(backend: NowPlayingBackend? = nil, now: @escaping () -> Date = Date.init) {
        self.backend = backend ?? HelperNowPlayingBackend()
        self.now = now
    }

    var isAvailable: Bool {
        if case .unavailable = status { return false }
        return true
    }

    /// What the app playing is called ("Brave Browser"), when the system says which app it is.
    var sourceName: String? {
        track?.processID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
    }

    var sourceIcon: NSImage? {
        track?.processID.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
    }

    func start(for reason: Reason = .player) {
        reasons.insert(reason)
        guard reporting == nil else { return }
        generation += 1
        let current = generation
        status = .starting
        let result = backend.startReporting(
            onReading: { [weak self] reading in
                Task { @MainActor in self?.receive(reading, generation: current) }
            },
            onEnd: { [weak self] in
                Task { @MainActor in self?.ended(generation: current) }
            })
        switch result {
        case .success(let handle): reporting = handle
        case .failure(let error): status = .unavailable(error.message)
        }
    }

    func stop(for reason: Reason = .player) {
        reasons.remove(reason)
        guard reasons.isEmpty else { return }   // someone else still wants it
        generation += 1   // anything still on its way is now out of date
        reporting?.stop()
        reporting = nil
        if isAvailable { status = .stopped }   // an "unavailable" notice stays until the next try
    }

    func send(_ command: NowPlayingCommand) {
        backend.send(command)
        // Show the new state at once; the next report (within a second) confirms it.
        if command == .togglePlayPause, let track { self.track = track.toggled(at: now()) }
    }

    /// Moves to `seconds` (clicking or dragging on the progress bar). Does nothing when the app doesn't allow it.
    func seek(to seconds: TimeInterval) {
        guard let track, track.isSeekable else { return }
        let target = min(max(seconds, 0), track.duration ?? seconds)
        backend.seek(to: target)
        // Show it at once; reports in the next moment may still carry the old position, so they are held back briefly.
        self.track = track.seeked(to: target, at: now())
        holdPositionUntil = now().addingTimeInterval(1.5)
    }

    /// Jumps forward or back by `seconds`, from where the track is now.
    func skip(by seconds: TimeInterval) {
        guard let track else { return }
        seek(to: track.elapsed(at: now()) + seconds)
    }

    private func receive(_ reading: NowPlayingReading, generation: Int) {
        guard generation == self.generation, reporting != nil else { return }
        switch reading {
        case .nothing:
            track = nil
            status = .running
        case .track(var value):
            if now() < holdPositionUntil, let current = track, current.title == value.title {
                value.elapsed = current.elapsed
                value.timestamp = current.timestamp
            }
            track = value
            status = .running
        case .unsupported:
            track = nil
            status = .unavailable("This version of macOS doesn't share what's playing with Island.")
        }
    }

    private func ended(generation: Int) {
        guard generation == self.generation, reporting != nil else { return }
        reporting = nil
        track = nil
        status = .unavailable("Island lost contact with the helper that reads what's playing. Reopen the tab to try again.")
    }
}

// MARK: - The real backend

/// Reads Now Playing through a small library (Packaging/NowPlayingAdapter.m, built into the app by build-app.sh) that is
/// loaded into /usr/bin/perl. macOS only answers the Now Playing questions for Apple's own programs, and perl is one.
@MainActor
final class HelperNowPlayingBackend: NowPlayingBackend {
    private let library: URL?

    init(library: URL? = Bundle.main.url(forResource: "NowPlayingAdapter", withExtension: "dylib")) {
        self.library = library
    }

    // What perl runs: load the library and call one of its two functions.
    private static let script = """
        use DynaLoader;
        my ($path, $symbol) = @ARGV;
        my $lib = DynaLoader::dl_load_file($path, 0) or die "cannot load $path\\n";
        my $address = DynaLoader::dl_find_symbol($lib, $symbol) or die "no $symbol\\n";
        &{DynaLoader::dl_install_xsub("main::entry", $address)};
        """

    func startReporting(
        onReading: @escaping @Sendable (NowPlayingReading) -> Void, onEnd: @escaping @Sendable () -> Void
    ) -> Result<NowPlayingReporting, NowPlayingBackendError> {
        guard let library else {
            return .failure(NowPlayingBackendError(
                message: "The helper that reads what's playing is missing. Build the app with scripts/build-app.sh."))
        }
        let stream = HelperStream(onReading: onReading, onEnd: onEnd)
        let process = makeProcess(library: library, symbol: "adapter_stream", environment: [:])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        stream.attach(process: process, pipe: pipe)
        do { try process.run() } catch {
            return .failure(NowPlayingBackendError(message: "Island couldn't start the helper that reads what's playing."))
        }
        return .success(stream)
    }

    func send(_ command: NowPlayingCommand) {
        run(symbol: "adapter_send", environment: ["ISLAND_MR_COMMAND": String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        run(symbol: "adapter_seek", environment: ["ISLAND_MR_SEEK": String(format: "%.2f", seconds)])
    }

    private func run(symbol: String, environment: [String: String]) {
        guard let library else { return }
        let process = makeProcess(library: library, symbol: symbol, environment: environment)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func makeProcess(library: URL, symbol: String, environment: [String: String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.script, library.path, symbol]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        return process
    }
}

/// The running helper: splits what it prints into lines and hands each one on.
@MainActor
private final class HelperStream: NowPlayingReporting {
    private let onReading: @Sendable (NowPlayingReading) -> Void
    private let onEnd: @Sendable () -> Void
    private var process: Process?
    private var pipe: Pipe?
    private var stopped = false

    init(onReading: @escaping @Sendable (NowPlayingReading) -> Void, onEnd: @escaping @Sendable () -> Void) {
        self.onReading = onReading
        self.onEnd = onEnd
    }

    func attach(process: Process, pipe: Pipe) {
        self.process = process
        self.pipe = pipe
        let reading = onReading
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            for line in buffer.append(data) {
                if let parsed = NowPlayingParser.parse(line) { reading(parsed) }
            }
        }
        let end = onEnd
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                end()
            }
        }
    }

    func stop() {
        stopped = true
        pipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        pipe = nil
    }
}

/// Collects bytes and gives back the complete lines.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
