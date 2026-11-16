import Foundation
import ObjectiveC

/// The backlight under the keys of the Mac's own keyboard.
protocol KeyboardBacklightControlling: AnyObject {
    /// 0 to 1, or nil when this Mac has no keyboard backlight to change (or macOS no longer offers a way to).
    func current() -> Float?
    /// Sets the level. While a finger is still sliding `final` is false; when the slide ends it is true, which is when macOS keeps
    /// the level (as when a slider is let go).
    func set(_ value: Float, final: Bool)
}

/// macOS has no public way to change the keyboard backlight, so this uses the private CoreBrightness library that Control Center
/// and the brightness keys use (as keyboard-light utilities do). It is loaded the first time the gesture is used, not at launch. If a
/// future macOS changes it, `current()` returns nil and the edge says so instead of doing anything.
final class CoreBrightnessKeyboard: KeyboardBacklightControlling {
    private typealias IDs = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias Level = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Flag = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias Put = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
    private typealias PutPlain = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private lazy var client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil else { return nil }
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()
    /// The keyboard found by the last `current()`.
    private var keyboard: UInt64?

    private func method<T>(_ name: String, as type: T.Type) -> (call: T, selector: Selector)? {
        guard let client else { return nil }
        let selector = NSSelectorFromString(name)
        guard client.responds(to: selector), let implementation = client.method(for: selector) else { return nil }
        return (unsafeBitCast(implementation, to: type), selector)
    }

    /// The Mac's own keyboard (a Mac can have more than one backlit keyboard): the built-in one, else the first.
    private func findKeyboard() -> UInt64? {
        guard let client, let list = method("copyKeyboardBacklightIDs", as: IDs.self) else { return nil }
        let ids = (list.call(client, list.selector)?.takeRetainedValue() as? [NSNumber])?.map(\.uint64Value) ?? []
        if let isBuiltIn = method("isKeyboardBuiltIn:", as: Flag.self), let own = ids.first(where: { isBuiltIn.call(client, isBuiltIn.selector, $0) }) {
            return own
        }
        return ids.first
    }

    func current() -> Float? {
        keyboard = findKeyboard()
        guard let client, let id = keyboard, let read = method("brightnessForKeyboard:", as: Level.self) else { return nil }
        return read.call(client, read.selector, id)
    }

    func set(_ value: Float, final: Bool) {
        guard let client, let id = keyboard ?? findKeyboard() else { return }
        let level = min(max(value, 0), 1)
        if let put = method("setBrightness:fadeSpeed:commit:forKeyboard:", as: Put.self) {
            _ = put.call(client, put.selector, level, 0, final, id)
        } else if let put = method("setBrightness:forKeyboard:", as: PutPlain.self) {
            _ = put.call(client, put.selector, level, id)
        }
    }
}
