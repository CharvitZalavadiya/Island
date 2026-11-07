import Foundation
import UniformTypeIdentifiers

/// What the shelf's action bar offers for the files that are currently selected.
public struct ShelfActions: Equatable {
    public var canZip = false
    /// The formats the selection can be converted to (empty unless every selected file is an image or PDF), never
    /// including the one every selected image already is.
    public var convertFormats: [ImageFormat] = []
    public var canUnzip = false
    public var canShowInFinder = false
    public var canAirDrop = false
    public var canRemove = false

    public init() {}

    /// `urls` are the selected files that exist.
    public static func make(for urls: [URL]) -> ShelfActions {
        var actions = ShelfActions()
        actions.canZip = urls.count >= 2
        actions.canUnzip = urls.count == 1 && isArchive(urls[0])
        actions.canShowInFinder = urls.count == 1
        actions.canAirDrop = !urls.isEmpty
        actions.canRemove = !urls.isEmpty

        // Convert is only offered when every selected file is an image (or PDF): a mixed selection shows no Convert.
        let convertible = urls.filter(isConvertible)
        if !convertible.isEmpty, convertible.count == urls.count {
            let formats = convertible.map(format(of:))
            if let first = formats[0], formats.allSatisfy({ $0 == first }) {
                actions.convertFormats = ImageFormat.allCases.filter { $0 != first }
            } else {
                actions.convertFormats = ImageFormat.allCases
            }
        }
        return actions
    }

    /// Images (any format macOS can read) and PDFs can be converted.
    public static func isConvertible(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    public static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    /// The output format a file already is, or nil for something Island can read but not write (a GIF, say).
    public static func format(of url: URL) -> ImageFormat? {
        switch url.pathExtension.lowercased() {
        case "heic", "heif": .heic
        case "png": .png
        case "jpg", "jpeg": .jpeg
        case "tif", "tiff": .tiff
        case "pdf": .pdf
        default: nil
        }
    }
}
