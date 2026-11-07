import Testing
@testable import IslandCore

@Test func hoverOpensThenDelayedCollapse() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    #expect(machine.mode == .collapsed)

    #expect(machine.handle(.pointerEntered) == .cancelCollapse)
    #expect(machine.mode == .expanded)

    #expect(machine.handle(.pointerExited) == .scheduleCollapse(after: 0.4))
    #expect(machine.mode == .expanded)

    #expect(machine.handle(.collapseDelayElapsed) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func reenteringCancelsPendingCollapse() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    _ = machine.handle(.pointerExited)
    #expect(machine.handle(.pointerEntered) == .cancelCollapse)

    // A stale timer firing while the pointer is inside must not collapse the island.
    #expect(machine.handle(.collapseDelayElapsed) == .none)
    #expect(machine.mode == .expanded)
}

@Test func hoverDisabledNeedsClick() {
    var machine = ExpansionStateMachine(hoverOpens: false, collapseDelay: 0.4)
    #expect(machine.handle(.pointerEntered) == .none)
    #expect(machine.mode == .collapsed)

    #expect(machine.handle(.clicked) == .cancelCollapse)
    #expect(machine.mode == .expanded)

    #expect(machine.handle(.pointerExited) == .scheduleCollapse(after: 0.4))
    #expect(machine.handle(.collapseDelayElapsed) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func clickingWhileExpandedDoesNotCollapse() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    #expect(machine.handle(.clicked) == .none)
    #expect(machine.mode == .expanded)
}

@Test func exitingWhileCollapsedDoesNothing() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    #expect(machine.handle(.pointerExited) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func collapseDelayCanBeChangedLive() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    machine.collapseDelay = 1.5
    _ = machine.handle(.pointerEntered)
    #expect(machine.handle(.pointerExited) == .scheduleCollapse(after: 1.5))
}

// MARK: Pinning

@Test func pinningOpensTheIslandAndCancelsAnyCollapse() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    #expect(machine.setPinned(true) == .cancelCollapse)
    #expect(machine.mode == .expanded)
    #expect(machine.isPinned)
}

@Test func pinningTwiceChangesNothingTheSecondTime() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setPinned(true)
    #expect(machine.setPinned(true) == .cancelCollapse)
    #expect(machine.mode == .expanded)
}

@Test func whilePinnedLeavingNeverCollapses() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    _ = machine.setPinned(true)
    #expect(machine.handle(.pointerExited) == .none)
    #expect(machine.mode == .expanded)
}

@Test func aStaleCollapseTimerDoesNothingWhilePinned() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    _ = machine.handle(.pointerExited)        // a collapse is now scheduled...
    _ = machine.setPinned(true)               // ...but the user pins before it fires
    #expect(machine.handle(.collapseDelayElapsed) == .none)
    #expect(machine.mode == .expanded)
}

@Test func unpinningWithThePointerAwaySchedulesACollapse() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setPinned(true)
    #expect(machine.setPinned(false) == .scheduleCollapse(after: 0.4))
    #expect(machine.mode == .expanded)
    #expect(machine.handle(.collapseDelayElapsed) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func unpinningWithThePointerInsideKeepsItOpen() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    _ = machine.setPinned(true)
    #expect(machine.setPinned(false) == .none)
    #expect(machine.mode == .expanded)
    #expect(!machine.isPinned)
}

@Test func unpinningWhenNotPinnedDoesNothing() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    #expect(machine.setPinned(false) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func pinningAnIslandThatHoverIsDisabledForStillOpensIt() {
    var machine = ExpansionStateMachine(hoverOpens: false, collapseDelay: 0.4)
    _ = machine.setPinned(true)
    #expect(machine.mode == .expanded)
}

// MARK: Suspension (Mission Control is on screen)

@Test func whileSuspendedHoverDoesNotOpen() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    #expect(machine.setSuspended(true) == .none)
    #expect(machine.isSuspended)
    #expect(machine.handle(.pointerEntered) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func whileSuspendedAClickDoesNotOpen() {
    var machine = ExpansionStateMachine(hoverOpens: false, collapseDelay: 0.4)
    _ = machine.setSuspended(true)
    #expect(machine.handle(.clicked) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func whileSuspendedLeavingTheNotchSchedulesNothing() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setSuspended(true)
    _ = machine.handle(.pointerEntered)
    #expect(machine.handle(.pointerExited) == .none)
    #expect(machine.handle(.collapseDelayElapsed) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func suspendingAnOpenIslandClosesItAtOnce() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    #expect(machine.mode == .expanded)
    #expect(machine.setSuspended(true) == .cancelCollapse)
    #expect(machine.mode == .collapsed)
}

@Test func suspendingCancelsACollapseThatWasAlreadyScheduled() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    #expect(machine.handle(.pointerExited) == .scheduleCollapse(after: 0.4))
    #expect(machine.setSuspended(true) == .cancelCollapse)
    #expect(machine.mode == .collapsed)
}

@Test func suspendingAPinnedIslandClosesItAndUnsuspendingReopensIt() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setPinned(true)
    #expect(machine.mode == .expanded)

    #expect(machine.setSuspended(true) == .cancelCollapse)
    #expect(machine.mode == .collapsed)
    #expect(machine.isPinned)

    #expect(machine.setSuspended(false) == .cancelCollapse)
    #expect(machine.mode == .expanded)
    #expect(machine.isPinned)
}

@Test func unsuspendingAnUnpinnedIslandDoesNotOpenItByItself() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.handle(.pointerEntered)
    _ = machine.setSuspended(true)
    #expect(machine.setSuspended(false) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func unsuspendedBehavesAsBefore() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setSuspended(true)
    _ = machine.setSuspended(false)
    #expect(machine.handle(.pointerEntered) == .cancelCollapse)
    #expect(machine.mode == .expanded)
    #expect(machine.handle(.pointerExited) == .scheduleCollapse(after: 0.4))
    #expect(machine.handle(.collapseDelayElapsed) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func pinningWhileSuspendedRemembersThePinButDoesNotOpen() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setSuspended(true)
    #expect(machine.setPinned(true) == .none)
    #expect(machine.isPinned)
    #expect(machine.mode == .collapsed)

    #expect(machine.setSuspended(false) == .cancelCollapse)
    #expect(machine.mode == .expanded)
}

@Test func unpinningWhileSuspendedStaysClosedAfterwards() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setPinned(true)
    _ = machine.setSuspended(true)
    _ = machine.setPinned(false)
    #expect(machine.setSuspended(false) == .none)
    #expect(machine.mode == .collapsed)
}

@Test func suspendingOrUnsuspendingTwiceIsHarmless() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    _ = machine.setPinned(true)
    #expect(machine.setSuspended(false) == .none)
    #expect(machine.mode == .expanded)
    _ = machine.setSuspended(true)
    #expect(machine.setSuspended(true) == .none)
    #expect(machine.mode == .collapsed)
    _ = machine.setSuspended(false)
    #expect(machine.setSuspended(false) == .none)
    #expect(machine.mode == .expanded)
}

@Test func suspendingACollapsedIslandChangesNothingElse() {
    var machine = ExpansionStateMachine(hoverOpens: true, collapseDelay: 0.4)
    #expect(machine.setSuspended(true) == .none)
    #expect(machine.mode == .collapsed)
    #expect(!machine.isPinned)
}
