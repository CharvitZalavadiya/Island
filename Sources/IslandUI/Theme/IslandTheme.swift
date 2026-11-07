import SwiftUI

/// Island is black, and each feature has its own colour so the tabs read apart at a glance.
enum IslandTheme {
    /// Keep awake: the warm amber of a cup of coffee.
    static let keepAwake = Color(hex: 0xFACC15)
    /// Pomodoro and the timer.
    static let focus = Color(hex: 0xFB923C)
    static let danger = Color(hex: 0xF87171)
    /// Clipboard: purple chrome, with a colour for each little action.
    static let clipboard = Color(hex: 0xA78BFA)
    static let pin = Color(hex: 0xFACC15)
    static let link = Color(hex: 0x60A5FA)
    static let scan = Color(hex: 0x2DD4BF)
    static let mail = Color(hex: 0x34D399)
    static let swatch = Color(hex: 0xF472B6)
    /// The Tools tab.
    static let tools = Color(hex: 0x818CF8)
    /// The sound mixer's sliders in the Stats tab.
    static let volume = Color(hex: 0xFB7185)
    /// The background sound's controls.
    static let ambient = Color(hex: 0x2DD4BF)
    /// Tasks: a fresh green for ticking things off.
    static let tasks = Color(hex: 0x4ADE80)
    /// Todoist's own red, for its connect card.
    static let todoist = Color(hex: 0xE44332)
    /// The GitHub tab (the purple GitHub uses for pull requests).
    static let github = Color(hex: 0xA371F7)
    /// Stats: a colour for each reading.
    static let statCPU = Color(hex: 0x34D399)
    static let statMemory = Color(hex: 0xA78BFA)
    static let download = Color(hex: 0x22D3EE)
    static let upload = Color(hex: 0xFB923C)
    static let speedTest = Color(hex: 0x38BDF8)
    /// The storage gauge runs from green (empty) through orange to red (full).
    static let storageLow = Color(hex: 0x34D399)
    static let storageMid = Color(hex: 0xFB923C)
    static let storageHigh = Color(hex: 0xEF4444)

    static let accent = Color(hex: 0x22D3EE)
    static let accentSoft = accent.opacity(0.25)
    /// Saturday and Sunday in the calendar.
    static let weekend = Color(hex: 0xF87171)
    /// Today's circle in the calendar, and the dots under days that have events.
    static let calendarToday = accent
}
