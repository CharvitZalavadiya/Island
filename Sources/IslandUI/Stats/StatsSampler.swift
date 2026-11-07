import Foundation
import Darwin
import Observation
import IslandCore

/// Live CPU, memory, network and disk readings. It samples once a second, but only between `start()` and `stop()`,
/// which the Stats tab calls while it is on screen, so a collapsed island costs nothing.
///
/// Tapping CPU or Memory opens a dropdown of the apps using the most of it (both can be open together). That needs the
/// process list, which is read with `ps` every couple of seconds, and only while a dropdown is open.
@Observable
@MainActor
final class StatsSampler {
    private(set) var cpuPercent: Double = 0
    private(set) var memoryUsedBytes: UInt64 = 0
    private(set) var memoryTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    private(set) var upBytesPerSec: Double = 0
    private(set) var downBytesPerSec: Double = 0
    /// Room left on the disk that holds the home folder; nil until the first reading.
    private(set) var disk: DiskSpace?

    /// The dropdowns that are open.
    private(set) var expanded: Set<Metric> = []
    /// True once a reading of the process list has come back since a dropdown opened.
    private(set) var appsLoaded = false
    private var apps: [AppUsage] = []
    /// The state of the network speed test (the button next to the download and upload speeds).
    private(set) var speedTest: SpeedTestState = .idle

    static let topAppCount = 5
    /// `ps` reports CPU as a share of one core; dividing by this gives each app's share of the whole Mac.
    let coreCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)

    /// The apps for the dropdown of `metric`, biggest first. Empty while that dropdown is closed.
    func topApps(for metric: Metric) -> [AppUsage] {
        guard expanded.contains(metric) else { return [] }
        return ProcessUsage.top(apps, by: metric, limit: Self.topAppCount)
    }

    /// An app's share of the whole CPU, in percent.
    func cpuShare(of app: AppUsage) -> Double { app.cpuPercent / Double(coreCount) }

    @ObservationIgnored private let processList: @Sendable () -> String
    @ObservationIgnored private let processInterval: TimeInterval
    @ObservationIgnored private let speedTestRunner: SpeedTestRunning
    @ObservationIgnored private var speedTestTask: Task<Void, Never>?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previousTicks: CPUTicks?
    @ObservationIgnored private var previousNet: NetCounters?
    @ObservationIgnored private var previousTime: TimeInterval?
    @ObservationIgnored private var inbound = InterfaceByteAccumulator()
    @ObservationIgnored private var outbound = InterfaceByteAccumulator()

    /// `processList` returns the output of `ps -axo pid=,pcpu=,rss=,comm=`; tests pass a stand-in.
    init(
        processList: @escaping @Sendable () -> String = { StatsSampler.systemProcessList() },
        processInterval: TimeInterval = 2,
        speedTestRunner: SpeedTestRunning = SystemSpeedTest()
    ) {
        self.processList = processList
        self.processInterval = processInterval
        self.speedTestRunner = speedTestRunner
    }

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        closeDropdowns()
        cancelSpeedTest()
        timer?.invalidate()
        timer = nil
        // Forget the baselines so the next start does not compute a rate across the time it was stopped.
        previousTicks = nil
        previousNet = nil
        previousTime = nil
    }

    /// Opens the dropdown for `metric`, or closes it if it is open. The other one is left as it is.
    func toggle(_ metric: Metric) {
        if expanded.contains(metric) {
            expanded.remove(metric)
            if expanded.isEmpty { closeDropdowns() }
        } else {
            expanded.insert(metric)
            startReadingProcesses()
        }
    }

    // MARK: Speed test

    /// Runs macOS's `networkQuality` (about twenty seconds). Does nothing while one is already running.
    func startSpeedTest() {
        guard speedTest != .running else { return }
        speedTest = .running
        let runner = speedTestRunner
        speedTestTask = Task { [weak self] in
            let outcome = await runner.run()
            guard !Task.isCancelled, let self else { return }
            self.speedTest = outcome
            self.speedTestTask = nil
        }
    }

    /// Closes the result bar under the network row (a finished or failed test). A running test is left alone.
    func dismissSpeedTest() {
        switch speedTest {
        case .finished, .failed: speedTest = .idle
        case .idle, .running: break
        }
    }

    /// Ends a test that is running (leaving the tab does this); a finished result is kept.
    func cancelSpeedTest() {
        guard speedTest == .running else { return }
        speedTestTask?.cancel()
        speedTestTask = nil
        speedTest = .idle
    }

    /// Takes one reading. Rates and CPU need two readings, so they appear from the second one on.
    func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        disk = DiskSpace.read(at: FileManager.default.homeDirectoryForCurrentUser)

        if let ticks = Self.readCPUTicks() {
            if let previous = previousTicks { cpuPercent = StatsMath.cpuPercent(previous: previous, current: ticks) }
            previousTicks = ticks
        }

        if let used = Self.readMemoryUsed() { memoryUsedBytes = used }

        let readings = Self.readInterfaceBytes()
        inbound.add(readings.mapValues { $0.received })
        outbound.add(readings.mapValues { $0.sent })
        let counters = NetCounters(bytesIn: inbound.total, bytesOut: outbound.total)
        if let previous = previousNet, let before = previousTime {
            let rate = StatsMath.networkRate(previous: previous, current: counters, interval: now - before)
            downBytesPerSec = rate.down
            upBytesPerSec = rate.up
        }
        previousNet = counters
        previousTime = now
    }

    // MARK: The process list

    private func closeDropdowns() {
        expanded = []
        processTask?.cancel()
        processTask = nil
        apps = []
        appsLoaded = false
    }

    /// Reads the process list now and then every `processInterval`, off the main thread, until the dropdown closes.
    /// Switching from one dropdown to the other keeps the same loop and re-ranks what it already has.
    private func startReadingProcesses() {
        guard processTask == nil else { return }
        let read = processList
        let interval = processInterval
        processTask = Task { [weak self] in
            while !Task.isCancelled {
                let output = await Task.detached(priority: .utility) { read() }.value
                // A reading that finishes after the dropdown was closed is thrown away.
                guard !Task.isCancelled, let self else { return }
                self.apps = ProcessUsage.aggregate(ProcessUsage.parse(psOutput: output))
                self.appsLoaded = true
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    nonisolated static func systemProcessList() -> String {
        (try? ProcessCommandRunner().run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="]))?.stdout ?? ""
    }

    // MARK: Reading the system

    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // The tuple order is user, system, idle, nice.
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    /// App memory plus wired plus compressed, which is what Activity Monitor calls "Memory Used".
    private static func readMemoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let appPages = max(Int64(stats.internal_page_count) - Int64(stats.purgeable_count), 0)
        let pages = appPages + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        return UInt64(pages) * UInt64(getpagesize())
    }

    /// Bytes received and sent per Wi-Fi or Ethernet interface (`en*`).
    private static func readInterfaceBytes() -> [String: (received: UInt32, sent: UInt32)] {
        var readings: [String: (received: UInt32, sent: UInt32)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return readings }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en"),
                let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                let data = entry.pointee.ifa_data
            else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            readings[name] = (counters.ifi_ibytes, counters.ifi_obytes)
        }
        return readings
    }
}
