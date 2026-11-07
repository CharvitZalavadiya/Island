import AppKit
import CoreAudio
import Foundation
import IslandCore

struct AppVolumeError: Error, Equatable {
    var message: String
}

/// Something that can hold apps at a lower volume. The real one is `AppVolumeEngine`; tests use a stand-in.
@MainActor
protocol AppVolumeControlling: AnyObject {
    /// Called when the system's list of audio programs or its output device changed.
    var onSystemChange: (() -> Void)? { get set }
    /// Called when an app's volume could not be kept, so it is back to full.
    var onFailure: ((_ appID: String, _ message: String) -> Void)? { get set }
    /// Holds `app` at `volume` (below full).
    func setVolume(_ volume: Float, for app: MixerApp) -> Result<Void, AppVolumeError>
    /// Lets `appID` play at full volume again.
    func release(_ appID: String)
    /// The apps as they are now: follows an app that gained or lost audio processes.
    func refresh(apps: [MixerApp])
    func shutdown()
}

/// One app's sound, taken over and played again through `GainCopy` at a chosen volume.
///
/// macOS (14.2 and later) lets a program tap another app's audio. The tap is set to *mute* the app's own output, and a
/// private device made of the tap plus the real output plays the tapped sound again, scaled. If that playing stopped,
/// the app would be silent, which is why `AppVolumeEngine` watches every tap and removes any that stalls.
final class AppVolumeTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// Read by the audio thread, written by the main thread (a single aligned float is safe to share this way).
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// How many times the audio thread has run; the watchdog checks it keeps going up.
    private let counter = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
    private let queue = DispatchQueue(label: "com.charvit.Island.app-volume", qos: .userInteractive)
    private var stopped = false

    var callbackCount: UInt64 { counter.pointee }

    init(app: MixerApp, outputUID: String, volume: Float) throws {
        gain.initialize(to: volume)
        counter.initialize(to: 0)
        do { try build(app: app, outputUID: outputUID, volume: volume) } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    func setVolume(_ volume: Float) { gain.pointee = volume }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        gain.deallocate()
        counter.deallocate()
    }

    private func build(app: MixerApp, outputUID: String, volume: Float) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: app.processObjects)
        description.uuid = UUID()
        description.name = "Island volume for \(app.name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(description, &tapID), "start listening to \(app.name)")

        // The playing code below copies 32-bit floats; stop here if the tap is anything else.
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = CoreAudioSystem.address(kAudioTapPropertyFormat)
        try check(AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format), "read the sound format of \(app.name)")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            throw AppVolumeError(message: "\(app.name) uses a sound format Island can't turn down.")
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Island volume for \(app.name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "set up the volume control for \(app.name)")

        // The tap is the last input; anything before it is the output device's own inputs (a headset's microphone).
        var streamsAddress = CoreAudioSystem.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var streamsSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(aggregateID, &streamsAddress, 0, nil, &streamsSize), "inspect the volume control for \(app.name)")
        let inputStreams = Int(streamsSize) / MemoryLayout<AudioObjectID>.size
        guard inputStreams >= 1 else { throw AppVolumeError(message: "Island couldn't hear \(app.name).") }
        let skipped = inputStreams - 1

        let gainPointer = gain, counterPointer = counter
        var current = volume
        let block: AudioDeviceIOBlock = { _, input, _, output, _ in
            let target = gainPointer.pointee
            GainCopy.render(input: input, output: output, from: current, to: target, skippingInputBuffers: skipped)
            current = target
            counterPointer.pointee &+= 1
        }
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, block), "start the volume control for \(app.name)")
        try check(AudioDeviceStart(aggregateID, procID), "start the volume control for \(app.name)")
    }

    private func check(_ status: OSStatus, _ action: String) throws {
        guard status != noErr else { return }
        throw AppVolumeError(message: "Island couldn't \(action) (macOS error \(status)).")
    }
}

