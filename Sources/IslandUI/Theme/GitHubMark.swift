import SwiftUI

/// The GitHub mark, drawn as a shape so it takes its colour from the tab bar like the other icons (SF Symbols has no
/// GitHub logo). The outline is GitHub's Octicons "mark-github" (MIT licensed), a 16 by 16 drawing converted to curves.
///
/// The octocat is a hole in the disc, so fill it with the even-odd rule: `GitHubMark().fill(style: FillStyle(eoFill: true))`,
/// or use `GitHubMarkView`.
struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        // Scaled to fit and centred, whatever shape the box is.
        let scale = min(rect.width, rect.height) / 16
        let originX = rect.midX - 8 * scale, originY = rect.midY - 8 * scale
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: originX + x * scale, y: originY + y * scale) }

        var path = Path()
        path.move(to: point(8, 0))
        path.addCurve(to: point(0, 8), control1: point(3.58, 0), control2: point(0, 3.58))
        path.addCurve(to: point(5.47, 15.59), control1: point(0, 11.54), control2: point(2.29, 14.53))
        path.addCurve(to: point(6.02, 15.21), control1: point(5.87, 15.66), control2: point(6.02, 15.42))
        path.addCurve(to: point(6.01, 13.72), control1: point(6.02, 15.02), control2: point(6.01, 14.39))
        path.addCurve(to: point(3.32, 12.78), control1: point(4, 14.09), control2: point(3.48, 13.23))
        path.addCurve(to: point(2.5, 11.65), control1: point(3.23, 12.55), control2: point(2.84, 11.84))
        path.addCurve(to: point(2.49, 11.12), control1: point(2.22, 11.5), control2: point(1.82, 11.13))
        path.addCurve(to: point(3.72, 11.94), control1: point(3.12, 11.11), control2: point(3.57, 11.7))
        path.addCurve(to: point(6.05, 12.6), control1: point(4.44, 13.15), control2: point(5.59, 12.81))
        path.addCurve(to: point(6.56, 11.53), control1: point(6.12, 12.08), control2: point(6.33, 11.73))
        path.addCurve(to: point(2.92, 7.58), control1: point(4.78, 11.33), control2: point(2.92, 10.64))
        path.addCurve(to: point(3.74, 5.43), control1: point(2.92, 6.71), control2: point(3.23, 5.99))
        path.addCurve(to: point(3.82, 3.31), control1: point(3.66, 5.23), control2: point(3.38, 4.41))
        path.addCurve(to: point(6.02, 4.13), control1: point(3.82, 3.31), control2: point(4.49, 3.1))
        path.addCurve(to: point(8.02, 3.86), control1: point(6.66, 3.95), control2: point(7.34, 3.86))
        path.addCurve(to: point(10.02, 4.13), control1: point(8.7, 3.86), control2: point(9.38, 3.95))
        path.addCurve(to: point(12.22, 3.31), control1: point(11.55, 3.09), control2: point(12.22, 3.31))
        path.addCurve(to: point(12.3, 5.43), control1: point(12.66, 4.41), control2: point(12.38, 5.23))
        path.addCurve(to: point(13.12, 7.58), control1: point(12.81, 5.99), control2: point(13.12, 6.7))
        path.addCurve(to: point(9.47, 11.53), control1: point(13.12, 10.65), control2: point(11.25, 11.33))
        path.addCurve(to: point(10.01, 13.01), control1: point(9.76, 11.78), control2: point(10.01, 12.26))
        path.addCurve(to: point(10, 15.21), control1: point(10.01, 14.08), control2: point(10, 14.94))
        path.addCurve(to: point(10.55, 15.59), control1: point(10, 15.42), control2: point(10.15, 15.67))
        path.addCurve(to: point(16, 8), control1: point(13.8064, 14.4907), control2: point(15.9991, 11.437))
        path.addCurve(to: point(8, 0), control1: point(16, 3.58), control2: point(12.42, 0))
        path.closeSubpath()
        return path
    }
}

/// The GitHub mark at a given size, in the colour of the surrounding text.
struct GitHubMarkView: View {
    var size: CGFloat = 17

    var body: some View {
        GitHubMark()
            .fill(style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}
