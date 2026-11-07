import CoreAudio
import Foundation

/// Copies audio from one set of buffers to another at a different volume. This is what turns an app's sound down: the
/// app's audio is captured, and played again through this at the volume chosen.
///
/// It runs on the audio thread, so it never allocates and never waits.
public enum GainCopy {
    /// Writes `input` into `output` (32-bit float samples), scaling by a volume that moves in a straight line from
    /// `start` to `end` across the buffer, so a change of volume never clicks. Buffers can be interleaved or one per
    /// channel, and need not match: a mono input plays on every output channel, and output channels with nothing to
    /// play are silenced. The first `skippingInputBuffers` input buffers are ignored: a device that is also a microphone
    /// lists its own input before the captured sound, and that must never be played back.
    public static func render(
        input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, from start: Float, to end: Float,
        skippingInputBuffers skipped: Int = 0
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let inputChannels = channelCount(inputs, skipping: skipped)
        let outputChannels = channelCount(outputs, skipping: 0)

        for channel in 0..<outputChannels {
            guard let destination = locate(outputs, channel: channel, skipping: 0) else { continue }
            // A mono input feeds every output channel; otherwise channel n plays channel n, and extra channels are silent.
            let sourceChannel = inputChannels == 1 ? 0 : channel
            guard sourceChannel < inputChannels, let source = locate(inputs, channel: sourceChannel, skipping: skipped) else {
                for frame in 0..<destination.frames { destination.samples[frame * destination.stride] = 0 }
                continue
            }
            let frames = min(source.frames, destination.frames)
            let step = frames > 1 ? (end - start) / Float(frames - 1) : 0
            for frame in 0..<frames {
                destination.samples[frame * destination.stride] =
                    source.samples[frame * source.stride] * (start + step * Float(frame))
            }
            if destination.frames > frames {
                for frame in frames..<destination.frames { destination.samples[frame * destination.stride] = 0 }
            }
        }
    }

    private static func channelCount(_ list: UnsafeMutableAudioBufferListPointer, skipping skipped: Int) -> Int {
        var total = 0
        for buffer in list.dropFirst(skipped) { total += Int(buffer.mNumberChannels) }
        return total
    }

    /// Where one channel's samples are: the first sample, the distance between samples, and how many there are.
    private static func locate(
        _ list: UnsafeMutableAudioBufferListPointer, channel: Int, skipping skipped: Int
    ) -> (samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int)? {
        var remaining = channel
        for buffer in list.dropFirst(skipped) {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let data = buffer.mData else { continue }
            if remaining < channels {
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                return (data.assumingMemoryBound(to: Float.self) + remaining, channels, frames)
            }
            remaining -= channels
        }
        return nil
    }
}
