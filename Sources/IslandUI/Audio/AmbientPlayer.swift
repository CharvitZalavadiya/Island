import AVFoundation
import Observation
import os
import IslandCore

/// Plays the background sound chosen on the Focus tab. The audio is made on the fly by `AmbientGenerator`; the audio
/// engine only exists while something is playing, so a paused Island uses nothing.
@Observable
@MainActor
final class AmbientPlayer {
    private(set) var isPlaying = false
    private(set) var sound: AmbientSound
    private(set) var volume: Double

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    /// What the audio thread reads: the generator, and the loudness it is fading towards.
    @ObservationIgnored private let shared: OSAllocatedUnfairLock<RenderState>

    struct RenderState {
        var generator: AmbientGenerator
        var targetGain: Float = 0
        var gain: Float = 0
    }

    init(settings: SettingsStore) {
        self.settings = settings
        let stored = settings.settings
        let initial = AmbientSound(rawValue: stored.ambientSound) ?? .rain
        sound = initial
        volume = stored.ambientVolume
        shared = OSAllocatedUnfairLock(initialState: RenderState(generator: AmbientGenerator(sound: initial)))
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        stopTask?.cancel()
        stopTask = nil
        guard !isPlaying else { return }
        if engine == nil {
            guard let created = makeEngine() else { return }
            engine = created
        }
        guard let engine else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            self.engine = nil
            return
        }
        let target = Self.gain(for: volume)
        shared.withLock { $0.targetGain = target }
        isPlaying = true
    }

    /// Fades out, then shuts the engine down.
    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        shared.withLock { $0.targetGain = 0 }
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            self.engine?.stop()
            self.engine = nil
        }
    }

    func select(_ newSound: AmbientSound) {
        guard newSound != sound else { return }
        sound = newSound
        settings.update { $0.ambientSound = newSound.rawValue }
        // The new sound starts from silence and fades in.
        shared.withLock {
            $0.generator = AmbientGenerator(sound: newSound)
            $0.gain = 0
        }
    }

    func setVolume(_ newVolume: Double) {
        volume = min(max(newVolume, 0), 1)
        settings.update { $0.ambientVolume = volume }
        if isPlaying {
            let target = Self.gain(for: volume)
            shared.withLock { $0.targetGain = target }
        }
    }

    /// Volume feels even when the slider drives the amplitude through a curve rather than straight.
    nonisolated static func gain(for volume: Double) -> Float {
        Float(pow(min(max(volume, 0), 1), 2) * 0.9)
    }

    // MARK: Engine

    private func makeEngine() -> AVAudioEngine? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false) else {
            return nil
        }
        let shared = self.shared
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            shared.withLock { state in
                for frame in 0..<Int(frameCount) {
                    // About 40 ms to move towards the target loudness: no clicks when starting, stopping or sliding.
                    state.gain += (state.targetGain - state.gain) * 0.0006
                    let value = state.generator.next() * state.gain
                    for buffer in buffers {
                        buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                    }
                }
            }
            return noErr
        }
        let engine = AVAudioEngine()
        engine.attach(node)
        do {
            try engine.connectNode(node, to: engine.mainMixerNode, format: format)
        } catch {
            return nil
        }
        return engine
    }
}
