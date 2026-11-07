import Foundation

/// Base64 encoding and decoding of text.
public enum Base64Tool {
    public enum DecodeError: Error, Equatable {
        /// What was typed is not Base64.
        case notBase64
        /// It is Base64, but the bytes inside are not text.
        case notText(byteCount: Int)

        public var message: String {
            switch self {
            case .notBase64: "That doesn't look like Base64."
            case .notText(let count): "That is Base64, but the \(count) bytes inside are not text."
            }
        }
    }

    public static func encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Decodes Base64 back to text. It is forgiving about how the Base64 was written: spaces and line breaks are ignored,
    /// the URL-safe alphabet (`-` and `_`) is understood, missing `=` padding is added, and a leading
    /// `data:...;base64,` is dropped.
    public static func decode(_ text: String) -> Result<String, DecodeError> {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("data:"), let comma = cleaned.firstIndex(of: ",") {
            cleaned = String(cleaned[cleaned.index(after: comma)...])
        }
        cleaned = cleaned.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !cleaned.isEmpty else { return .failure(.notBase64) }
        let remainder = cleaned.count % 4
        if remainder == 1 { return .failure(.notBase64) }   // no Base64 text has a length like that
        if remainder != 0 { cleaned += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: cleaned) else { return .failure(.notBase64) }
        guard let string = String(data: data, encoding: .utf8) else { return .failure(.notText(byteCount: data.count)) }
        return .success(string)
    }
}
