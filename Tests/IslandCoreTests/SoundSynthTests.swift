import Testing
import Foundation
@testable import IslandCore

private func samples(_ wav: Data) -> [Double] {
    wav.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Double($0) / 32768 }
}

/// How much of one pitch there is in a stretch of the sound (the Goertzel measure).
private func energy(of frequency: Double, in signal: [Double], from start: Double, to end: Double) -> Double {
    let rate = Double(SoundSynth.sampleRate)
    let slice = signal[Int(start * rate)..<min(Int(end * rate), signal.count)]
    let coefficient = 2 * cos(2 * .pi * frequency / rate)
    var previous = 0.0, beforePrevious = 0.0
    for sample in slice {
        let current = sample + coefficient * previous - beforePrevious
        beforePrevious = previous
        previous = current
    }
    return previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious
}

@Test func lockingFallsAndUnlockingRises() {
    let lock = samples(SoundSynth.lockChime()), unlock = samples(SoundSynth.unlockChime())
    let (high, low) = (SoundSynth.high, SoundSynth.low)
    // Lock: the first note is the high one, the second the low one.
    #expect(energy(of: high, in: lock, from: 0.01, to: 0.075) > 5 * energy(of: low, in: lock, from: 0.01, to: 0.075))
    #expect(energy(of: low, in: lock, from: 0.095, to: 0.17) > 5 * energy(of: high, in: lock, from: 0.095, to: 0.17))
    // Unlock: the other way round.
    #expect(energy(of: low, in: unlock, from: 0.01, to: 0.075) > 5 * energy(of: high, in: unlock, from: 0.01, to: 0.075))
    #expect(energy(of: high, in: unlock, from: 0.095, to: 0.17) > 5 * energy(of: low, in: unlock, from: 0.095, to: 0.17))
}
