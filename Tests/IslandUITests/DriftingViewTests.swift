import Testing
import AppKit
import SwiftUI
import IslandCore
@testable import IslandUI

/// Puts the host view in a real (never shown) window, as it is when the island is on screen.
@MainActor
private func makeHost(celebrating: Bool = false, scale: CGFloat = 1) -> (DriftHostView<Color>, NSWindow) {
    let host = DriftHostView(content: Color.red)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.update(content: Color.red, celebrating: celebrating, scale: scale)
    return (host, window)
}

@Test @MainActor func theDriftLoopIsInstalledOnTheLayerAndRepeatsForever() throws {
    let (host, window) = makeHost()
    _ = window
    let animation = try #require(host.layer?.animation(forKey: "drift") as? CAKeyframeAnimation)
    #expect(animation.keyPath == "transform.translation")
    #expect(animation.duration == MascotMotion.driftLoopSeconds)
    #expect(animation.repeatCount == .infinity)
    #expect(animation.values?.count == 481)
    #expect(!animation.isRemovedOnCompletion)
}

@Test @MainActor func celebratingSwitchesToTheShortHopLoop() throws {
    let (host, window) = makeHost()
    _ = window
    host.update(content: Color.red, celebrating: true, scale: 1)
    let animation = try #require(host.layer?.animation(forKey: "drift") as? CAKeyframeAnimation)
    #expect(animation.duration == MascotMotion.hopLoopSeconds)
    #expect(animation.values?.count == 49)
}

@Test @MainActor func theKeyframesAreScaledToThePointsOfTheMascot() throws {
    let (host, window) = makeHost(scale: 2)
    _ = window
    let animation = try #require(host.layer?.animation(forKey: "drift") as? CAKeyframeAnimation)
    let sizes = (animation.values ?? []).compactMap { ($0 as? NSValue)?.sizeValue }
    #expect(sizes.count == 481)
    #expect(sizes.allSatisfy { abs($0.width) <= 6.001 && abs($0.height) <= 4.801 })   // twice the limits of 3 and 2.4
    #expect(sizes.map(\.width).max()! > 3 && sizes.map(\.height).max()! > 2)          // really uses the room
}

@Test @MainActor func aHopGoesUpWhichIsPositiveInALayer() throws {
    let (host, window) = makeHost(celebrating: true)
    _ = window
    let animation = try #require(host.layer?.animation(forKey: "drift") as? CAKeyframeAnimation)
    let heights = (animation.values ?? []).compactMap { ($0 as? NSValue)?.sizeValue.height }
    #expect(heights.min()! >= -0.0001)      // never dips below where it rests
    #expect(heights.max()! > 4.5)           // and reaches about the full 5 units up
}

@Test @MainActor func unrelatedUpdatesDoNotRestartTheLoop() throws {
    let (host, window) = makeHost()
    _ = window
    let installsAfterFirst = host.installCount
    host.update(content: Color.blue, celebrating: false, scale: 1)
    host.update(content: Color.green, celebrating: false, scale: 1)
    #expect(host.installCount == installsAfterFirst)
    host.update(content: Color.green, celebrating: true, scale: 1)
    #expect(host.installCount == installsAfterFirst + 1)
}

@Test @MainActor func theLoopComesBackWhenTheViewReturnsToAWindow() throws {
    let (host, window) = makeHost()
    window.contentView = NSView()                 // the host leaves the window...
    host.layer?.removeAnimation(forKey: "drift")  // ...and the system drops its animation
    window.contentView = host                     // it comes back
    #expect(host.layer?.animation(forKey: "drift") != nil)
}
