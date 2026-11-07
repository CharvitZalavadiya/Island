import Testing
import Foundation
@testable import IslandCore

private func row(_ pid: Int, _ cpu: Double, _ kilobytes: UInt64, _ path: String) -> ProcessRow {
    ProcessRow(pid: pid, cpuPercent: cpu, residentBytes: kilobytes * 1024, path: path)
}

// MARK: parse

@Test func parseReadsPidCpuRssAndAPathWithSpaces() {
    let output = """
          396  41.8  89360 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
        12345   0.0   2048 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
        """
    let rows = ProcessUsage.parse(psOutput: output)
    #expect(rows.count == 2)
    #expect(rows[0] == row(396, 41.8, 89360, "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"))
    #expect(rows[1].path == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    #expect(rows[1].residentBytes == 2048 * 1024)
}

@Test func parseSkipsBlankAndMalformedLines() {
    let output = """

        not a process line at all
           7   1.0
           8   1.0   100
           9   x.y   100 /bin/badcpu
          10   1.0   -5 /bin/badrss
         -11   1.0   100 /bin/badpid
          12   2.5   300 /bin/good
        \u{20}\u{20}\u{20}
        """
    #expect(ProcessUsage.parse(psOutput: output) == [row(12, 2.5, 300, "/bin/good")])
}

@Test func parseAcceptsPidZeroAndAComma() {
    let rows = ProcessUsage.parse(psOutput: "    0   0,5  1024 kernel_task\n")
    #expect(rows == [row(0, 0.5, 1024, "kernel_task")])
}

@Test func parseRejectsNonFiniteCpu() {
    #expect(ProcessUsage.parse(psOutput: "1 nan 100 /bin/a\n2 inf 100 /bin/b\n").isEmpty)
}

@Test func parseKeepsPathsWithInteriorRunsOfSpaces() {
    let rows = ProcessUsage.parse(psOutput: "5 1.0 10 /Applications/My  App.app/Contents/MacOS/My  App")
    #expect(rows.first?.path == "/Applications/My  App.app/Contents/MacOS/My  App")
}

@Test func parseOfNothingIsEmpty() {
    #expect(ProcessUsage.parse(psOutput: "").isEmpty)
}

// MARK: aggregate

@Test func aggregateGroupsHelpersUnderTheirApp() {
    let chrome = "/Applications/Google Chrome.app/Contents"
    let rows = [
        row(1, 10, 1000, "\(chrome)/MacOS/Google Chrome"),
        row(2, 5, 3000, "\(chrome)/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"),
        row(3, 2.5, 500, "\(chrome)/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)"),
        row(4, 1, 100, "/System/Applications/Safari.app/Contents/MacOS/Safari"),
    ]
    let apps = ProcessUsage.aggregate(rows)
    #expect(apps.map(\.name) == ["Google Chrome", "Safari"])
    #expect(apps[0].cpuPercent == 17.5)
    #expect(apps[0].residentBytes == 4500 * 1024)
    #expect(apps[1].cpuPercent == 1)
}

@Test func aggregateUsesTheExecutableNameWhenThereIsNoApp() {
    let rows = [
        row(1, 0.4, 100, "/usr/libexec/logd"),
        row(2, 0.1, 50, "/usr/libexec/logd"),
        row(3, 3, 200, "claude"),
        row(4, 0, 10, "/usr/sbin/Some Daemon"),
    ]
    let apps = ProcessUsage.aggregate(rows)
    #expect(apps.map(\.name) == ["Some Daemon", "claude", "logd"])
    let logd = apps.first { $0.name == "logd" }
    #expect(logd?.cpuPercent == 0.5)
    #expect(logd?.residentBytes == 150 * 1024)
}

@Test func aFolderThatMerelyContainsDotAppIsNotAnApp() {
    let apps = ProcessUsage.aggregate([row(1, 1, 1, "/Users/me/my.app.backup/tool")])
    #expect(apps.map(\.name) == ["tool"])
}

@Test func theOutermostAppOwnsItsNestedLoginItems() {
    let path = "/Applications/Foo.app/Contents/Library/LoginItems/Bar.app/Contents/MacOS/Bar"
    #expect(ProcessUsage.aggregate([row(1, 1, 1, path)]).map(\.name) == ["Foo"])
}

@Test func aggregateOfNothingIsEmpty() {
    #expect(ProcessUsage.aggregate([]).isEmpty)
}

@Test func aProcessWhosePathEndsInASlashStillGetsAName() {
    #expect(ProcessUsage.aggregate([row(1, 1, 1, "/")]).map(\.name) == ["/"])
}

// MARK: top

private let sample = [
    AppUsage(name: "A", cpuPercent: 5, residentBytes: 300),
    AppUsage(name: "B", cpuPercent: 50, residentBytes: 100),
    AppUsage(name: "C", cpuPercent: 20, residentBytes: 900),
    AppUsage(name: "D", cpuPercent: 20, residentBytes: 200),
]

@Test func topSortsByTheChosenMetricAndLimits() {
    #expect(ProcessUsage.top(sample, by: .cpu, limit: 2).map(\.name) == ["B", "C"])
    #expect(ProcessUsage.top(sample, by: .memory, limit: 3).map(\.name) == ["C", "A", "D"])
}

@Test func topBreaksTiesByNameSoTheListDoesNotShuffle() {
    #expect(ProcessUsage.top(sample, by: .cpu, limit: 4).map(\.name) == ["B", "C", "D", "A"])
}

@Test func topWithAHugeOrZeroLimit() {
    #expect(ProcessUsage.top(sample, by: .cpu, limit: 99).count == 4)
    #expect(ProcessUsage.top(sample, by: .cpu, limit: 0).isEmpty)
    #expect(ProcessUsage.top([], by: .memory, limit: 5).isEmpty)
}

// MARK: the real thing

@Test func theRealPsOutputOfThisMacParses() throws {
    let result = try ProcessCommandRunner().run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="])
    #expect(result.status == 0)
    let lines = result.stdout.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }
    let rows = ProcessUsage.parse(psOutput: result.stdout)
    // Every non-blank line is understood, and there are plenty of them on any Mac.
    #expect(rows.count >= 50)
    #expect(rows.count == lines.count)
    #expect(rows.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
    #expect(rows.allSatisfy { !$0.path.isEmpty && $0.cpuPercent >= 0 })
    let apps = ProcessUsage.aggregate(rows)
    #expect(!apps.isEmpty && apps.count < rows.count)
}
