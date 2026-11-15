import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
import IslandCore
@testable import IslandUI

// The island's keyboard shortcuts on the real model: which key does what, when it must be left alone, and the bookkeeping that
// lets the keyboard go back to the app the person was in. (The monitors that feed key presses in live in the panel controller,
// which needs the whole app to build; what they hand to this is tried here.)

@MainActor
private func makeModel() -> IslandModel {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("island-ui-tests-\(UUID().uuidString)/settings.json")
    return IslandModel(settings: SettingsStore(store: FileStore(url: url, defaultValue: Settings())))
}

@MainActor
private func someOtherApp() -> NSRunningApplication {
    let me = ProcessInfo.processInfo.processIdentifier
    return NSWorkspace.shared.runningApplications.first { $0.processIdentifier != me }!
}

@MainActor
private final class Rig {
    let model = makeModel()
    var settingsOpened = 0
    lazy var handler = IslandShortcutHandler(model: model, openSettings: { [unowned self] in settingsOpened += 1 })

    init(mode: IslandMode = .expanded) { model.mode = mode }

    func press(_ key: String, command: Bool = false, shift: Bool = false, typing: Bool = false, isRepeat: Bool = false) -> Bool {
        handler.handle(KeyPress(key: key, command: command, shift: shift, isRepeat: isRepeat), isTyping: typing)
    }
}

// MARK: What the keys do

@Test @MainActor func fOpensFocusModeAndFAgainLeavesIt() {
    let rig = Rig()
    #expect(rig.press("f") && rig.model.isFocusView)
    #expect(rig.press("f") && !rig.model.isFocusView)
}

@Test @MainActor func mSwitchesBetweenTheUsualSizeAndMax() {
    let rig = Rig()
    #expect(rig.press("m") && rig.model.isMax)
    #expect(rig.press("m") && !rig.model.isMax)
}

@Test @MainActor func pPinsAndUnpins() {
    let rig = Rig()
    #expect(rig.press("p") && rig.model.isPinned)
    #expect(rig.press("p") && !rig.model.isPinned)
}

@Test @MainActor func commandCommaOpensSettingsOnce() {
    let rig = Rig()
    #expect(rig.press(",", command: true))
    #expect(rig.settingsOpened == 1)
}

@Test @MainActor func theKeysDoNotTouchTheOtherSettingsOfTheIsland() {
    let rig = Rig()
    rig.model.isMax = true
    rig.model.isPinned = true
    #expect(rig.press("f"))
    #expect(rig.model.isMax && rig.model.isPinned)                       // focus mode leaves Max and Pin as they were
    #expect(rig.press("f"))
    #expect(rig.model.isMax && rig.model.isPinned && !rig.model.isFocusView)
}

// MARK: When they must be left alone

