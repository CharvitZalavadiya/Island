import Foundation

public enum ClipboardContent: Codable, Equatable {
    case text(String)
    case link(URL)
    /// An image Island saved as a PNG in its own images folder.
    case image(fileName: String)
    case files([URL])
}

public struct ClipboardEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public var content: ClipboardContent
    public var date: Date
    public var pinned: Bool
    /// Text found in an image by on-device recognition.
    public var ocrText: String?

    public init(id: UUID = UUID(), content: ClipboardContent, date: Date, pinned: Bool = false, ocrText: String? = nil) {
        self.id = id
        self.content = content
        self.date = date
        self.pinned = pinned
        self.ocrText = ocrText
    }
}
