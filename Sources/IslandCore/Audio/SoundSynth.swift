import Foundation

/// The two tiny sounds Island makes when the Mac locks and unlocks, 0.2 seconds each. They are generated here, as WAV
/// data, so there is nothing to ship or license. The direction of the notes says which is which, the way a closing and
/// an opening sound would: locking falls (high note, then low), unlocking rises (low note, then high).
public enum SoundSynth {
    public static let sampleRate = 44_100
    /// Both sounds last exactly this long.
    public static let duration = 0.2

    /// The two notes: G5 and C5. A fourth apart is the smallest step that is still obvious as "down" or "up".
    static let high = 783.99
    static let low = 523.25
    /// When the second note starts.
    static let secondNote = 0.085

    /// Locking: two soft notes falling, high then low, mellow.
    public static func lockChime() -> Data {
        var mix = Mix(seconds: duration)
        mix.addNote(frequency: high, start: 0, decay: 0.032, gain: 0.85, brightness: 0.15)
        mix.addNote(frequency: low, start: secondNote, decay: 0.035, gain: 1.0, brightness: 0.2)
        return wav(mix.samples(peak: 0.4))
    }

    /// Unlocking: two soft notes rising, low then high, a little brighter than the lock.
    public static func unlockChime() -> Data {
        var mix = Mix(seconds: duration)
        mix.addNote(frequency: low, start: 0, decay: 0.032, gain: 0.8, brightness: 0.2)
        mix.addNote(frequency: high, start: secondNote, decay: 0.035, gain: 1.0, brightness: 0.35)
        return wav(mix.samples(peak: 0.4))
    }

    /// Mono 16-bit PCM in a WAV container.
    static func wav(_ samples: [Int16]) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        func append32(_ value: Int) { var v = UInt32(value).littleEndian; data.append(Data(bytes: &v, count: 4)) }
        func append16(_ value: Int) { var v = UInt16(value).littleEndian; data.append(Data(bytes: &v, count: 2)) }
        data.append(contentsOf: Array("RIFF".utf8)); append32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append32(16)
        append16(1); append16(1)                       // PCM, one channel
        append32(sampleRate); append32(sampleRate * 2) // sample rate, bytes per second
        append16(2); append16(16)                      // bytes per frame, bits per sample
        data.append(contentsOf: Array("data".utf8)); append32(dataSize)
        for sample in samples { append16(Int(UInt16(bitPattern: sample))) }
        return data
    }

    /// A buffer sounds are added into.
    private struct Mix {
        private var buffer: [Double]
        private var noiseState: UInt32 = 0x1234_5678   // fixed seed: the sound is the same every time

        init(seconds: Double) {
            buffer = Array(repeating: 0, count: Int(seconds * Double(SoundSynth.sampleRate)))
        }

        private mutating func noise() -> Double {
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            return Double(noiseState >> 8) / Double(1 << 24) * 2 - 1
        }

        /// One soft note: a sine with a touch of overtone, a very short fade-in (no click) that dies away.
        mutating func addNote(frequency: Double, start: Double, decay: Double, gain: Double, brightness: Double) {
            let rate = Double(SoundSynth.sampleRate)
            let first = Int(start * rate)
            guard first < buffer.count else { return }
            for i in first..<buffer.count {
                let t = Double(i - first) / rate
                let phase = 2 * .pi * frequency * t
                let tone = sin(phase) + brightness * sin(2 * phase) + brightness * 0.4 * sin(3 * phase)
                buffer[i] += gain * min(t / 0.005, 1) * exp(-t / decay) * tone
            }
        }

        /// The sound as 16-bit samples, scaled so that its loudest point is `peak` of full scale, and faded out over the
        /// last 30 ms so it ends in silence (a sound that stops abruptly clicks).
        func samples(peak target: Double) -> [Int16] {
            let loudest = max(buffer.map(abs).max() ?? 1, 1e-9)
            let fade = Int(0.03 * Double(SoundSynth.sampleRate))
            return buffer.enumerated().map { index, value in
                let remaining = buffer.count - index
                let envelope = remaining >= fade ? 1.0 : 0.5 * (1 - cos(.pi * Double(remaining) / Double(fade)))
                return Int16(max(min(value / loudest * target * envelope, 1), -1) * Double(Int16.max))
            }
        }
    }
}
