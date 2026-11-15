import ApplicationServices
import Foundation

/// A window that may be able to fill the screen. The real one is an Accessibility element; tests use a stand-in.
protocol FullScreenWindow {
    /// Whether it fills the screen now; nil when the window does not say.
    var isFullScreen: Bool? { get }
    var canChangeFullScreen: Bool { get }
    /// Asks the window to fill the screen (or to go back); false if the app refused.
    func setFullScreen(_ on: Bool) -> Bool
}

enum FullScreenToggle {
    /// Puts the window in full screen, or, when it is in full screen already, brings it back.
    static func toggle(_ window: some FullScreenWindow) -> TapActionResult {
        guard window.canChangeFullScreen else { return .unavailable("This window can't go full screen") }
        let goingIn = window.isFullScreen != true
        return window.setFullScreen(goingIn) ? .done : .unavailable("The app didn't go full screen")
    }
}

/// A window of another app, reached through the Accessibility interface (the "AXFullScreen" attribute that every standard window
/// has: it is how the green button of the window works). Needs Accessibility permission.
struct AccessibilityWindow: FullScreenWindow {
    let element: AXUIElement
    private static let attribute = "AXFullScreen" as CFString
    /// An app that does not answer must not hold Island up for long.
    private static let timeout: Float = 1.5

    var isFullScreen: Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, Self.attribute, &value) == .success else { return nil }
        return value as? Bool
    }

    var canChangeFullScreen: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, Self.attribute, &settable) == .success && settable.boolValue
    }

    func setFullScreen(_ on: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, Self.attribute, (on ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef) == .success
    }

    /// The window the person is working in: the one with the keyboard focus, else the app's main window, else its first.
    static func window(ofProcess pid: pid_t) -> AccessibilityWindow? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, name as CFString, &value) == .success, let value,
                CFGetTypeID(value) == AXUIElementGetTypeID()
            {
                return make(unsafeDowncast(value, to: AXUIElement.self))
            }
        }
        var list: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) == .success,
            let windows = list as? [AXUIElement], let first = windows.first
        {
            return make(first)
        }
        return nil
    }

    private static func make(_ element: AXUIElement) -> AccessibilityWindow {
        AXUIElementSetMessagingTimeout(element, timeout)
        return AccessibilityWindow(element: element)
    }
}
