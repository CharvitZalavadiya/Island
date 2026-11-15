import AppKit
import Foundation
import Testing
@testable import IslandUI

// Focus mode's stage, tried with windows nobody can see (the blur is fully transparent here) and a stand-in for switching apps,
// so nothing on the real screen changes and no real app loses the keyboard. How the blur looks, and the keyboard going back to
// a real app, are for a real try.

@MainActor
private final class FakeActivation: AppActivating {
    var front: NSRunningApplication?
    private(set) var islandActivated = 0
    private(set) var activated: [NSRunningApplication] = []

    var frontmostApplication: NSRunningApplication? { front }
    func activateIsland() { islandActivated += 1 }
    func activate(_ app: NSRunningApplication) { activated.append(app) }
}

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000)
}

/// Some app that is not Island, to be "the app the person was working in".
@MainActor
private func someOtherApp() -> NSRunningApplication {
    let me = ProcessInfo.processInfo.processIdentifier
    return NSWorkspace.shared.runningApplications.first { $0.processIdentifier != me }!
}

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

@MainActor
private final class Rig {
    let activation = FakeActivation()
    let clock = Clock()
    let panel = IslandPanel()
    let backdrop = FocusBackdrop(opacity: 0, animates: false)
    let stage: FocusStage
    let other = someOtherApp()
    var exits = 0

    init(grace: TimeInterval = 0.6) {
        _ = NSApplication.shared
        panel.setFrame(NSRect(x: 100, y: 100, width: 400, height: 300), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        activation.front = other
        let clock = clock
        stage = FocusStage(activation: activation, backdrop: backdrop, grace: grace, now: { clock.date })
        stage.onExit = { [unowned self] in exits += 1 }
    }

    deinit {
        MainActor.assumeIsolated {
            stage.hide(restoreFocus: false)
            backdrop.hide()
            panel.orderOut(nil)
        }
    }

    func escape(flags: NSEvent.ModifierFlags = [], in window: NSWindow?) -> NSEvent {
        key(code: 53, characters: "\u{1b}", flags: flags, in: window)
    }

    func key(code: UInt16, characters: String, flags: NSEvent.ModifierFlags = [], in window: NSWindow?) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func click(_ type: NSEvent.EventType = .leftMouseDown) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: backdrop.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// Waits for something that arrives through the main queue (a notification).
    func settle(until condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(nanoseconds: 10_000_000) }
    }
}

// MARK: Starting

@Test @MainActor func showingBlursTheWholeScreenAndPutsTheIslandAboveItWithTheKeyboard() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    #expect(rig.stage.isShowing)
    #expect(rig.backdrop.isShown && rig.backdrop.frame == screen)
    #expect(rig.activation.islandActivated == 1)
    let order = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue)
    let panelAt = order.firstIndex(of: rig.panel.windowNumber)
    let backdropAt = order.firstIndex(of: rig.backdrop.windowNumber)
    #expect(panelAt != nil && backdropAt != nil && panelAt! < backdropAt!)       // front to back: the island is in front of the blur
    #expect(rig.panel.level >= rig.backdrop.level)
}

@Test @MainActor func showingAgainOnlyMovesTheBlurAndDoesNotTakeTheKeyboardTwice() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    let bigger = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    rig.stage.show(panel: rig.panel, over: bigger)
    #expect(rig.activation.islandActivated == 1)
    #expect(rig.backdrop.frame == bigger)
}

@Test @MainActor func theBlurFollowsADisplayChangeOnlyWhileItShows() {
    let rig = Rig()
    let other = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    rig.stage.move(to: other)
    #expect(!rig.backdrop.isShown)
    rig.stage.show(panel: rig.panel, over: screen)
    rig.stage.move(to: other)
    #expect(rig.backdrop.frame == other)
}

// MARK: Escape

