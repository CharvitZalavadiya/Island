import Testing
import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
@testable import IslandCore

private func makeImage(width: Int = 40, height: Int = 20, alpha: CGFloat = 1) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    if alpha > 0 {
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return context.makeImage()!
}

private func write(_ image: CGImage, as type: UTType, to url: URL, orientation: Int? = nil) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
}

private func writePDF(pages: Int, to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 200, height: 100)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    for _ in 0..<pages {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0, green: 0.4, blue: 1, alpha: 1))
        context.fill(box)
        context.endPDFPage()
    }
    context.closePDF()
}

private func imageType(of url: URL) -> String? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
}

private func decode(_ url: URL) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

private func fixturePNG(named name: String = "x.png", image: CGImage? = nil) throws -> URL {
    let url = makeTempDirectory().appendingPathComponent(name)
    try write(image ?? makeImage(), as: .png, to: url)
    return url
}

@Test func aPNGBecomesAJPEGNextToTheSourceWithAJpgExtension() throws {
    let source = try fixturePNG()
    let results = try ImageConverter.convert(source, to: .jpeg)
    #expect(results == [source.deletingLastPathComponent().appendingPathComponent("x.jpg")])
    #expect(imageType(of: results[0]) == "public.jpeg")
}

@Test func convertingToTheSameFormatNeverOverwritesTheOriginal() throws {
    let source = try fixturePNG()
    let before = try Data(contentsOf: source)
    let results = try ImageConverter.convert(source, to: .png)
    #expect(results == [source.deletingLastPathComponent().appendingPathComponent("x 2.png")])
    #expect(try Data(contentsOf: source) == before)
    #expect(FileManager.default.fileExists(atPath: results[0].path))
}

@Test func convertingTwiceKeepsEveryResult() throws {
    let source = try fixturePNG()
    let first = try ImageConverter.convert(source, to: .jpeg)
    let second = try ImageConverter.convert(source, to: .jpeg)
    #expect(first != second)
    #expect(second[0].lastPathComponent == "x 2.jpg")
}

@Test func convertsToHeicAndTiff() throws {
    let source = try fixturePNG()
    let heic = try ImageConverter.convert(source, to: .heic)
    #expect(imageType(of: heic[0]) == "public.heic")
    let tiff = try ImageConverter.convert(source, to: .tiff)
    #expect(imageType(of: tiff[0]) == "public.tiff")
}

@Test func anImageBecomesASinglePagePDF() throws {
    let source = try fixturePNG()
    let results = try ImageConverter.convert(source, to: .pdf)
    #expect(results[0].pathExtension == "pdf")
    #expect(PDFDocument(url: results[0])?.pageCount == 1)
}

@Test func aMultiPagePDFGivesOneNumberedFilePerPage() throws {
    let directory = makeTempDirectory()
    let pdf = directory.appendingPathComponent("doc.pdf")
    writePDF(pages: 2, to: pdf)
    let results = try ImageConverter.convert(pdf, to: .png)
    #expect(results.map(\.lastPathComponent) == ["doc 1.png", "doc 2.png"])
    for url in results { #expect(imageType(of: url) == "public.png") }
}

@Test func aSinglePagePDFGivesOneUnnumberedFile() throws {
    let directory = makeTempDirectory()
    let pdf = directory.appendingPathComponent("one.pdf")
    writePDF(pages: 1, to: pdf)
    let results = try ImageConverter.convert(pdf, to: .jpeg)
    #expect(results.map(\.lastPathComponent) == ["one.jpg"])
}

@Test func aPDFConvertedToPDFIsCopiedWithANewName() throws {
    let directory = makeTempDirectory()
    let pdf = directory.appendingPathComponent("doc.pdf")
    writePDF(pages: 2, to: pdf)
    let results = try ImageConverter.convert(pdf, to: .pdf)
    #expect(results.map(\.lastPathComponent) == ["doc 2.pdf"])
    #expect(PDFDocument(url: results[0])?.pageCount == 2)
}

@Test func aFileThatIsNotAnImageThrowsAndWritesNothing() throws {
    let directory = makeTempDirectory()
    let bad = directory.appendingPathComponent("bad.png")
    try "not an image".write(to: bad, atomically: true, encoding: .utf8)
    #expect(throws: ImageConverterError.self) { try ImageConverter.convert(bad, to: .jpeg) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["bad.png"])
}

@Test func transparentPixelsBecomeWhiteInAJPEG() throws {
    let source = try fixturePNG(image: makeImage(width: 8, height: 8, alpha: 0))
    let jpeg = try ImageConverter.convert(source, to: .jpeg)[0]
    let image = try decode(jpeg)
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let pixel = context.data!.assumingMemoryBound(to: UInt8.self)
    #expect(pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240)
}

@Test func thePhotoOrientationIsAppliedSoThePictureIsNotSideways() throws {
    let directory = makeTempDirectory()
    let sideways = directory.appendingPathComponent("photo.jpg")
    // 40 wide x 20 tall pixels, tagged "rotate 90°": it should come out 20 wide x 40 tall.
    try write(makeImage(width: 40, height: 20), as: .jpeg, to: sideways, orientation: 6)
    let png = try ImageConverter.convert(sideways, to: .png)[0]
    let image = try decode(png)
    #expect(image.width == 20)
    #expect(image.height == 40)
}