/// Keeps a set of `AppVolumeTap`s and makes sure none of them can leave an app silent.
///
/// - A tap exists only while an app is turned down; at full volume the app is untouched.
/// - Every second a watchdog checks each tap is still playing; one that stalled for three checks is removed, which
///   puts that app back at full volume at once.
/// - When the output device changes (headphones plugged in, AirPods connected) or the Mac wakes, the taps are rebuilt
///   for the new device.
/// - Quitting Island removes them all. If Island crashed, macOS removes them with the process.
@MainActor
final class AppVolumeEngine: AppVolumeControlling {
    private struct Entry {
        var app: MixerApp
        var volume: Float
        var tap: AppVolumeTap
        var lastCount: UInt64
        var stalls: Int
    }

    var onSystemChange: (() -> Void)?
    var onFailure: ((String, String) -> Void)?

    private var entries: [String: Entry] = [:]
    private var watchdog: Timer?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var wakeObserver: NSObjectProtocol?

    func setVolume(_ volume: Float, for app: MixerApp) -> Result<Void, AppVolumeError> {
        if var entry = entries[app.id], entry.app.processObjects == app.processObjects {
            entry.tap.setVolume(volume)
            entry.volume = volume
            entries[app.id] = entry
            return .success(())
        }
        remove(app.id)   // the app's processes changed: start again with the current ones
        do {
            try add(app, volume: volume)
            return .success(())
        } catch let error as AppVolumeError {
            return .failure(error)
        } catch {
            return .failure(AppVolumeError(message: "Island couldn't change \(app.name)'s volume."))
        }
    }

    func release(_ appID: String) {
        remove(appID)
    }

    func refresh(apps: [MixerApp]) {
        for (id, entry) in entries {
            guard let current = apps.first(where: { $0.id == id }) else { remove(id); continue }
            if Set(current.processObjects) != Set(entry.app.processObjects) {
                rebuild(id, with: current)
            }
        }
    }

    func shutdown() {
        for id in Array(entries.keys) { remove(id) }
    }

    // MARK: Taps

    private func add(_ app: MixerApp, volume: Float) throws {
        guard let uid = CoreAudioSystem.defaultOutputUID() else {
            throw AppVolumeError(message: "Island couldn't find the sound output.")
        }
        let tap = try AppVolumeTap(app: app, outputUID: uid, volume: volume)
        entries[app.id] = Entry(app: app, volume: volume, tap: tap, lastCount: 0, stalls: 0)
        startWatching()
    }

    private func remove(_ appID: String) {
        entries.removeValue(forKey: appID)?.tap.stop()
        if entries.isEmpty { stopWatching() }
    }

    private func rebuild(_ appID: String, with app: MixerApp? = nil) {
        guard let entry = entries[appID] else { return }
        let target = app ?? entry.app
        remove(appID)
        do { try add(target, volume: entry.volume) } catch {
            fail(appID, name: target.name, detail: (error as? AppVolumeError)?.message)
        }
    }

    private func fail(_ appID: String, name: String, detail: String? = nil) {
        remove(appID)
        onFailure?(appID, detail ?? "Island lost control of \(name)'s volume, so it is back to full.")
    }

    // MARK: Watching

    private func startWatching() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTaps() }
        }
        installListeners()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildAll() }
        }
    }

    private func stopWatching() {
        watchdog?.invalidate()
        watchdog = nil
        removeListeners()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// A tap that is playing makes its counter go up every few milliseconds.
    private func checkTaps() {
        for (id, var entry) in entries {
            let count = entry.tap.callbackCount
            entry.stalls = count == entry.lastCount ? entry.stalls + 1 : 0
            entry.lastCount = count
            entries[id] = entry
            if entry.stalls >= 3 { fail(id, name: entry.app.name) }
        }
    }

    private func rebuildAll() {
        for id in Array(entries.keys) { rebuild(id) }
    }

    private func installListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let watched: [(AudioObjectPropertySelector, Bool)] = [
            (kAudioHardwarePropertyDefaultOutputDevice, true),
            (kAudioHardwarePropertyProcessObjectList, false),
        ]
        for (selector, isDevice) in watched {
            var address = CoreAudioSystem.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if isDevice { self.rebuildAll() }
                    self.onSystemChange?()
                }
            }
            if AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    private func removeListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(system, &address, DispatchQueue.main, block)
        }
        listeners = []
    }
}
