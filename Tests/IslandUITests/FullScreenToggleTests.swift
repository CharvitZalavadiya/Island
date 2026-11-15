import Foundation
import Testing
@testable import IslandUI

// Going in and out of full screen, tried with a stand-in for the window (the real one is another app's window, reached through
// Accessibility, and is never touched here).

private final class FakeWindow: FullScreenWindow {
    var isFullScreen: Bool?
    var canChangeFullScreen: Bool
    var accepts: Bool
    private(set) var asked: [Bool] = []

    init(isFullScreen: Bool? = false, canChange: Bool = true, accepts: Bool = true) {
        self.isFullScreen = isFullScreen
        self.canChangeFullScreen = canChange
        self.accepts = accepts
    }

    func setFullScreen(_ on: Bool) -> Bool {
        asked.append(on)
        if accepts { isFullScreen = on }
        return accepts
    }
}

@Test func aWindowThatIsNotInFullScreenIsPutThere() {
    let window = FakeWindow(isFullScreen: false)
    #expect(FullScreenToggle.toggle(window) == .done)
    #expect(window.asked == [true])
}

@Test func aWindowInFullScreenIsBroughtBack() {
    let window = FakeWindow(isFullScreen: true)
    #expect(FullScreenToggle.toggle(window) == .done)
    #expect(window.asked == [false])
}

@Test func theSameTapTwiceGoesInAndThenOut() {
    let window = FakeWindow(isFullScreen: false)
    #expect(FullScreenToggle.toggle(window) == .done)
    #expect(window.isFullScreen == true)
    #expect(FullScreenToggle.toggle(window) == .done)
    #expect(window.isFullScreen == false)
    #expect(window.asked == [true, false])
}

@Test func aWindowThatCannotChangeIsLeftAloneAndSaysSo() {
    let window = FakeWindow(isFullScreen: false, canChange: false)
    #expect(FullScreenToggle.toggle(window) == .unavailable("This window can't go full screen"))
    #expect(window.asked.isEmpty)
}

@Test func anAppThatRefusesIsReportedNotPretendedDone() {
    let window = FakeWindow(isFullScreen: false, accepts: false)
    #expect(FullScreenToggle.toggle(window) == .unavailable("The app didn't go full screen"))
    #expect(window.asked == [true])
}

@Test func aWindowThatDoesNotSayWhereItIsIsTreatedAsNotInFullScreen() {
    let window = FakeWindow(isFullScreen: nil)
    #expect(FullScreenToggle.toggle(window) == .done)
    #expect(window.asked == [true])
}
