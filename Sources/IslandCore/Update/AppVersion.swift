import Foundation

/// A version number such as 1.2.3 (a leading "v" and a missing last part are fine: "v1.2" is 1.2.0). Anything with letters in
/// it ("1.2.3-beta") is not a version Island offers, so it is not one here.
public struct AppVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "v" || first == "V" { trimmed.removeFirst() }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy(\.isASCII), piece.allSatisfy(\.isNumber), let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        parts = numbers
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
    public func hash(into hasher: inout Hasher) {
        var trimmed = parts
        while trimmed.count > 3, trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}
