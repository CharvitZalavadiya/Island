import Testing
import Foundation
@testable import IslandCore

private let zeroTicks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)

@Test func cpuPercentIsBusyOverTotal() {
    let current = CPUTicks(user: 30, system: 10, idle: 60, nice: 0)
    #expect(StatsMath.cpuPercent(previous: zeroTicks, current: current) == 40.0)
}

@Test func niceTimeCountsAsBusy() {
    let current = CPUTicks(user: 0, system: 0, idle: 50, nice: 50)
    #expect(StatsMath.cpuPercent(previous: zeroTicks, current: current) == 50.0)
}

@Test func onlyTheChangeBetweenTwoSamplesCounts() {
    let previous = CPUTicks(user: 1_000, system: 500, idle: 8_500, nice: 0)
    let current = CPUTicks(user: 1_080, system: 520, idle: 8_600, nice: 0)  // +80, +20, +100
    #expect(StatsMath.cpuPercent(previous: previous, current: current) == 50.0)
}

@Test func aZeroChangeIsZeroPercent() {
    let ticks = CPUTicks(user: 5, system: 5, idle: 5, nice: 5)
    #expect(StatsMath.cpuPercent(previous: ticks, current: ticks) == 0)
}

@Test func decreasingCountersGiveZeroNotNonsense() {
    let previous = CPUTicks(user: 100, system: 100, idle: 100, nice: 100)
    let current = CPUTicks(user: 50, system: 150, idle: 150, nice: 100)
    #expect(StatsMath.cpuPercent(previous: previous, current: current) == 0)
}

@Test func networkRateIsBytesPerSecond() {
    let previous = NetCounters(bytesIn: 1_000, bytesOut: 500)
    let current = NetCounters(bytesIn: 3_000, bytesOut: 1_500)
    let rate = StatsMath.networkRate(previous: previous, current: current, interval: 2)
    #expect(rate.down == 1_000)
    #expect(rate.up == 500)
}

@Test func aCounterResetGivesZeroNotANegativeRate() {
    let previous = NetCounters(bytesIn: 9_000, bytesOut: 9_000)
    let current = NetCounters(bytesIn: 100, bytesOut: 12_000)
    let rate = StatsMath.networkRate(previous: previous, current: current, interval: 1)
    #expect(rate.down == 0)
    #expect(rate.up == 3_000)
}

@Test func aZeroOrNegativeIntervalGivesZero() {
    let previous = NetCounters(bytesIn: 0, bytesOut: 0)
    let current = NetCounters(bytesIn: 1_000, bytesOut: 1_000)
    #expect(StatsMath.networkRate(previous: previous, current: current, interval: 0).down == 0)
    #expect(StatsMath.networkRate(previous: previous, current: current, interval: -1).up == 0)
}

// MARK: Wrapping 32-bit interface counters

@Test func theFirstReadingOfAnInterfaceIsOnlyABaseline() {
    var accumulator = InterfaceByteAccumulator()
    accumulator.add(["en0": 123_456])
    #expect(accumulator.total == 0)
}

@Test func laterReadingsAddTheirDifference() {
    var accumulator = InterfaceByteAccumulator()
    accumulator.add(["en0": 1_000])
    accumulator.add(["en0": 4_000])
    #expect(accumulator.total == 3_000)
}

@Test func aThirtyTwoBitWrapIsCountedCorrectly() {
    var accumulator = InterfaceByteAccumulator()
    accumulator.add(["en0": 4_294_967_000])
    accumulator.add(["en0": 200])  // wrapped past 2^32: 296 + 200 bytes later
    #expect(accumulator.total == 496)
}

@Test func anInterfaceThatResetsItsCounterAddsNothing() {
    var accumulator = InterfaceByteAccumulator()
    accumulator.add(["en0": 1_000_000])
    accumulator.add(["en0": 5])  // looks like a huge wrap, which is really a reset
    #expect(accumulator.total == 0)
    accumulator.add(["en0": 105])
    #expect(accumulator.total == 100)
}

@Test func interfacesAreSummedAndOneThatDisappearsIsForgotten() {
    var accumulator = InterfaceByteAccumulator()
    accumulator.add(["en0": 100, "en1": 1_000])
    accumulator.add(["en0": 150, "en1": 1_400])
    #expect(accumulator.total == 450)
    accumulator.add(["en0": 160])  // en1 went away
    #expect(accumulator.total == 460)
    accumulator.add(["en0": 160, "en1": 5_000])  // en1 is back: a fresh baseline, not a jump
    #expect(accumulator.total == 460)
}

// MARK: Formatting

@Test func ratesUseReadableUnits() {
    #expect(StatsFormat.rate(0) == "0 B/s")
    #expect(StatsFormat.rate(999) == "999 B/s")
    #expect(StatsFormat.rate(12_000) == "12 KB/s")
    #expect(StatsFormat.rate(2_500_000) == "2.5 MB/s")
    #expect(StatsFormat.rate(3_200_000_000) == "3.20 GB/s")
    #expect(StatsFormat.rate(-50) == "0 B/s")
}

@Test func memoryIsShownInGigabytes() {
    #expect(StatsFormat.memory(0) == "0.0 GB")
    #expect(StatsFormat.memory(17_179_869_184) == "16.0 GB")
}
