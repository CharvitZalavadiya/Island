import Testing
import Foundation
import IslandCore
@testable import IslandUI

/// These read the real machine, so they only check that the numbers are sensible.
@Test @MainActor func realReadingsAreWithinSensibleBounds() async throws {
    let sampler = StatsSampler()
    sampler.sample()
    try await Task.sleep(nanoseconds: 300_000_000)
    sampler.sample()

    #expect(sampler.cpuPercent >= 0 && sampler.cpuPercent <= 100)
    #expect(sampler.memoryTotalBytes == ProcessInfo.processInfo.physicalMemory)
    #expect(sampler.memoryUsedBytes > 0)
    #expect(sampler.memoryUsedBytes <= sampler.memoryTotalBytes)
    #expect(sampler.upBytesPerSec >= 0)
    #expect(sampler.downBytesPerSec >= 0)
}

@Test @MainActor func theMemoryReadingIsInTheRangeOfARealMac() {
    let sampler = StatsSampler()
    sampler.sample()
    let gigabytes = Double(sampler.memoryUsedBytes) / 1_073_741_824
    // More than a few hundred MB and less than the whole RAM is the only thing that can be asserted anywhere.
    #expect(gigabytes > 0.3)
}

@Test @MainActor func stoppingBeforeStartingIsHarmless() {
    let sampler = StatsSampler()
    sampler.stop()
    sampler.start()
    sampler.stop()
    sampler.stop()
}

// MARK: Disk space

@Test @MainActor func diskSpaceIsReadOnEachSample() throws {
    let sampler = StatsSampler()
    #expect(sampler.disk == nil)
    sampler.sample()
    let disk = try #require(sampler.disk)
    #expect(disk.totalBytes > 0 && disk.availableBytes <= disk.totalBytes)
}

// MARK: The top-apps dropdown

/// A stand-in for `ps` that counts how often it is asked.
private final class FakePS: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var output: String

    init(output: String) { self.output = output }

    var calls: Int { lock.withLock { count } }

    func run() -> String {
        lock.withLock { count += 1 }
        return output
    }
}

private let fakeOutput = """
    1  50.0  1024 /Applications/Busy.app/Contents/MacOS/Busy
    2   5.0 90000 /Applications/Hungry.app/Contents/MacOS/Hungry
    3   1.0  2048 /usr/libexec/quiet
    """

@MainActor
private func waitUntil(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

@Test @MainActor func bothDropdownsCanBeOpenAtOnceAndEachClosesByItself() {
    let sampler = StatsSampler(processList: { "" })
    #expect(sampler.expanded.isEmpty)
    sampler.toggle(.cpu)
    #expect(sampler.expanded == [.cpu])
    sampler.toggle(.memory)
    #expect(sampler.expanded == [.cpu, .memory])
    sampler.toggle(.memory)
    #expect(sampler.expanded == [.cpu])
    sampler.toggle(.cpu)
    #expect(sampler.expanded.isEmpty)
    sampler.stop()
}

@Test @MainActor func stoppingClosesTheDropdown() {
    let sampler = StatsSampler(processList: { "" })
    sampler.toggle(.cpu)
    sampler.stop()
    #expect(sampler.expanded.isEmpty)
    #expect(sampler.topApps(for: .cpu).isEmpty)
}

@Test @MainActor func openingTheDropdownListsTheTopAppsForThatMetric() async {
    let fake = FakePS(output: fakeOutput)
    let sampler = StatsSampler(processList: { fake.run() }, processInterval: 0.05)
    #expect(sampler.topApps(for: .cpu).isEmpty)
    sampler.toggle(.cpu)
    #expect(await waitUntil { !sampler.topApps(for: .cpu).isEmpty })
    #expect(sampler.topApps(for: .cpu).map(\.name) == ["Busy", "Hungry", "quiet"])

    // Opening Memory too ranks the apps already read, without waiting for another reading; CPU stays open.
    sampler.toggle(.memory)
    #expect(sampler.topApps(for: .memory).map(\.name) == ["Hungry", "quiet", "Busy"])
    #expect(sampler.topApps(for: .cpu).map(\.name) == ["Busy", "Hungry", "quiet"])
    sampler.stop()
}

@Test @MainActor func theListIsCappedAtFiveApps() async {
    let many = (1...9).map { "\($0) \(Double($0)) 100 /usr/bin/tool\($0)" }.joined(separator: "\n")
    let fake = FakePS(output: many)
    let sampler = StatsSampler(processList: { fake.run() }, processInterval: 0.05)
    sampler.toggle(.cpu)
    #expect(await waitUntil { sampler.topApps(for: .cpu).count == 5 })
    #expect(sampler.topApps(for: .cpu).map(\.name) == ["tool9", "tool8", "tool7", "tool6", "tool5"])
    sampler.stop()
}

@Test @MainActor func theListRefreshesWhileTheDropdownIsOpen() async {
    let fake = FakePS(output: fakeOutput)
    let sampler = StatsSampler(processList: { fake.run() }, processInterval: 0.05)
    sampler.toggle(.cpu)
    #expect(await waitUntil { fake.calls >= 2 })
    fake.output = "9 99.0 1 /usr/bin/newcomer"
    #expect(await waitUntil { sampler.topApps(for: .cpu).first?.name == "newcomer" })
    sampler.stop()
}

@Test @MainActor func closingTheDropdownStopsAskingForProcesses() async throws {
    let fake = FakePS(output: fakeOutput)
    let sampler = StatsSampler(processList: { fake.run() }, processInterval: 0.05)
    sampler.toggle(.cpu)
    #expect(await waitUntil { fake.calls >= 2 })
    sampler.toggle(.cpu)
    #expect(sampler.expanded.isEmpty)
    try await Task.sleep(nanoseconds: 100_000_000)   // let an in-flight reading finish
    let settled = fake.calls
    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(fake.calls == settled)
    #expect(sampler.topApps(for: .cpu).isEmpty)
}

@Test @MainActor func stoppingTheSamplerStopsAskingForProcessesToo() async throws {
    let fake = FakePS(output: fakeOutput)
    let sampler = StatsSampler(processList: { fake.run() }, processInterval: 0.05)
    sampler.toggle(.memory)
    #expect(await waitUntil { fake.calls >= 1 })
    sampler.stop()
    try await Task.sleep(nanoseconds: 100_000_000)
    let settled = fake.calls
    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(fake.calls == settled)
}

@Test @MainActor func switchingMetricsDoesNotStartASecondReadingLoop() async throws {
    let fake = FakePS(output: fakeOutput)
    let sampler = StatsSampler(processList: { fake.run() }, processInterval: 0.2)
    sampler.toggle(.cpu)
    #expect(await waitUntil { fake.calls >= 1 })
    sampler.toggle(.memory)
    sampler.toggle(.cpu)
    sampler.toggle(.memory)
    let before = fake.calls
    try await Task.sleep(nanoseconds: 1_000_000_000)
    // One loop at 0.2 s gives about 5 readings a second; two loops would give about 10.
    #expect(fake.calls - before <= 7)
    sampler.stop()
}

@Test @MainActor func aFailedReadingIsReportedAsNotLoaded() async {
    let sampler = StatsSampler(processList: { "" }, processInterval: 0.05)
    #expect(!sampler.appsLoaded)
    sampler.toggle(.cpu)
    #expect(await waitUntil { sampler.appsLoaded })
    #expect(sampler.topApps(for: .cpu).isEmpty)
    sampler.stop()
    #expect(!sampler.appsLoaded)
}
