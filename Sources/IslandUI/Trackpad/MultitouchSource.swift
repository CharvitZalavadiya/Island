import CoreFoundation
import Foundation
import IslandCore

/// The size of the trackpad that is being read.
struct TrackpadDevice: Equatable, Sendable {
    var widthMM: Double
    var heightMM: Double
    var count: Int
}

enum TouchSourceError: Error, Equatable {
    /// No trackpad was found (a Mac mini with no Magic Trackpad, say).
    case noTrackpad
    /// macOS did not give the touches (the message says why, in words for the person using Island).
    case unavailable(String)
}

/// Where the touches on the trackpad come from.
protocol TouchSource: AnyObject {
    /// Starts reading. `handler` is called on a background thread for every frame, a hundred or so times a second while a
    /// finger is on the pad.
    func start(_ handler: @escaping @Sendable (TrackpadFrame) -> Void) -> Result<TrackpadDevice, TouchSourceError>
    func stop()
}

/// Reads where fingers are on the trackpad from the private MultitouchSupport library that macOS itself uses (the same one
/// BetterTouchTool and similar apps use). It is not a public API, so a future macOS can change it; if the library or a function
/// is not there, `start` says so instead of crashing, and each frame is checked before it is used.
///
/// A frame hands over an array of 96-byte records; the ones used here: the finger's number at byte 16, its state at byte 20
/// (3 or 4 is touching), and its place on the pad, 0 to 1 from the left and from the bottom, as two floats at bytes 32 and 36.
final class MultitouchSource: TouchSource, @unchecked Sendable {
    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias StartDevice = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias StopDevice = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias Dimensions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    private static let recordSize = 96
    private static let touching: Set<Int32> = [3, 4]

    // The library calls back a plain C function with no room for a reference, so what it needs lives here.
    private struct Shared {
        var handler: (@Sendable (TrackpadFrame) -> Void)?
        var sizes: [UInt: (width: Double, height: Double)] = [:]
    }
    private static let lock = NSLock()
    private nonisolated(unsafe) static var shared = Shared()

    private static let callback: Callback = { device, records, count, _, _ in
        guard let device, count >= 0, count <= 32 else { return 0 }
        lock.lock()
        let handler = shared.handler
        let size = shared.sizes[UInt(bitPattern: device)]
        lock.unlock()
        guard let handler, let size else { return 0 }

        var touches: [TrackpadTouch] = []
        if let records, count > 0 {
            for index in 0..<Int(count) {
                let record = records + index * recordSize
                let x = Double(record.load(fromByteOffset: 32, as: Float.self))
                let y = Double(record.load(fromByteOffset: 36, as: Float.self))
                // A frame that does not look like a place on the pad is not used (macOS may have changed the layout).
                guard x.isFinite, y.isFinite, x > -0.1, x < 1.1, y > -0.1, y < 1.1 else { continue }
                touches.append(
                    TrackpadTouch(
                        id: Int(record.load(fromByteOffset: 16, as: Int32.self)), x: min(max(x, 0), 1), y: min(max(y, 0), 1),
                        isDown: touching.contains(record.load(fromByteOffset: 20, as: Int32.self))))
            }
        }
        handler(TrackpadFrame(touches: touches, widthMM: size.width, heightMM: size.height))
        return 0
    }

    private var library: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var running: [UnsafeMutableRawPointer] = []
    private var register: Register?
    private var unregister: Register?
    private var stopDevice: StopDevice?

    func start(_ handler: @escaping @Sendable (TrackpadFrame) -> Void) -> Result<TrackpadDevice, TouchSourceError> {
        stop()
        guard let library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            return .failure(.unavailable("macOS did not let Island read the trackpad."))
        }
        self.library = library
        func symbol<T>(_ name: String, _ type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        guard let createList = symbol("MTDeviceCreateList", CreateList.self),
            let register = symbol("MTRegisterContactFrameCallback", Register.self),
            let unregister = symbol("MTUnregisterContactFrameCallback", Register.self),
            let startDevice = symbol("MTDeviceStart", StartDevice.self),
            let stopDevice = symbol("MTDeviceStop", StopDevice.self),
            let dimensions = symbol("MTDeviceGetSensorSurfaceDimensions", Dimensions.self)
        else {
            return .failure(.unavailable("This version of macOS reads the trackpad differently, so the edge gestures cannot work yet."))
        }
        self.register = register
        self.unregister = unregister
        self.stopDevice = stopDevice

        guard let list = createList()?.takeRetainedValue() else { return .failure(.noTrackpad) }
        var sizes: [UInt: (width: Double, height: Double)] = [:]
        var devices: [UnsafeMutableRawPointer] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            var width: Int32 = 0, height: Int32 = 0
            guard dimensions(device, &width, &height) == 0 else { continue }
            // A trackpad, not a Magic Mouse: its surface is more than 8 cm by 5 cm. Sizes come in hundredths of a millimetre.
            guard width >= 8000, height >= 5000 else { continue }
            sizes[UInt(bitPattern: device)] = (Double(width) / 100, Double(height) / 100)
            devices.append(device)
        }
        guard let first = devices.first, let size = sizes[UInt(bitPattern: first)] else { return .failure(.noTrackpad) }

        Self.lock.lock()
        Self.shared = Shared(handler: handler, sizes: sizes)
        Self.lock.unlock()
        deviceList = list
        for device in devices {
            register(device, Self.callback)
            _ = startDevice(device, 0)
        }
        running = devices
        return .success(TrackpadDevice(widthMM: size.width, heightMM: size.height, count: devices.count))
    }

    func stop() {
        for device in running {
            unregister?(device, Self.callback)
            _ = stopDevice?(device)
        }
        running = []
        Self.lock.lock()
        Self.shared = Shared()
        Self.lock.unlock()
        deviceList = nil
    }

    deinit { stop() }
}