@Test @MainActor func theLettersAreLeftAloneWhileTypingButCommandCommaIsNot() {
    let rig = Rig()
    for key in ["f", "m", "p"] { #expect(!rig.press(key, typing: true), "\(key)") }
    #expect(!rig.model.isFocusView && !rig.model.isMax && !rig.model.isPinned)
    #expect(rig.press(",", command: true, typing: true))
    #expect(rig.settingsOpened == 1)
}

@Test @MainActor func aClosedIslandIgnoresAllOfThem() {
    let rig = Rig(mode: .collapsed)
    for (key, command) in [("f", false), ("m", false), ("p", false), (",", true)] { #expect(!rig.press(key, command: command), "\(key)") }
    #expect(!rig.model.isFocusView && !rig.model.isMax && !rig.model.isPinned && rig.settingsOpened == 0)
}

@Test @MainActor func capitalsCommandLettersAndHeldKeysAreNotShortcuts() {
    let rig = Rig()
    #expect(!rig.press("f", shift: true) && !rig.press("m", command: true) && !rig.press("p", command: true))
    #expect(!rig.press("f", isRepeat: true))
    #expect(!rig.model.isFocusView && !rig.model.isMax && !rig.model.isPinned)
}

@Test @MainActor func inFocusModeMAndPAreNotTakenBecauseThereIsNothingToSwitch() {
    let rig = Rig()
    #expect(rig.press("f"))
    #expect(!rig.press("m") && !rig.press("p"))
    #expect(!rig.model.isMax && !rig.model.isPinned && rig.model.isFocusView)
}

@Test @MainActor func focusModeStillWorksFromACollapsedIslandBecauseTheCardIsShowing() {
    let rig = Rig(mode: .collapsed)
    rig.model.isFocusView = true
    #expect(rig.press("f") && !rig.model.isFocusView)
}

@Test @MainActor func settingsFromFocusModeLeavesFocusModeFirstSoSettingsIsNotHiddenBehindTheCard() {
    let rig = Rig()
    rig.model.isFocusView = true
    #expect(rig.press(",", command: true))
    #expect(!rig.model.isFocusView && rig.settingsOpened == 1)
}

// MARK: What counts as typing

@Test @MainActor func nothingFocusedAndTheHostingViewAreNotTyping() {
    #expect(!IslandKeyboard.isTyping(nil))
    #expect(!IslandKeyboard.isTyping(NSView()))
    #expect(!IslandKeyboard.isTyping(NSHostingView(rootView: Text("x"))))     // what has the keyboard when no box is being edited
}

@Test @MainActor func aTextBoxBeingEditedIsTyping() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
    let field = NSTextField(string: "abc")
    field.frame = NSRect(x: 0, y: 0, width: 120, height: 22)
    window.contentView?.addSubview(field)
    #expect(!IslandKeyboard.isTyping(window.firstResponder))
    window.makeFirstResponder(field)
    #expect(IslandKeyboard.isTyping(window.firstResponder))                  // while editing, the box's text editor has the keyboard
    #expect(IslandKeyboard.isTyping(NSTextView()))
}

@Test @MainActor func aWebPageAndAnythingInsideItIsTyping() {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
    #expect(IslandKeyboard.isTyping(web))
    let inner = NSView()
    web.addSubview(inner)
    #expect(IslandKeyboard.isTyping(inner))
}

// MARK: Key events

@Test @MainActor func aKeyEventBecomesTheKeyPressItStandsFor() {
    func event(_ characters: String, _ flags: NSEvent.ModifierFlags, isRepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: 0)!
    }
    #expect(KeyPress(event("f", [])) == KeyPress(key: "f"))
    #expect(KeyPress(event("F", [.capsLock])) == KeyPress(key: "f"))          // caps lock is not a modifier that matters
    #expect(KeyPress(event(",", [.command])) == KeyPress(key: ",", command: true))
    #expect(KeyPress(event("m", [.shift, .option])) == KeyPress(key: "m", option: true, shift: true))
    #expect(KeyPress(event("p", [], isRepeat: true)) == KeyPress(key: "p", isRepeat: true))
}

// MARK: Remembering the app the person was in

@Test @MainActor func theTrackerStartsWithTheAppInFrontUnlessThatIsIsland() {
    let other = someOtherApp()
    #expect(PreviousAppTracker(notifications: NotificationCenter(), frontmost: other).previous?.processIdentifier == other.processIdentifier)
    #expect(PreviousAppTracker(notifications: NotificationCenter(), frontmost: nil).previous == nil)
    #expect(PreviousAppTracker(notifications: NotificationCenter(), frontmost: NSRunningApplication.current).previous == nil)
}

@Test @MainActor func theTrackerFollowsAppsComingToTheFrontExceptIslandItself() async throws {
    let center = NotificationCenter()
    let tracker = PreviousAppTracker(notifications: center, frontmost: nil)
    let other = someOtherApp()
    center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: other])
    for _ in 0..<100 where tracker.previous == nil { try await Task.sleep(nanoseconds: 10_000_000) }
    #expect(tracker.previous?.processIdentifier == other.processIdentifier)

    // Island coming to the front (it took the keyboard) must not become "the previous app".
    center.post(
        name: NSWorkspace.didActivateApplicationNotification, object: nil,
        userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
    try await Task.sleep(nanoseconds: 80_000_000)
    #expect(tracker.previous?.processIdentifier == other.processIdentifier)
}
