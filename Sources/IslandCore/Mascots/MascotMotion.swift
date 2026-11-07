import Foundation
import CoreGraphics

/// How a mascot drifts about while a timer runs, as an offset in the mascot's own 26-unit drawing space.
///
/// The motion is one **closed loop** (it ends exactly where it starts) so it can be handed to Core Animation as a
/// repeating keyframe animation. That keeps the work in the render server: redrawing a SwiftUI view every frame cost
/// about 3.5% of a core however slowly it was updated, while a Core Animation loop leaves the app idle.
///
/// The drift is two sine waves per axis at different whole-number speeds, a lazy wander left and right and up and
/// down. A celebration is a quick, repeated hop instead.
public enum MascotMotion {
    /// The most the drift moves sideways and up or down, in drawing units.
    public static let maxDriftX: CGFloat = 3.0
    public static let maxDriftY: CGFloat = 2.4
    public static let maxHop: CGFloat = 5.0

    /// One full pass of the wander takes this long and then repeats exactly.
    public static let driftLoopSeconds = 24.0
    /// One hop takes this long and then repeats.
    public static let hopLoopSeconds = 0.48

    public static func loopSeconds(celebrating: Bool) -> Double {
        celebrating ? hopLoopSeconds : driftLoopSeconds
    }

    /// Where the mascot is at `time` seconds (the motion repeats every loop, also for times before zero).
    public static func offset(at time: TimeInterval, celebrating: Bool) -> CGSize {
        let loop = loopSeconds(celebrating: celebrating)
        var phase = time.truncatingRemainder(dividingBy: loop) / loop
        if phase < 0 { phase += 1 }
        return loopOffset(phase: phase, celebrating: celebrating)
    }

    /// `count + 1` positions along one whole loop, the last equal to the first, for a keyframe animation.
    public static func keyframes(celebrating: Bool, count: Int) -> [CGSize] {
        let steps = max(count, 1)
        return (0...steps).map { loopOffset(phase: Double($0) / Double(steps), celebrating: celebrating) }
    }

    /// The position a fraction `phase` (0 to 1) of the way round the loop. Negative y is up on screen.
    private static func loopOffset(phase: Double, celebrating: Bool) -> CGSize {
        if celebrating {
            return CGSize(width: 0, height: -abs(sin(Double.pi * phase)) * maxHop)
        }
        let turn = 2 * Double.pi * phase
        let x = 2.2 * sin(turn * 3) + 0.8 * sin(turn * 7 + 1.3)
        let y = 1.6 * sin(turn * 4 + 0.7) + 0.8 * sin(turn * 9 + 2.1)
        return CGSize(width: x, height: y)
    }
}
