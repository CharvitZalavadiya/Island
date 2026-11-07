import Testing
import Foundation
@testable import IslandUI

@MainActor private func makeTools(now: Date = Date(timeIntervalSince1970: 1_794_000_000), use24Hour: Bool = true) -> TextToolsController {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return TextToolsController(now: { now }, use24Hour: { use24Hour }, calendar: calendar)
}

@Test @MainActor func base64StillEncodesAndDecodesOnItsButtons() {
    let tools = makeTools()
    tools.base64Input = "hello"
    #expect(tools.shown == .init(text: "", tone: .normal))        // nothing until a button is pressed
    tools.encode()
    #expect(tools.shown == .init(text: "aGVsbG8=", tone: .normal))
    tools.base64Input = "aGVsbG8="
    tools.decode()
    #expect(tools.shown == .init(text: "hello", tone: .normal))
    tools.base64Input = "%%%"
    tools.decode()
    #expect(tools.shown.tone == .error && tools.copyText.isEmpty)
    tools.clearOutput()
    #expect(tools.shown == .init(text: "", tone: .normal))
}

@Test @MainActor func eachToolKeepsItsOwnText() {
    let tools = makeTools()
    tools.input = "some text"                                      // Base64 is showing
    tools.mode = .cron
    #expect(tools.input == "")
    tools.input = "30 14 * * *"
    tools.mode = .base64
    #expect(tools.input == "some text" && tools.cronInput == "30 14 * * *")
    tools.clearInput()
    #expect(tools.base64Input == "" && tools.cronInput == "30 14 * * *")
}

@Test @MainActor func cronAnswersAsSoonAsItIsTypedWithNoButton() {
    let tools = makeTools()
    tools.mode = .cron
    #expect(tools.shown == .init(text: "", tone: .normal))          // nothing typed
    tools.input = "30 14"
    #expect(tools.shown.tone == .dim)                                // still typing: a calm hint, not an error
    tools.input = "30 14 * * *"
    let shown = tools.shown
    #expect(shown.tone == .normal)
    #expect(shown.text.hasPrefix("At 14:30 every day\n\nNext runs (GMT)\n"))
    #expect(shown.text.split(separator: "\n").count == 2 + TextToolsController.nextRunCount)   // the sentence, the heading and the run times
    tools.input = "99 14 * * *"
    #expect(tools.shown == .init(text: "Minute: 99 is out of range (0–59).", tone: .error))
    #expect(tools.copyText.isEmpty)                                  // nothing worth copying while it is wrong
}

@Test @MainActor func cronFollowsTheHourSettingAndShowsSecondsOnlyWhenTheyExist() {
    let twelve = makeTools(use24Hour: false)
    twelve.mode = .cron
    twelve.input = "30 14 * * *"
    #expect(twelve.shown.text.hasPrefix("At 2:30 PM every day"))
    twelve.input = "*/20 * * * * *"
    #expect(twelve.shown.text.hasPrefix("Every 20 seconds"))
}

@Test @MainActor func copyingTheCronResultCopiesTheWholeAnswer() {
    let tools = makeTools()
    tools.mode = .cron
    tools.input = "@daily"
    #expect(tools.copyText == tools.shown.text && tools.copyText.hasPrefix("At 00:00 every day"))
    tools.input = "@reboot"
    #expect(tools.shown.text == "Once, each time the system starts up")   // no run times to list
}