@Test @MainActor func escapeEndsItAndGivesTheKeyboardBackToTheAppThePersonWasIn() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    #expect(rig.stage.handleKey(rig.escape(in: rig.panel)))
    #expect(!rig.stage.isShowing && !rig.backdrop.isShown)
    #expect(rig.exits == 1)
    #expect(rig.activation.activated == [rig.other])
}

@Test @MainActor func escapeThroughTheRealEventPathEndsItAndIsTakenSoNothingElseSeesIt() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    NSApp.sendEvent(rig.escape(in: rig.panel))                    // runs the monitors, as a real key press does
    #expect(!rig.stage.isShowing)
    #expect(rig.exits == 1)
}

@Test @MainActor func escapeDoesNothingAfterItEnded() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    rig.stage.hide(restoreFocus: true)
    NSApp.sendEvent(rig.escape(in: rig.panel))                    // the monitor was taken away with it
    #expect(rig.exits == 0)
    #expect(!rig.stage.handleKey(rig.escape(in: rig.panel)))
}

@Test @MainActor func escapeIsOnlyForTheIslandAndOnlyPlain() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    #expect(!rig.stage.handleKey(rig.escape(in: nil)))                                 // meant for some other window
    #expect(!rig.stage.handleKey(rig.escape(flags: .command, in: rig.panel)))          // Command-Escape is not Escape
    #expect(!rig.stage.handleKey(rig.escape(flags: [.shift, .option], in: rig.panel)))
    #expect(rig.stage.isShowing && rig.exits == 0)
}

@Test @MainActor func otherKeysAreLeftForTheTabsToUse() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    for (code, text) in [(UInt16(0), "a"), (36, "\r"), (48, "\t"), (49, " "), (51, "\u{7f}"), (123, "\u{f702}")] {
        #expect(!rig.stage.handleKey(rig.key(code: code, characters: text, in: rig.panel)), "key \(code)")
    }
    #expect(rig.stage.isShowing && rig.exits == 0)
}

@Test @MainActor func escapePressedTwiceEndsItOnce() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    #expect(rig.stage.handleKey(rig.escape(in: rig.panel)))
    #expect(!rig.stage.handleKey(rig.escape(in: rig.panel)))
    #expect(rig.exits == 1 && rig.activation.activated.count == 1)
}

@Test @MainActor func itOnlyWatchesTheKeyboardWhileItShowsHoweverItEnds() async throws {
    let rig = Rig()
    #expect(!rig.stage.isListening)
    rig.stage.show(panel: rig.panel, over: screen)
    #expect(rig.stage.isListening)
    rig.stage.hide(restoreFocus: true)                                                    // by the button
    #expect(!rig.stage.isListening)

    rig.stage.show(panel: rig.panel, over: screen)
    #expect(rig.stage.handleKey(rig.escape(in: rig.panel)))                              // by Escape
    #expect(!rig.stage.isListening)

    rig.stage.show(panel: rig.panel, over: screen)
    rig.backdrop.view.mouseDown(with: rig.click())                                         // by a click outside
    #expect(!rig.stage.isListening)

    rig.stage.show(panel: rig.panel, over: screen)
    rig.clock.date += 5
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)   // by leaving for another app
    try await rig.settle { !rig.stage.isShowing }
    #expect(!rig.stage.isListening)
}

// MARK: A click outside

@Test @MainActor func aClickAnywhereOnTheBlurEndsItAndGivesTheKeyboardBack() {
    for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
        let rig = Rig()
        rig.stage.show(panel: rig.panel, over: screen)
        let event = rig.click(type)
        switch type {
        case .leftMouseDown: rig.backdrop.view.mouseDown(with: event)
        case .rightMouseDown: rig.backdrop.view.rightMouseDown(with: event)
        default: rig.backdrop.view.otherMouseDown(with: event)
        }
        #expect(!rig.stage.isShowing && !rig.backdrop.isShown, "\(type)")
        #expect(rig.exits == 1 && rig.activation.activated == [rig.other], "\(type)")
    }
}

