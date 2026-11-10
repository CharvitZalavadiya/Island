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

@Test func theOpenIslandHangsFromTheTopEdgeAndIsNearBlack() throws {
    let image = try largestImage()
    // Just under the top edge of the rounded square: the dark panel, in the middle and near its left side.
    for (x, y) in [(512, 125), (250, 130)] {
        let top = pixel(image, x: x, y: y)
        #expect(top.a == 255)
        #expect(top.r < 40 && top.g < 40 && top.b < 40, "expected near-black at \(x),\(y), got \(top)")
    }
    // Beside the panel, and below it, the square is light glass.
    for (x, y) in [(150, 450), (512, 760)] {
        let glass = pixel(image, x: x, y: y)
        #expect(glass.a == 255)
        #expect(glass.r > 200 && glass.g > 205 && glass.b > 210, "expected light glass at \(x),\(y), got \(glass)")
    }
}

@Test func theSixFeatureTilesAreBlueVioletAndOrange() throws {
    let image = try largestImage()
    // A point just inside the top-left corner of each tile, clear of the symbol in the middle.
    let blue = [(308, 240), (468, 400)]
    let violet = [(468, 240), (628, 400)]
    let orange = [(628, 240), (308, 400)]
    for (x, y) in blue {
        let p = pixel(image, x: x, y: y)
        #expect(p.r < 40 && p.g > 100 && p.g < 165 && p.b > 230, "expected blue at \(x),\(y), got \(p)")
    }
    for (x, y) in violet {
        let p = pixel(image, x: x, y: y)
        #expect(p.r > 165 && p.r < 215 && p.g > 60 && p.g < 125 && p.b > 220, "expected violet at \(x),\(y), got \(p)")
    }
    for (x, y) in orange {
        let p = pixel(image, x: x, y: y)
        #expect(p.r > 235 && p.g > 130 && p.g < 190 && p.b < 50, "expected orange at \(x),\(y), got \(p)")
    }
}

@Test func theSymbolsAreInkAndTheProgressBarIsBlue() throws {
    let image = try largestImage()
    // The play triangle's middle is dark ink on its blue tile.
    let play = pixel(image, x: 505, y: 444)
    #expect(play.r < 40 && play.g < 40 && play.b < 40, "expected ink, got \(play)")
    // The filled part of the progress bar is blue; the rest of the track is not.
    let filled = pixel(image, x: 400, y: 569)
    #expect(filled.b > 230 && filled.r < 40, "expected blue, got \(filled)")
    let empty = pixel(image, x: 600, y: 569)
    #expect(empty.b - empty.r < 30, "expected the grey track, got \(empty)")
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
    let sign = try #require(script.range(of: "codesign \"${SIGN[@]}\""))     // the script signs through one list of options
    #expect(copy.lowerBound < sign.lowerBound)
}

@Test func theIconScriptsExistAndUseOnlyToolsThatShipWithMacOS() throws {
    let drawing = try String(contentsOf: root.appendingPathComponent("scripts/make-icon.swift"), encoding: .utf8)
    #expect(drawing.contains("CGContext"))
    let shell = try String(contentsOf: root.appendingPathComponent("scripts/make-icon.sh"), encoding: .utf8)
    #expect(shell.contains("iconutil") && shell.contains("sips"))
    #expect(shell.contains("Packaging/AppIcon.icns"))
}
