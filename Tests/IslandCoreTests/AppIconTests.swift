import Testing
import Foundation
import ImageIO
@testable import IslandCore

/// The package root, found from this file's own location.
private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let iconURL = root.appendingPathComponent("Packaging/AppIcon.icns")

private func iconData() throws -> Data { try Data(contentsOf: iconURL) }

private func bigEndianUInt32(_ data: Data, at offset: Int) -> Int {
    data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
}

/// The chunks of an .icns file: a four-letter type and its payload.
private func chunks(of data: Data) -> [(type: String, payload: Data)] {
    var result: [(String, Data)] = []
    var offset = 8
    while offset + 8 <= data.count {
        let type = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let length = bigEndianUInt32(data, at: offset + 4)
        guard length >= 8, offset + length <= data.count else { break }
        result.append((type, data.subdata(in: offset + 8..<offset + length)))
        offset += length
    }
    return result
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw the image so that pixel (x, y) (counted from the top-left) lands on the one-pixel canvas.
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    let a = Int(bytes[3])
    guard a > 0 else { return (0, 0, 0, 0) }
    // Undo the premultiplication.
    return (Int(bytes[0]) * 255 / a, Int(bytes[1]) * 255 / a, Int(bytes[2]) * 255 / a, a)
}

private func largestImage() throws -> CGImage {
    let data = try iconData()
    let png = try #require(chunks(of: data).first { $0.type == "ic10" }?.payload)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

@Test func theIconFileExistsAndIsAValidIcns() throws {
    let data = try iconData()
    #expect(String(decoding: data.prefix(4), as: UTF8.self) == "icns")
    #expect(bigEndianUInt32(data, at: 4) == data.count)
    #expect(data.count > 20_000)
}

@Test func theIconCarriesTheStandardSizes() throws {
    let types = Set(chunks(of: try iconData()).map(\.type))
    // 16, 32, 64, 128, 256, 512 and 1024 pixels.
    for expected in ["ic04", "ic05", "ic12", "ic07", "ic08", "ic09", "ic10"] {
        #expect(types.contains(expected), "missing \(expected)")
    }
}

@Test func theBiggestImageIs1024Square() throws {
    let image = try largestImage()
    #expect(image.width == 1024 && image.height == 1024)
}

@Test func theIconKeepsTheStandardTransparentMargin() throws {
    let image = try largestImage()
    // The rounded square sits inside a 100 px margin: the corners and edges are clear.
    for (x, y) in [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (512, 40), (40, 512), (984, 512), (512, 984)] {
        #expect(pixel(image, x: x, y: y).a == 0, "pixel \(x),\(y) should be transparent")
    }
    #expect(pixel(image, x: 512, y: 700).a == 255)
}

@Test func theNotchPillIsCyanAndHangsFromTheTopEdge() throws {
    let image = try largestImage()
    // Just under the top edge of the rounded square, in the middle: the pill.
    let top = pixel(image, x: 512, y: 130)
    #expect(top.a == 255)
    #expect(top.b > 180 && top.g > 150 && top.r < 90, "expected cyan, got \(top)")
    // Beside the pill the square is near-black.
    let beside = pixel(image, x: 250, y: 130)
    #expect(beside.r < 40 && beside.g < 40 && beside.b < 40, "expected near-black, got \(beside)")
}

@Test func theMascotIsWhiteAndItsEyesAreDark() throws {
    let image = try largestImage()
    // Body centre of the mascot (below the eyes) is white; its left eye is dark.
    let body = pixel(image, x: 512, y: 700)
    #expect(body.r > 235 && body.g > 235 && body.b > 235, "expected white, got \(body)")
    let eye = pixel(image, x: 440, y: 550)
    #expect(eye.r < 60 && eye.g < 60 && eye.b < 60, "expected a dark eye, got \(eye)")
}

@Test func infoPlistNamesTheIcon() throws {
    let data = try Data(contentsOf: root.appendingPathComponent("Packaging/Info.plist"))
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
}

@Test func theBuildScriptCopiesTheIconIntoTheBundle() throws {
    let script = try String(contentsOf: root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
    #expect(script.contains("AppIcon.icns"))
    #expect(script.contains("Contents/Resources"))
    // It must be copied before the app is signed, or the signature would not cover it.
    let copy = try #require(script.range(of: "AppIcon.icns"))
    let sign = try #require(script.range(of: "codesign --force"))
    #expect(copy.lowerBound < sign.lowerBound)
}

@Test func theIconScriptsExistAndUseOnlyToolsThatShipWithMacOS() throws {
    let drawing = try String(contentsOf: root.appendingPathComponent("scripts/make-icon.swift"), encoding: .utf8)
    #expect(drawing.contains("CGContext"))
    let shell = try String(contentsOf: root.appendingPathComponent("scripts/make-icon.sh"), encoding: .utf8)
    #expect(shell.contains("iconutil") && shell.contains("sips"))
    #expect(shell.contains("Packaging/AppIcon.icns"))
}
