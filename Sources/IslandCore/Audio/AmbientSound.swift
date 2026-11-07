import Foundation

/// The background sounds you can play while you work. They are made up in code, sample by sample, so nothing is bundled.
public enum AmbientSound: String, CaseIterable, Codable, Sendable {
    case noise, brown, wind, sea, waterfall, rain

    public var title: String {
        switch self {
        case .noise: "Noise"
        case .brown: "Brown noise"
        case .wind: "Wind"
        case .sea: "Sea"
        case .waterfall: "Waterfall"
        case .rain: "Rain"
        }
    }

    public var symbol: String {
        switch self {
        case .noise: "waveform"
        case .brown: "waveform.path"
        case .wind: "wind"
        case .sea: "water.waves"
        case .waterfall: "water.waves.and.arrow.down"
        case .rain: "cloud.rain.fill"
        }
    }
}

/// Makes one ambient sound, a sample at a time. It holds its own filter states, so one generator belongs to one stream
/// of audio. The same seed always gives the same sound, which is what makes it testable.
public struct AmbientGenerator {
    public let sound: AmbientSound
    private let sampleRate: Double
    private var state: UInt32
    private var sampleIndex = 0

    // Filter memory.
    private var brownValue = 0.0
    private var pink = (b0: 0.0, b1: 0.0, b2: 0.0, b3: 0.0, b4: 0.0, b5: 0.0, b6: 0.0)
    private var lowpassA = 0.0
    private var lowpassB = 0.0
    private var previousWhite = 0.0
    private var droplets = [Double](repeating: 0, count: 8)

    public init(sound: AmbientSound, sampleRate: Double = 44_100, seed: UInt32 = 0x9E37_79B9) {
        self.sound = sound
        self.sampleRate = sampleRate
        self.state = seed == 0 ? 1 : seed
    }

    /// The next sample, between -1 and 1.
    public mutating func next() -> Float {
        let time = Double(sampleIndex) / sampleRate
        sampleIndex += 1
        let sample: Double
        switch sound {
        case .noise:
            sample = 0.35 * white()
        case .brown:
            sample = 3.2 * brownStep(white())
        case .wind:
            sample = windSample(time)
        case .sea:
            sample = seaSample(time)
        case .waterfall:
            sample = waterfallSample(time)
        case .rain:
            sample = rainSample()
        }
        // A gentle soft clip keeps every sound inside -1...1 whatever the filters do.
        return Float(tanh(sample))
    }

    // MARK: Building blocks

    private mutating func white() -> Double {
        // xorshift32, scaled to -1...1
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }

    private mutating func brownStep(_ white: Double) -> Double {
        brownValue = (brownValue + 0.02 * white) / 1.02
        return brownValue
    }

    /// Paul Kellet's economical pink-noise filter.
    private mutating func pinkStep(_ white: Double) -> Double {
        pink.b0 = 0.99886 * pink.b0 + white * 0.0555179
        pink.b1 = 0.99332 * pink.b1 + white * 0.0750759
        pink.b2 = 0.96900 * pink.b2 + white * 0.1538520
        pink.b3 = 0.86650 * pink.b3 + white * 0.3104856
        pink.b4 = 0.55000 * pink.b4 + white * 0.5329522
        pink.b5 = -0.7616 * pink.b5 - white * 0.0168980
        let value = pink.b0 + pink.b1 + pink.b2 + pink.b3 + pink.b4 + pink.b5 + pink.b6 + white * 0.5362
        pink.b6 = white * 0.115926
        return value * 0.11
    }

    // MARK: The sounds

    /// Soft noise whose pitch and loudness drift slowly, like gusts.
    private mutating func windSample(_ time: Double) -> Double {
        let gust = 0.5 + 0.5 * sin(2 * .pi * 0.11 * time) * (0.6 + 0.4 * sin(2 * .pi * 0.043 * time))
        let cutoff = 0.02 + 0.13 * gust
        lowpassA += cutoff * (pinkStep(white()) - lowpassA)
        lowpassB += cutoff * 0.8 * (lowpassA - lowpassB)
        return 2 * (0.25 + 0.75 * gust) * lowpassB
    }

    /// Waves: a hiss that swells and fades about every ten seconds, over a low rumble.
    private mutating func seaSample(_ time: Double) -> Double {
        let swell = pow(0.5 + 0.5 * sin(2 * .pi * 0.085 * time), 2)
        let ripple = 0.5 + 0.5 * sin(2 * .pi * 0.21 * time + 1.3)
        let w = white()
        lowpassA += 0.08 * (w - lowpassA)
        let rumble = brownStep(w)
        return (0.55 * swell * (0.7 + 0.3 * ripple)) * lowpassA * 2.2 + 1.4 * rumble
    }

    /// A broad, steady roar: pink noise with some of the high end on top, breathing very slightly.
    private mutating func waterfallSample(_ time: Double) -> Double {
        let w = white()
        let highs = w - previousWhite   // a crude high-pass
        previousWhite = w
        let breathing = 1 + 0.08 * sin(2 * .pi * 0.3 * time)
        return breathing * (0.9 * pinkStep(w) + 0.07 * highs)
    }

    /// A hiss with many tiny drops on top of it.
    private mutating func rainSample() -> Double {
        let w = white()
        let hiss = (w - previousWhite) * 0.05
        previousWhite = w
        if (Double(state & 0xFFFF) / 65_535) < 0.0007, let slot = droplets.firstIndex(where: { $0 < 0.02 }) {
            droplets[slot] = 0.25 + 0.55 * (Double((state >> 16) & 0xFF) / 255)
        }
        var drops = 0.0
        for index in droplets.indices {
            drops += droplets[index] * white() * 0.5
            droplets[index] *= 0.9965
        }
        lowpassA += 0.25 * (pinkStep(w) - lowpassA)
        return hiss + drops + 0.55 * lowpassA
    }
}
