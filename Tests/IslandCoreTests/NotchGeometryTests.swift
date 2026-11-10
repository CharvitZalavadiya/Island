import Testing
import CoreGraphics
@testable import IslandCore

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

private func builtInNotch() -> CGRect {
    NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 38, auxLeftWidth: 650, auxRightWidth: 650)!
}

@Test func notchRectIsCenteredAtTopWithWidthFromAuxAreas() {
    let notch = builtInNotch()
    #expect(notch == CGRect(x: 650, y: 944, width: 212, height: 38))
    #expect(notch.midX == screen.midX)
    #expect(notch.maxY == screen.maxY)
}

@Test func notchRectHonorsScreenOrigin() {
    let external = CGRect(x: 1512, y: 100, width: 1512, height: 982)
    let notch = NotchGeometry.notchRect(screenFrame: external, safeAreaTop: 38, auxLeftWidth: 650, auxRightWidth: 650)
    #expect(notch == CGRect(x: 2162, y: 1044, width: 212, height: 38))
}

@Test func noNotchReturnsNil() {
    #expect(NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 0, auxLeftWidth: 0, auxRightWidth: 0) == nil)
}

@Test func wingsAreClampedToTheCap() {
    let notch = builtInNotch()
    let frame = NotchGeometry.collapsedFrame(notch: notch, screenFrame: screen, leftWing: 400, rightWing: 400)
    #expect(NotchGeometry.maxWingWidth == 160)
    #expect(frame.width == notch.width + 320)
    #expect(frame.minX == notch.minX - 160)
    #expect(frame.height == notch.height)
    #expect(frame.maxY == screen.maxY)
}

@Test func negativeWingsAreTreatedAsZero() {
    let notch = builtInNotch()
    let frame = NotchGeometry.collapsedFrame(notch: notch, screenFrame: screen, leftWing: -5, rightWing: -1)
    #expect(frame == notch)
}

@Test func asymmetricWingsGrowOnlyTheirOwnSide() {
    let notch = builtInNotch()
    let frame = NotchGeometry.collapsedFrame(notch: notch, screenFrame: screen, leftWing: 60, rightWing: 0)
    #expect(frame.minX == notch.minX - 60)
    #expect(frame.maxX == notch.maxX)
}

@Test func idleCollapsedFrameEqualsNotch() {
    let notch = builtInNotch()
    #expect(NotchGeometry.collapsedFrame(notch: notch, screenFrame: screen, leftWing: 0, rightWing: 0) == notch)
}

@Test func noNotchFallsBackToTopCenterPill() {
    let frame = NotchGeometry.collapsedFrame(notch: nil, screenFrame: screen, leftWing: 0, rightWing: 0)
    #expect(frame == CGRect(x: 661, y: 958, width: 190, height: 24))      // 190 wide, 24 tall, centered, flush with the top
    #expect(frame.midX == screen.midX)
    #expect(frame.maxY == screen.maxY)
}

@Test func theArtificialNotchIsAsTallAsTheMenuBarCenteredAndFlushWithTheTop() {
    let notch = NotchGeometry.artificialNotch(screenFrame: screen, menuBarHeight: 25)
    #expect(notch.size == CGSize(width: NotchGeometry.artificialNotchWidth, height: 25))
    #expect(notch.midX == screen.midX && notch.maxY == screen.maxY)
    #expect(screen.contains(notch))
}

@Test func theArtificialNotchStaysSensibleWhateverTheMenuBarReports() {
    func height(_ reported: CGFloat) -> CGFloat { NotchGeometry.artificialNotch(screenFrame: screen, menuBarHeight: reported).height }
    #expect(height(0) == 24)         // the menu bar is hidden (or reports nothing)
    #expect(height(-5) == 24)
    #expect(height(10) == 22)        // never thinner than 22
    #expect(height(24) == 24)
    #expect(height(37) == 37)
    #expect(height(200) == 40)       // never taller than 40
}

@Test func theArtificialNotchIsCenteredOnASecondDisplayThatDoesNotStartAtZero() {
    // An external display to the right of the built-in one, and another above it.
    for frame in [CGRect(x: 1512, y: 0, width: 2560, height: 1440), CGRect(x: -800, y: 982, width: 1920, height: 1080)] {
        let notch = NotchGeometry.artificialNotch(screenFrame: frame, menuBarHeight: 24)
        #expect(notch.midX == frame.midX && notch.maxY == frame.maxY)
        #expect(frame.contains(notch))
    }
}

