import Foundation

/// A one-tap action offered for a clipboard entry that is, as a whole, a link, a hex color or an email address.
public enum SmartAction: Equatable, Hashable {
    case openLink(URL)
    /// The color as "r, g, b" (0-255).
    case copyRGB(String)
    case composeMail(String)

    /// Looks at the whole (trimmed) text only: a sentence that merely contains a link has no actions.
    public static func detect(in text: String) -> [SmartAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return [] }
        if let rgb = rgb(fromHex: trimmed) { return [.copyRGB(rgb)] }
        if let url = webURL(trimmed) { return [.openLink(url)] }
        if isEmail(trimmed) { return [.composeMail(trimmed)] }
        return []
    }

    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// `#RGB` or `#RRGGBB`; the leading `#` is required so ordinary words like "bad" are not colors.
    private static func rgb(fromHex text: String) -> String? {
        guard text.hasPrefix("#") else { return nil }
        var digits = Array(text.dropFirst())
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }), digits.count == 3 || digits.count == 6 else { return nil }
        if digits.count == 3 { digits = digits.flatMap { [$0, $0] } }
        let values = stride(from: 0, to: 6, by: 2).compactMap { UInt8(String(digits[$0...($0 + 1)]), radix: 16) }
        guard values.count == 3 else { return nil }
        return "\(values[0]), \(values[1]), \(values[2])"
    }

    private static func isEmail(_ text: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
