import SwiftUI

/// The island's silhouette, shaped like the notch itself: the body is a little narrower than the panel, its top corners
/// flare **outward** into the top edge of the screen (concave "ears") so it looks like part of the display rather than a
/// box laid on top, and its bottom corners are rounded.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    static let expanded: (top: CGFloat, bottom: CGFloat) = (14, 28)
    static let collapsed: (top: CGFloat, bottom: CGFloat) = (6, 12)

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Keep the radii sensible for small rectangles.
        let top = max(0, min(topRadius, rect.width / 2, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        // Left ear: sweeps from the screen edge in to the body.
        path.addQuadCurve(to: CGPoint(x: minX + top, y: minY + top), control: CGPoint(x: minX + top, y: minY))
        path.addLine(to: CGPoint(x: minX + top, y: maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: minX + top + bottom, y: maxY), control: CGPoint(x: minX + top, y: maxY))
        path.addLine(to: CGPoint(x: maxX - top - bottom, y: maxY))
        path.addQuadCurve(to: CGPoint(x: maxX - top, y: maxY - bottom), control: CGPoint(x: maxX - top, y: maxY))
        path.addLine(to: CGPoint(x: maxX - top, y: minY + top))
        // Right ear.
        path.addQuadCurve(to: CGPoint(x: maxX, y: minY), control: CGPoint(x: maxX - top, y: minY))
        path.closeSubpath()
        return path
    }
}
