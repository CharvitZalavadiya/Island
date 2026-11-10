import Testing
import Foundation
@testable import IslandCore

@Test func noArgumentsMeansNoOptions() {
    #expect(LaunchOptions.parse(["/path/to/Island"]) == LaunchOptions())
    #expect(LaunchOptions.parse([]) == LaunchOptions())
}

@Test func theCheckingFlagsAreRecognised() {
    let options = LaunchOptions.parse(["Island", "--debug-wings", "--fast-pomodoro"])
    #expect(options.debugWings)
    #expect(options.fastPomodoro)
    #expect(options.supportDirectory == nil)
}

@Test func aSupportDirectoryIsTakenFromTheNextArgument() {
    let options = LaunchOptions.parse(["Island", "--support-dir", "/tmp/island-test"])
    #expect(options.supportDirectory == URL(fileURLWithPath: "/tmp/island-test"))
}

@Test func aSupportDirectoryFlagWithNoValueIsIgnored() {
    #expect(LaunchOptions.parse(["Island", "--support-dir"]).supportDirectory == nil)
}

@Test func aSupportDirectoryFlagFollowedByAnotherFlagIsIgnored() {
    let options = LaunchOptions.parse(["Island", "--support-dir", "--debug-wings"])
    #expect(options.supportDirectory == nil)
    #expect(options.debugWings)
}

@Test func unknownArgumentsAreIgnored() {
    #expect(LaunchOptions.parse(["Island", "-psn_0_12345", "--whatever", "x"]) == LaunchOptions())
}

@Test func flagsCanComeInAnyOrderWithTheDirectoryBetweenThem() {
    let options = LaunchOptions.parse(["Island", "--fast-pomodoro", "--support-dir", "/tmp/x", "--debug-wings"])
    #expect(options.fastPomodoro)
    #expect(options.debugWings)
    #expect(options.supportDirectory?.path == "/tmp/x")
}

@Test func startingThePomodoroAtLaunchIsAFlagForMeasuring() {
    #expect(LaunchOptions.parse(["Island", "--debug-start-pomodoro"]).debugStartPomodoro)
    #expect(!LaunchOptions.parse(["Island"]).debugStartPomodoro)
}

@Test func theDebugAlertFlagIsRecognisedAndOffByDefault() {
    #expect(!LaunchOptions().debugAlert)
    #expect(LaunchOptions.parse(["Island", "--debug-alert"]).debugAlert)
    #expect(LaunchOptions.parse(["Island", "--debug-wings", "--debug-alert"]).debugWings)
}

@Test func simulatingNoNotchIsAnOptInSwitch() {
    #expect(!LaunchOptions().simulateNoNotch)
    #expect(!LaunchOptions.parse(["Island"]).simulateNoNotch)
    #expect(LaunchOptions.parse(["Island", "--simulate-no-notch"]).simulateNoNotch)
    #expect(LaunchOptions.parse(["Island", "--debug-wings", "--simulate-no-notch", "--support-dir", "/tmp/x"]).simulateNoNotch)
}