@Test func theArtificialNotchTakesWingsAndOpensLikeARealOne() {
    let notch = NotchGeometry.artificialNotch(screenFrame: screen, menuBarHeight: 24)
    let withWings = NotchGeometry.collapsedFrame(notch: notch, screenFrame: screen, leftWing: 40, rightWing: 60)
    #expect(withWings.width == notch.width + 100 && withWings.height == notch.height && withWings.maxY == screen.maxY)
    let open = NotchGeometry.expandedFrame(notch: notch, screenFrame: screen, size: CGSize(width: 620, height: 330))
    #expect(open.midX == notch.midX && open.maxY == screen.maxY && open.size == CGSize(width: 620, height: 330))
}

@Test func noNotchPillAlsoGetsClampedWings() {
    let frame = NotchGeometry.collapsedFrame(notch: nil, screenFrame: screen, leftWing: 500, rightWing: 20)
    let half = NotchGeometry.artificialNotchWidth / 2
    let expectedMinX: CGFloat = screen.midX - half - NotchGeometry.maxWingWidth      // a 500-point wing is cut to the limit
    let expectedMaxX: CGFloat = screen.midX + half + 20
    #expect(frame.minX == expectedMinX)
    #expect(frame.maxX == expectedMaxX)
}

@Test func expandedFrameIsCenteredAndFlushWithTop() {
    let frame = NotchGeometry.expandedFrame(notch: builtInNotch(), screenFrame: screen, size: CGSize(width: 600, height: 300))
    #expect(frame == CGRect(x: 456, y: 682, width: 600, height: 300))
}

@Test func expandedFrameNeverExceedsTheScreen() {
    let frame = NotchGeometry.expandedFrame(notch: nil, screenFrame: screen, size: CGSize(width: 5000, height: 5000))
    #expect(frame.width == screen.width)
    #expect(frame.height == screen.height)
    #expect(screen.contains(frame))
}

// MARK: The event alert banner

@Test func theAlertIsCenteredOnTheNotchAndFlushWithTheTop() {
    let frame = NotchGeometry.alertFrame(notch: builtInNotch(), screenFrame: screen, size: NotchGeometry.alertSize)
    #expect(frame.size == CGSize(width: 380, height: 104))
    #expect(frame.midX == builtInNotch().midX)
    #expect(frame.maxY == screen.maxY)
}

@Test func theAlertSizeIsTheOneTheBannerIsDesignedFor() {
    #expect(NotchGeometry.alertSize == CGSize(width: 380, height: 104))
}

@Test func theAlertWithoutANotchIsCenteredOnTheScreen() {
    let frame = NotchGeometry.alertFrame(notch: nil, screenFrame: screen, size: NotchGeometry.alertSize)
    #expect(frame.midX == screen.midX)
    #expect(frame.maxY == screen.maxY)
}

@Test func theAlertStaysOnAScreenThatIsNarrowerThanIt() {
    let narrow = CGRect(x: 0, y: 0, width: 300, height: 600)
    let frame = NotchGeometry.alertFrame(notch: nil, screenFrame: narrow, size: NotchGeometry.alertSize)
    #expect(frame.minX >= narrow.minX && frame.maxX <= narrow.maxX)
    #expect(frame.width == 300)
}

@Test func theAlertStaysOnScreenWhenTheNotchIsNearAnEdge() {
    let edgeNotch = CGRect(x: 0, y: 944, width: 212, height: 38)
    let frame = NotchGeometry.alertFrame(notch: edgeNotch, screenFrame: screen, size: NotchGeometry.alertSize)
    #expect(frame.minX == 0)
}

@Test func theAlertHonoursTheScreenOrigin() {
    let external = CGRect(x: 1512, y: 100, width: 1512, height: 982)
    let notch = NotchGeometry.notchRect(screenFrame: external, safeAreaTop: 38, auxLeftWidth: 650, auxRightWidth: 650)
    let frame = NotchGeometry.alertFrame(notch: notch, screenFrame: external, size: NotchGeometry.alertSize)
    #expect(frame.midX == external.midX)
    #expect(frame.maxY == external.maxY)
}
