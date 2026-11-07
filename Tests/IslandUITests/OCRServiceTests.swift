import Testing
import AppKit
import Vision
@testable import IslandUI

/// Draws `text` in black on white, big enough for reliable recognition.
func makeTextImage(_ text: String) throws -> CGImage {
    let size = NSSize(width: 600, height: 120)
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 20, y: 30))
        return true
    }
    var rect = CGRect(origin: .zero, size: size)
    return try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
}

@Test func theFastLevelRecognizesRenderedText() async throws {
    let text = await OCRService(attempts: [.fast]).recognizeText(in: try makeTextImage("Hello Island"))
    #expect(text.contains("Hello"))
    #expect(text.contains("Island"))
}

@Test func aBlankImageHasNoText() async throws {
    let text = await OCRService(attempts: [.fast]).recognizeText(in: try makeTextImage(""))
    #expect(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

/// On some setups the accurate model cannot run (a Neural Engine error after a long wait).
/// The default service must still read the text, by falling back to the fast level.
@Test func theDefaultServiceStillReadsTextWhenTheAccurateModelFails() async throws {
    let text = await OCRService().recognizeText(in: try makeTextImage("Hello Island"))
    #expect(text.contains("Hello"))
    #expect(text.contains("Island"))
}
