import CoreGraphics

/// How wide each wing needs to be for the live activities on it.
/// Widths are raw sums plus a margin at the outer edge, chosen so that every activity at once still fits the 160-point cap
/// that `NotchGeometry` applies to each wing (right side: 48 + 56 + 18 + 30 + 8 = 160).
enum WingLayout {
    /// Breathing room between the icons or the time and the outer edge of the island (the shape's rounded corners
    /// otherwise make them look cut off).
    static let edgeInset: CGFloat = 8

    static let leftWidths: [LiveActivityKind: CGFloat] = [.pomodoro: 34, .keepAwake: 34, .media: 34]
    static let rightWidths: [LiveActivityKind: CGFloat] = [.pomodoro: 48, .keepAwake: 56, .focusMode: 18, .media: 30]

    static func widths(for activities: Set<LiveActivityKind>) -> (left: CGFloat, right: CGFloat) {
        let left = activities.reduce(CGFloat(0)) { $0 + (leftWidths[$1] ?? 0) }
        let right = activities.reduce(CGFloat(0)) { $0 + (rightWidths[$1] ?? 0) }
        return (left > 0 ? left + edgeInset : 0, right > 0 ? right + edgeInset : 0)
    }
}
