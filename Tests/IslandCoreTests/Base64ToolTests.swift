import Testing
import Foundation
@testable import IslandCore

@Test func encodingGivesStandardBase64() {
    #expect(Base64Tool.encode("Hello, Island!") == "SGVsbG8sIElzbGFuZCE=")
    #expect(Base64Tool.encode("") == "")
    #expect(Base64Tool.encode("héllo ✓") == "aMOpbGxvIOKckw==")
}

@Test func decodingReversesEncoding() {
    for text in ["Hello, Island!", "héllo ✓", "a", "ab", "abc", "line one\nline two", String(repeating: "x", count: 1000)] {
        #expect(Base64Tool.decode(Base64Tool.encode(text)) == .success(text))
    }
}

@Test func decodingIsForgiving() {
    #expect(Base64Tool.decode("SGVsbG8sIElzbGFuZCE") == .success("Hello, Island!"))           // no padding
    #expect(Base64Tool.decode("  SGVsbG8s\nIElzbGFu\nZCE=  ") == .success("Hello, Island!"))   // spaces and line breaks
    #expect(Base64Tool.decode("data:text/plain;base64,SGVsbG8sIElzbGFuZCE=") == .success("Hello, Island!"))
    // URL-safe alphabet: "??>" encodes to "Pz8-" (standard "Pz8+")
    #expect(Base64Tool.decode("Pz8-") == .success("??>"))
}

@Test func nonsenseIsNotBase64() {
    #expect(Base64Tool.decode("") == .failure(.notBase64))
    #expect(Base64Tool.decode("   ") == .failure(.notBase64))
    #expect(Base64Tool.decode("not base64 at all!") == .failure(.notBase64))
    #expect(Base64Tool.decode("A") == .failure(.notBase64))
}

@Test func base64OfNonTextIsReportedAsSuch() {
    let bytes = Data([0xFF, 0xFE, 0xFD, 0x00, 0x80]).base64EncodedString()
    #expect(Base64Tool.decode(bytes) == .failure(.notText(byteCount: 5)))
    #expect(Base64Tool.DecodeError.notText(byteCount: 5).message.contains("5 bytes"))
}

// MARK: The lock and unlock sounds

@Test func bothLockSoundsAreExactlyTwoTenthsOfASecond() {
    // 44-byte WAV header + 0.2 s of 16-bit mono at 44.1 kHz.
    let expected = 44 + Int(0.2 * 44_100) * 2
    #expect(SoundSynth.lockChime().count == expected)
    #expect(SoundSynth.unlockChime().count == expected)
}

@Test func theTwoSoundsAreDifferentAndNotSilent() {
    let lock = SoundSynth.lockChime(), unlock = SoundSynth.unlockChime()
    #expect(lock != unlock)
    for sound in [lock, unlock] {
        let samples = sound.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(peak > 8_000 && peak < 20_000)   // audible but soft: between a quarter and about 60 % of full scale
        // And it fades to nothing before the end, so there is no click when it stops.
        #expect(samples.suffix(400).allSatisfy { abs(Int($0)) < 200 })
    }
}