@Test @MainActor func theBlurTakesTheClickItselfSoItNeverReachesTheAppUnderneath() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    let view = rig.backdrop.view
    #expect(view.hitTest(NSPoint(x: 5, y: 5)) === view)                                // anywhere on it, the blur itself answers
    #expect(view.hitTest(NSPoint(x: 5000, y: 5000)) == nil)                            // but only where it is
    #expect(view.acceptsFirstMouse(for: nil))                                           // even the first click, while Island is inactive
}

// MARK: Leaving for another app, and the button

@Test @MainActor func leavingForAnotherAppEndsItAndDoesNotTakeTheKeyboardBack() async throws {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    rig.clock.date += 5                                                                   // well past the first moments
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    try await rig.settle { rig.exits > 0 }
    #expect(rig.exits == 1 && !rig.stage.isShowing && !rig.backdrop.isShown)
    #expect(rig.activation.activated.isEmpty)                                            // they chose the other app: leave it be
}

@Test @MainActor func losingTheKeyboardInTheFirstMomentsIsNotLeaving() async throws {
    let rig = Rig(grace: 0.6)
    rig.stage.show(panel: rig.panel, over: screen)
    rig.clock.date += 0.2
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    try await Task.sleep(nanoseconds: 80_000_000)
    #expect(rig.stage.isShowing && rig.exits == 0)
}

@Test @MainActor func theButtonEndsItAndGivesTheKeyboardBackWithoutAskingTheOwnerAgain() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    rig.stage.hide(restoreFocus: true)
    #expect(!rig.stage.isShowing && !rig.backdrop.isShown)
    #expect(rig.exits == 0)                                                               // the owner is the one who asked
    #expect(rig.activation.activated == [rig.other])
}

@Test @MainActor func endingItWhenItIsNotShowingDoesNothing() {
    let rig = Rig()
    rig.stage.hide(restoreFocus: true)
    #expect(rig.activation.activated.isEmpty && rig.exits == 0 && !rig.backdrop.isShown)
}

@Test @MainActor func ifIslandItselfWasInFrontThereIsNoOneToGiveTheKeyboardBackTo() {
    let rig = Rig()
    rig.activation.front = NSRunningApplication.current
    rig.stage.show(panel: rig.panel, over: screen)
    rig.stage.hide(restoreFocus: true)
    #expect(rig.activation.activated.isEmpty)
}

@Test @MainActor func itCanStartAgainAfterItEnded() {
    let rig = Rig()
    rig.stage.show(panel: rig.panel, over: screen)
    #expect(rig.stage.handleKey(rig.escape(in: rig.panel)))
    rig.stage.show(panel: rig.panel, over: screen)
    #expect(rig.stage.isShowing && rig.backdrop.isShown)
    #expect(rig.activation.islandActivated == 2)
    #expect(rig.stage.handleKey(rig.escape(in: rig.panel)))
    #expect(rig.exits == 2 && rig.activation.activated == [rig.other, rig.other])
}

// MARK: Windows

@Test @MainActor func aDialogIslandOpensIsAboveTheIslandAndSoAboveTheBlur() {
    #expect(IslandWindowLevel.dialog > IslandWindowLevel.island)
    #expect(IslandWindowLevel.dialog > NSWindow.Level.modalPanel)
    #expect(FocusBackdrop(opacity: 0, animates: false).level == IslandWindowLevel.island)
    #expect(IslandPanel().level == IslandWindowLevel.island)
}

@Test @MainActor func theBlurDoesNotHideWhenIslandIsNotTheActiveApp() {
    let backdrop = FocusBackdrop(opacity: 0, animates: false)
    let window = backdrop.view.window
    #expect(window != nil)
    #expect((window as? NSPanel)?.hidesOnDeactivate == false)
    #expect(window?.collectionBehavior.contains(.canJoinAllSpaces) == true)            // it is there over a full-screen app's space too
    #expect(window?.collectionBehavior.contains(.fullScreenAuxiliary) == true)
}
