import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum ImageFormat: CaseIterable {
    case heic, png, jpeg, tiff, pdf

    public var fileExtension: String {
        switch self {
        case .heic: "heic"
        case .png: "png"
        case .jpeg: "jpg"
        case .tiff: "tiff"
        case .pdf: "pdf"
        }
    }

    var type: UTType {
        switch self {
        case .heic: .heic
        case .png: .png
        case .jpeg: .jpeg
        case .tiff: .tiff
        case .pdf: .pdf
        }
    }
}

public enum ImageConverterError: Error, Equatable {
    case unreadable(URL)
    case writeFailed(URL)
}

/// Converts between HEIC, PNG, JPEG, TIFF and PDF, offline. Results are written next to the source and never
/// overwrite an existing file.
public enum ImageConverter {
    /// Returns the files written: one, or one per page when a multi-page PDF becomes images.
    public static func convert(_ source: URL, to format: ImageFormat) throws -> [URL] {
        if isPDF(source) { return try convertPDF(source, to: format) }
        let image = try loadImage(source)
        let output = OutputNamer.uniqueURL(for: source.deletingPathExtension().appendingPathExtension(format.fileExtension))
        try write(image, as: format, to: output)
        return [output]
    }

    // MARK: PDF sources

    private static func convertPDF(_ source: URL, to format: ImageFormat) throws -> [URL] {
        guard let document = PDFDocument(url: source), document.pageCount > 0 else {
            throw ImageConverterError.unreadable(source)
        }
        let base = source.deletingPathExtension()
        if format == .pdf {
            let output = OutputNamer.uniqueURL(for: base.appendingPathExtension("pdf"))
            try FileManager.default.copyItem(at: source, to: output)
            return [output]
        }

        var outputs: [URL] = []
        do {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = render(page) else {
                    throw ImageConverterError.unreadable(source)
                }
                let stem = document.pageCount == 1
                    ? base
                    : base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent) \(index + 1)")
                let output = OutputNamer.uniqueURL(for: stem.appendingPathExtension(format.fileExtension))
                try write(image, as: format, to: output)
                outputs.append(output)
            }
        } catch {
            for output in outputs { try? FileManager.default.removeItem(at: output) }
            throw error
        }
        return outputs
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func isPDF(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .pdf) {
            return true
        }
        return url.pathExtension.lowercased() == "pdf"
    }

    // MARK: Image sources

    /// Full-size pixels with the photo's orientation applied, so a phone photo does not come out sideways.
    private static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ImageConverterError.unreadable(url)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if max(width, height) > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height) }
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return image }
        if let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return image }
        throw ImageConverterError.unreadable(url)
    }

    // MARK: Writing

    private static func write(_ image: CGImage, as format: ImageFormat, to url: URL) throws {
        if format == .pdf {
            try writePDF(image, to: url)
            return
        }
        // JPEG has no transparency, so flatten onto white instead of letting transparent pixels turn black.
        let prepared = format == .jpeg ? flattenedOnWhite(image) : image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw ImageConverterError.writeFailed(url)
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg || format == .heic { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, prepared, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw ImageConverterError.writeFailed(url)
        }
    }

    private static func writePDF(_ image: CGImage, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw ImageConverterError.writeFailed(url)
        }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
    }

    private static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }
}
