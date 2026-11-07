import Testing
import SwiftUI
@testable import IslandUI

private let rect = CGRect(x: 0, y: 0, width: 300, height: 120)
private let shape = NotchShape(topRadius: 14, bottomRadius: 28)

@Test func theCenterIsInsideTheBody() {
    #expect(shape.path(in: rect).contains(CGPoint(x: 150, y: 60)))
}

@Test func theOuterTopCornersAreCurvedAwayFromTheBody() {
    // The concave "ears": right at the corner there is nothing, further in the body reaches the top edge.
    let path = shape.path(in: rect)
    #expect(!path.contains(CGPoint(x: 1, y: 1)))
    #expect(!path.contains(CGPoint(x: 299, y: 1)))
}

@Test func theBodyReachesTheTopEdgeAcrossTheMiddle() {
    let path = shape.path(in: rect)
    #expect(path.contains(CGPoint(x: 150, y: 1)))
    #expect(path.contains(CGPoint(x: 40, y: 1)))
    #expect(path.contains(CGPoint(x: 260, y: 1)))
}

@Test func theBodyIsNarrowerLowerDownThanAtTheTop() {
    let path = shape.path(in: rect)
    // At the top the body flares nearly to the edge; lower it sits inside the top-radius inset.
    #expect(path.contains(CGPoint(x: 10, y: 8)) == false)
    #expect(path.contains(CGPoint(x: 16, y: 60)))
    #expect(!path.contains(CGPoint(x: 8, y: 60)))
}

@Test func theBottomCornersAreRounded() {
    let path = shape.path(in: rect)
    #expect(!path.contains(CGPoint(x: 16, y: 118)))
    #expect(path.contains(CGPoint(x: 40, y: 118)))
    #expect(!path.contains(CGPoint(x: 284, y: 118)))
    #expect(path.contains(CGPoint(x: 260, y: 118)))
}

@Test func radiiAnimate() {
    var animated = NotchShape(topRadius: 14, bottomRadius: 28)
    animated.animatableData = AnimatablePair(6, 12)
    #expect(animated.topRadius == 6)
    #expect(animated.bottomRadius == 12)
    #expect(animated.animatableData.first == 6)
    #expect(animated.animatableData.second == 12)
}

@Test func hugeRadiiOnATinyRectStayInsideTheRect() {
    let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
    let box = NotchShape(topRadius: 50, bottomRadius: 50).path(in: tiny).boundingRect
    #expect(box.minX >= -0.001 && box.minY >= -0.001)
    #expect(box.maxX <= 10.001 && box.maxY <= 10.001)
}

@Test func theCollapsedShapeIsTighterThanTheExpandedOne() {
    #expect(NotchShape.collapsed.top < NotchShape.expanded.top)
    #expect(NotchShape.collapsed.bottom < NotchShape.expanded.bottom)
}
