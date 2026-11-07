import Foundation

/// What the user typed into the keep-awake minutes box.
public enum MinutesInput: Equatable {
    /// An empty box: stay awake until Stop, like running `stayawake` with no argument.
    case indefinite
    case minutes(Int)
    case invalid(String)

    /// Seven days. The cap keeps the deadline arithmetic far from overflow.
    public static let maxMinutes = 10080

    public static func parse(_ text: String) -> MinutesInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .indefinite }
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return .invalid("Enter a whole number of minutes, or leave the box empty to stay awake until you press Stop.")
        }
        guard let value = Int(trimmed), value <= maxMinutes else {
            return .invalid("Keep awake can run for at most \(maxMinutes) minutes (7 days).")
        }
        guard value >= 1 else { return .invalid("Enter at least 1 minute.") }
        return .minutes(value)
    }
}
