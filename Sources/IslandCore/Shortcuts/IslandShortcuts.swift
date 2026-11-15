import Foundation

/// What a key pressed in the island can do.
public enum IslandShortcut: Equatable, Sendable {
    case focusMode, toggleMax, togglePin, openSettings
}

/// A key press, reduced to what the shortcuts care about (so they can be tried without a keyboard).
public struct KeyPress: Equatable, Sendable {
    /// The character on the key without the modifier keys, lowercased ("f", ",").
    public var key: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    /// A key held down repeats; only the first press counts.
    public var isRepeat: Bool

    public init(key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false, isRepeat: Bool = false) {
        self.key = key.lowercased()
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.isRepeat = isRepeat
    }
}

/// The island's keyboard shortcuts: F opens focus mode (and leaves it), M switches between the usual size and Max, P pins or
/// unpins, and ⌘, opens Settings. The letters are plain keys, so they only count while nothing is being typed into (a text
/// box, a web page): otherwise typing "map" in a task would pin and resize the island.
public enum IslandShortcuts {
    public static func shortcut(for press: KeyPress, isTyping: Bool) -> IslandShortcut? {
        guard !press.isRepeat else { return nil }
        // The usual Settings shortcut works everywhere, typing or not.
        if press.key == "," {
            return press.command && !press.option && !press.control && !press.shift ? .openSettings : nil
        }
        guard !isTyping, !press.command, !press.option, !press.control, !press.shift else { return nil }
        switch press.key {
        case "f": return .focusMode
        case "m": return .toggleMax
        case "p": return .togglePin
        default: return nil
        }
    }
}
