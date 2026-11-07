import Foundation

public enum ColorFormat {
    /// "#22D3EE" from red, green and blue between 0 and 1.
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// "rgb(34, 211, 238)".
    public static func rgb(red: Double, green: Double, blue: Double) -> String {
        "rgb(\(byte(red)), \(byte(green)), \(byte(blue)))"
    }

    private static func byte(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }
}

/// Spots a key being pressed `count` times within `window` seconds: the emergency "let me out" of the keyboard lock
/// (Escape three times).
public struct PressCounter {
    public let count: Int
    public let window: TimeInterval
    private var times: [TimeInterval] = []

    public init(count: Int = 3, window: TimeInterval = 1.5) {
        self.count = count
        self.window = window
    }

    /// Records a press and says whether it was the `count`th within the window.
    public mutating func press(at time: TimeInterval) -> Bool {
        times.append(time)
        times.removeAll { time - $0 > window }
        if times.count >= count {
            times = []
            return true
        }
        return false
    }
}
