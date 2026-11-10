import Testing
import AppKit
import Foundation
@testable import IslandUI

private final class FakeKeyboardLock: KeyboardLocking {
    var result = KeyboardLock.StartResult.started
    private(set) var starts = 0
    private(set) var stops = 0
    private var onEnd: (@Sendable () -> Void)?

    func start(duration: TimeInterval, onEnd: @escaping @Sendable () -> Void) -> KeyboardLock.StartResult {
        starts += 1
        if result == .started { self.onEnd = onEnd }
        return result
    }

    func stop() {
        stops += 1
        onEnd?()
        onEnd = nil
    }

    /// The lock ended by itself (its own timer, three Escapes, the system).
    func endByItself() {
        onEnd?()
        onEnd = nil
    }
}

private func waitUntil(timeout: TimeInterval = 30, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

@Test @MainActor func lockingStartsTheLockAndShowsTheRing() {
    let fake = FakeKeyboardLock()
    let tools = ToolsController(keyboardLock: fake, lockDuration: 30)
    #expect(tools.lockProgress == nil)
    tools.toggleKeyboardLock()
    #expect(tools.keyboard == .locked)
    #expect(fake.starts == 1)
    #expect(tools.lockProgress == 1)
    tools.toggleKeyboardLock()      // clicking the tile again unlocks at once
    #expect(tools.keyboard == .idle)
    #expect(fake.stops == 1)
    #expect(tools.lockProgress == nil)
}

@Test @MainActor func aLockThatEndsByItselfReturnsTheToolToIdle() async {
    let fake = FakeKeyboardLock()
    let tools = ToolsController(keyboardLock: fake, lockDuration: 30)
    tools.toggleKeyboardLock()
    fake.endByItself()              // for example the three-Escape escape hatch
    #expect(await waitUntil { tools.keyboard == .idle })
}

@Test @MainActor func withoutPermissionNothingIsLockedAndTheNoticeCanBeDismissed() {
    let fake = FakeKeyboardLock()
    fake.result = .needsPermission
    let tools = ToolsController(keyboardLock: fake, lockDuration: 30)
    tools.toggleKeyboardLock()
    #expect(tools.keyboard == .needsPermission)
    #expect(tools.lockProgress == nil)
    tools.dismissPermissionNotice()
    #expect(tools.keyboard == .idle)
}

@Test @MainActor func theMainThreadGuardEndsALockThatNothingElseEnded() async {
    let fake = FakeKeyboardLock()
    let tools = ToolsController(keyboardLock: fake, lockDuration: 0.3)   // a very short lock
    tools.toggleKeyboardLock()
    #expect(tools.keyboard == .locked)
    #expect(await waitUntil(timeout: 30) { tools.keyboard == .idle })
    #expect(fake.stops >= 1)
}

@Test @MainActor func aPickedColourIsShownWithItsCodesAndItsHexIsCopied() {
    var copied: [String] = []
    let tools = ToolsController(keyboardLock: FakeKeyboardLock(), writeToClipboard: { copied.append($0) })   // never the real clipboard
    tools.finishPicking(NSColor(srgbRed: 34 / 255, green: 211 / 255, blue: 238 / 255, alpha: 1))
    #expect(copied == ["#22D3EE"])
    #expect(tools.pickedColor?.hex == "#22D3EE")
    #expect(tools.pickedColor?.rgb == "rgb(34, 211, 238)")
    tools.dismissColor()
    #expect(tools.pickedColor == nil)
}

@Test @MainActor func cancellingThePickerChangesNothing() {
    let tools = ToolsController(keyboardLock: FakeKeyboardLock())
    tools.finishPicking(nil)
    #expect(tools.pickedColor == nil)
}
