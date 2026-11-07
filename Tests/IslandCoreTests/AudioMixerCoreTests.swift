import Testing
import CoreAudio
import Foundation
@testable import IslandCore

// MARK: Grouping

private func client(_ object: UInt32, _ path: String, playing: Bool = false, pid: Int32 = 100) -> AudioClient {
    AudioClient(processObject: object, pid: pid == 100 ? Int32(object) : pid, path: path, isPlaying: playing)
}

@Test func helpersJoinTheirAppAndOnlyAppsAreListed() {
    let apps = AudioMixerGrouping.apps(from: [
        client(1, "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
        client(2, "/Applications/Brave Browser.app/Contents/Frameworks/X.framework/Helpers/Brave Browser Helper.app/Contents/MacOS/Brave Browser Helper", playing: true),
        client(3, "/Applications/Microsoft Teams.app/Contents/MacOS/MSTeams", playing: true),
        client(4, "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", playing: true),
        client(5, "/usr/libexec/coreaudiod", playing: true),
        client(6, ""),
    ], ownPID: 999)
    #expect(apps.map(\.name) == ["Brave Browser", "Microsoft Teams"])
    #expect(apps[0].processObjects == [1, 2] && apps[0].isPlaying)   // playing because one helper is
}

@Test func islandItselfIsLeftOut() {
    let apps = AudioMixerGrouping.apps(from: [client(1, "/Applications/Island.app/Contents/MacOS/Island", playing: true, pid: 42)], ownPID: 42)
    #expect(apps.isEmpty)
}

@Test func quietAppsShowOnlyWhileTurnedDown() {
    let quiet = MixerApp(id: "/A.app", name: "A", processObjects: [1], isPlaying: false)
    let loud = MixerApp(id: "/B.app", name: "B", processObjects: [2], isPlaying: true)
    #expect(AudioMixerGrouping.visible([quiet, loud], volumes: [:]).map(\.name) == ["B"])
    #expect(AudioMixerGrouping.visible([quiet, loud], volumes: ["/A.app": 0.3]).map(\.name) == ["A", "B"])
}

// MARK: Gain copy

/// Audio buffers for a test: each entry is (channels in the buffer, samples).
private final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(_ buffers: [(channels: Int, samples: [Float])]) {
        list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        for (index, buffer) in buffers.enumerated() {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: buffer.samples.count)
            pointer.initialize(from: buffer.samples, count: buffer.samples.count)
            storage.append(pointer)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(buffer.channels), mDataByteSize: UInt32(buffer.samples.count * 4), mData: pointer)
        }
    }

    func samples(_ index: Int) -> [Float] {
        let count = Int(list[index].mDataByteSize) / 4
        return Array(UnsafeBufferPointer(start: storage[index], count: count))
    }

    deinit { storage.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }
}

@Test func halfVolumeHalvesEverySample() {
    let input = Buffers([(2, [1, -1, 0.5, -0.5])])
    let output = Buffers([(2, [9, 9, 9, 9])])
    GainCopy.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, from: 0.5, to: 0.5)
    #expect(output.samples(0) == [0.5, -0.5, 0.25, -0.25])
}

@Test func volumeMovesInAStraightLineAcrossABuffer() {
    let input = Buffers([(1, [1, 1, 1, 1, 1])])
    let output = Buffers([(1, [0, 0, 0, 0, 0])])
    GainCopy.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, from: 1, to: 0)
    #expect(output.samples(0) == [1, 0.75, 0.5, 0.25, 0])
}

@Test func oneBufferPerChannelPlaysOnAnInterleavedOutput() {
    let input = Buffers([(1, [1, 1]), (1, [-1, -1])])          // left and right in separate buffers
    let output = Buffers([(2, [0, 0, 0, 0])])                  // one interleaved stereo buffer
    GainCopy.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, from: 1, to: 1)
    #expect(output.samples(0) == [1, -1, 1, -1])
}

@Test func aMicrophoneListedBeforeTheCapturedSoundIsNeverPlayedBack() {
    let microphone = [Float](repeating: 0.9, count: 4)
    let captured: [Float] = [0.2, 0.2, 0.2, 0.2]
    let input = Buffers([(2, microphone), (2, captured)])
    let output = Buffers([(2, [0, 0, 0, 0])])
    GainCopy.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, from: 1, to: 1, skippingInputBuffers: 1)
    #expect(output.samples(0) == captured)
}

@Test func outputChannelsWithNothingToPlayAreSilenced() {
    let input = Buffers([(2, [1, 1, 1, 1])])
    let output = Buffers([(4, [7, 7, 7, 7, 7, 7, 7, 7])])      // four channels, only two to play
    GainCopy.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer, from: 1, to: 1)
    #expect(output.samples(0) == [1, 1, 0, 0, 1, 1, 0, 0])
}
