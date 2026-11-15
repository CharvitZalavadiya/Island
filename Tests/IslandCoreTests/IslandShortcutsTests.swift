import Testing
@testable import IslandCore

private func shortcut(_ key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false,
    isRepeat: Bool = false, typing: Bool = false) -> IslandShortcut? {
    IslandShortcuts.shortcut(
        for: KeyPress(key: key, command: command, option: option, control: control, shift: shift, isRepeat: isRepeat), isTyping: typing)
}

@Test func fMPAndCommandCommaDoTheirOneJobEach() {
    #expect(shortcut("f") == .focusMode)
    #expect(shortcut("m") == .toggleMax)
    #expect(shortcut("p") == .togglePin)
    #expect(shortcut(",", command: true) == .openSettings)
}

@Test func theLettersAreCaseBlindSoCapsLockDoesNotBreakThem() {
    #expect(shortcut("F") == .focusMode && shortcut("M") == .toggleMax && shortcut("P") == .togglePin)
}

@Test func theLettersNeverCountWhileSomethingIsBeingTypedInto() {
    for key in ["f", "m", "p"] { #expect(shortcut(key, typing: true) == nil, "\(key)") }
}

@Test func commandCommaOpensSettingsEvenWhileTyping() {
    #expect(shortcut(",", command: true, typing: true) == .openSettings)
}

@Test func theLettersMustBePlainKeysSoCommandPAndFriendsAreLeftToOtherThings() {
    for key in ["f", "m", "p"] {
        #expect(shortcut(key, command: true) == nil, "command \(key)")      // ⌘F is a find, ⌘M a minimise, ⌘P a print
        #expect(shortcut(key, option: true) == nil, "option \(key)")
        #expect(shortcut(key, control: true) == nil, "control \(key)")
        #expect(shortcut(key, shift: true) == nil, "shift \(key)")          // a capital letter is typing
        #expect(shortcut(key, command: true, shift: true) == nil, "command shift \(key)")
    }
}

@Test func aCommaAloneOrWithTheWrongKeysIsNotTheSettingsShortcut() {
    #expect(shortcut(",") == nil)
    #expect(shortcut(",", command: true, shift: true) == nil)
    #expect(shortcut(",", command: true, option: true) == nil)
    #expect(shortcut(",", command: true, control: true) == nil)
    #expect(shortcut(",", option: true) == nil)
}

@Test func aHeldKeyOnlyCountsOnce() {
    #expect(shortcut("f", isRepeat: true) == nil)
    #expect(shortcut("m", isRepeat: true) == nil)
    #expect(shortcut(",", command: true, isRepeat: true) == nil)
}

@Test func otherKeysDoNothing() {
    for key in ["a", "z", "1", " ", "\r", "\u{1b}", "\t", "o", "g", ".", "/", "ف"] {
        #expect(shortcut(key) == nil, "\(key.debugDescription)")
    }
    #expect(shortcut("") == nil)
}
