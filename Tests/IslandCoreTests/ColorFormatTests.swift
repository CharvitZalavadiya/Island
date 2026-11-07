import Testing
@testable import IslandCore

@Test func colourStringsAreFormattedLikeDesignTools() {
    #expect(ColorFormat.hex(red: 34 / 255, green: 211 / 255, blue: 238 / 255) == "#22D3EE")
    #expect(ColorFormat.rgb(red: 34 / 255, green: 211 / 255, blue: 238 / 255) == "rgb(34, 211, 238)")
    #expect(ColorFormat.hex(red: 0, green: 0, blue: 0) == "#000000")
    #expect(ColorFormat.hex(red: 1, green: 1, blue: 1) == "#FFFFFF")
}

@Test func outOfRangeColourValuesAreClamped() {
    #expect(ColorFormat.hex(red: -0.5, green: 1.7, blue: 0.5) == "#00FF80")
}

@Test func threeQuickPressesAreRecognisedButSlowOnesAreNot() {
    var counter = PressCounter(count: 3, window: 1.5)
    let first = counter.press(at: 0)
    let second = counter.press(at: 0.4)
    let third = counter.press(at: 0.9)
    let afterwards = counter.press(at: 1.0)   // after it fires the count starts again
    #expect(!first && !second)
    #expect(third)
    #expect(!afterwards)

    var slow = PressCounter(count: 3, window: 1.5)
    let a = slow.press(at: 0)
    let b = slow.press(at: 1.0)
    let c = slow.press(at: 2.0)    // the first press is too old by now
    let d = slow.press(at: 2.5)
    #expect(!a && !b && !c)
    #expect(d)
}
