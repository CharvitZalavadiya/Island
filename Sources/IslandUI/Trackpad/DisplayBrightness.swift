import CoreGraphics
import Foundation

/// The brightness of the Mac's own screen.
protocol BrightnessControlling: AnyObject {
    /// 0 to 1, or nil when there is no built-in display or it cannot be read.
    func current() -> Float?
    func set(_ value: Float)
}

/// macOS has no public way to change the brightness of the built-in display, so this uses the private DisplayServices library
/// that System Settings itself uses (as MonitorControl and similar apps do). If a future macOS changes it, `current()` returns
/// nil and the brightness edge says so instead of doing anything. External monitors are not handled.
final class DisplayServicesBrightness: BrightnessControlling {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Put = @convention(c) (UInt32, Float) -> Int32

    private let get: Get?
    private let put: Put?

    init() {
        let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        get = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
        put = library.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Put.self) }
    }

    /// The built-in display, if the Mac has one that is on.
    private var builtIn: UInt32? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func current() -> Float? {
        guard let get, let display = builtIn else { return nil }
        var value: Float = 0
        return get(display, &value) == 0 ? value : nil
    }

    func set(_ value: Float) {
        guard let put, let display = builtIn else { return }
        _ = put(display, min(max(value, 0), 1))
    }
}
