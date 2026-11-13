import Foundation

public struct Settings: Codable, Equatable {
    public var hoverOpens = true
    public var collapseDelay: TimeInterval = 0.4
    public var mascotID = "ghost"
    public var shuffleMascots = false
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var longBreakEvery = 4
    public var autoChain = false
    public var launchAtLogin = false
    /// Tab ids in the user's order. Empty means the default order; ids that are missing or unknown are tolerated.
    public var tabOrder: [String] = []
    /// Ids of the tabs switched off in Settings: the island does not show them. Empty means every tab is on, and a tab that is
    /// not mentioned here is on, so a tab added by a later version appears by itself.
    public var hiddenTabs: [String] = []
    public var cameraMirrored = true
    /// Island makes a short sound when the Mac locks (or the screen saver starts) and when it unlocks.
    public var lockSounds = true
    /// The background sound on the Focus tab and how loud it plays (0 to 1).
    public var ambientSound = AmbientSound.rain.rawValue
    public var ambientVolume = 0.5
    /// While music or a video plays, the minimal view (the wings beside the notch) shows the app's icon with the track's
    /// progress, and a little animated equalizer.
    public var mediaInMinimalView = true
    /// Edge gestures on the trackpad (the Trackpad tool). On from the start, and the person can switch them off: while one is going
    /// on the pointer is held still.
    public var trackpadEnabled = true
    /// What sliding one finger along each edge does, by edge name ("left", "right", "top", "bottom") to action name ("off",
    /// "volume", "brightness", "seek"). An edge that is missing or has an unknown action keeps its default.
    public var trackpadActions: [String: String] = [:]
    /// The edges whose direction is turned round (names, as above).
    public var trackpadReversedEdges: [String] = []
    /// How wide the strip along each edge is, in millimetres.
    public var trackpadEdgeMM = TrackpadDefaults.edgeMM
    /// How far one slide goes: 1 means a slide along a whole edge covers the whole range.
    public var trackpadSensitivity = TrackpadDefaults.sensitivity
    /// Tapping the trackpad with three or four fingers, twice or three times, does what the person chose for that tap. On from the
    /// start, and the person can switch it off; nothing is assigned until they choose.
    public var trackpadTapsEnabled = true
    /// What each tap does, by tap ("3-2" is three fingers, two taps) to action name. A tap that is missing does nothing.
    public var trackpadTapActions: [String: String] = [:]
    /// For the "open an app" action: where the app is, by tap.
    public var trackpadTapApps: [String: String] = [:]
    /// For the "run a Shortcut" action: the Shortcut's name, by tap.
    public var trackpadTapShortcuts: [String: String] = [:]
    /// Which tasks the Tasks tab shows: "local" (Island's own list) or "todoist".
    public var tasksSource = "local"
    /// Island looks for a newer version on GitHub now and then (at most about once a day) and says so in Settings.
    public var checkForUpdates = true
    /// When Island last asked GitHub for the newest version.
    public var lastUpdateCheck: Date?

    public static let focusMinutesRange = 1...180
    public static let shortBreakMinutesRange = 1...60
    public static let longBreakMinutesRange = 1...120

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hoverOpens, collapseDelay, mascotID, shuffleMascots, focusMinutes, shortBreakMinutes, longBreakMinutes
        case longBreakEvery, autoChain, launchAtLogin, tabOrder, hiddenTabs, cameraMirrored, lockSounds, ambientSound, ambientVolume
        case mediaInMinimalView, tasksSource, checkForUpdates, lastUpdateCheck
        case trackpadEnabled, trackpadActions, trackpadReversedEdges, trackpadEdgeMM, trackpadSensitivity
        case trackpadTapsEnabled, trackpadTapActions, trackpadTapApps, trackpadTapShortcuts
    }

    /// Every key is optional, so a settings file written by an older Island (which had fewer keys) keeps the user's
    /// values instead of being thrown away, and a value outside its sensible range is pulled back inside it.
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hoverOpens = try values.decodeIfPresent(Bool.self, forKey: .hoverOpens) ?? hoverOpens
        collapseDelay = Self.clamp(
            try values.decodeIfPresent(TimeInterval.self, forKey: .collapseDelay) ?? collapseDelay, 0.1...2)
        mascotID = try values.decodeIfPresent(String.self, forKey: .mascotID) ?? mascotID
        shuffleMascots = try values.decodeIfPresent(Bool.self, forKey: .shuffleMascots) ?? shuffleMascots
        focusMinutes = Self.clamp(
            try values.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? focusMinutes, Self.focusMinutesRange)
        shortBreakMinutes = Self.clamp(
            try values.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? shortBreakMinutes, Self.shortBreakMinutesRange)
        longBreakMinutes = Self.clamp(
            try values.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? longBreakMinutes, Self.longBreakMinutesRange)
        longBreakEvery = Self.clamp(try values.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? longBreakEvery, 2...10)
        autoChain = try values.decodeIfPresent(Bool.self, forKey: .autoChain) ?? autoChain
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        tabOrder = try values.decodeIfPresent([String].self, forKey: .tabOrder) ?? tabOrder
        hiddenTabs = try values.decodeIfPresent([String].self, forKey: .hiddenTabs) ?? hiddenTabs
        cameraMirrored = try values.decodeIfPresent(Bool.self, forKey: .cameraMirrored) ?? cameraMirrored
        lockSounds = try values.decodeIfPresent(Bool.self, forKey: .lockSounds) ?? lockSounds
        ambientSound = try values.decodeIfPresent(String.self, forKey: .ambientSound) ?? ambientSound
        ambientVolume = Self.clamp(try values.decodeIfPresent(Double.self, forKey: .ambientVolume) ?? ambientVolume, 0...1)
        mediaInMinimalView = try values.decodeIfPresent(Bool.self, forKey: .mediaInMinimalView) ?? mediaInMinimalView
        tasksSource = try values.decodeIfPresent(String.self, forKey: .tasksSource) ?? tasksSource
        checkForUpdates = try values.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? checkForUpdates
        lastUpdateCheck = try values.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        trackpadEnabled = try values.decodeIfPresent(Bool.self, forKey: .trackpadEnabled) ?? trackpadEnabled
        trackpadActions = try values.decodeIfPresent([String: String].self, forKey: .trackpadActions) ?? trackpadActions
        trackpadReversedEdges = try values.decodeIfPresent([String].self, forKey: .trackpadReversedEdges) ?? trackpadReversedEdges
        trackpadEdgeMM = Self.clamp(
            try values.decodeIfPresent(Double.self, forKey: .trackpadEdgeMM) ?? trackpadEdgeMM, TrackpadDefaults.edgeMMRange)
        trackpadSensitivity = Self.clamp(
            try values.decodeIfPresent(Double.self, forKey: .trackpadSensitivity) ?? trackpadSensitivity, TrackpadDefaults.sensitivityRange)
        trackpadTapsEnabled = try values.decodeIfPresent(Bool.self, forKey: .trackpadTapsEnabled) ?? trackpadTapsEnabled
        trackpadTapActions = try values.decodeIfPresent([String: String].self, forKey: .trackpadTapActions) ?? trackpadTapActions
        trackpadTapApps = try values.decodeIfPresent([String: String].self, forKey: .trackpadTapApps) ?? trackpadTapApps
        trackpadTapShortcuts = try values.decodeIfPresent([String: String].self, forKey: .trackpadTapShortcuts) ?? trackpadTapShortcuts
    }

    /// What sliding along `edge` does: the saved choice, or the default for that edge.
    public func trackpadAction(for edge: TrackpadEdge) -> TrackpadAction {
        trackpadActions[edge.rawValue].flatMap(TrackpadAction.init(rawValue:)) ?? TrackpadDefaults.actions[edge] ?? .off
    }

    public func trackpadIsReversed(_ edge: TrackpadEdge) -> Bool { trackpadReversedEdges.contains(edge.rawValue) }

    /// The edges that do something (not "off").
    public var trackpadActiveEdges: Set<TrackpadEdge> {
        Set(TrackpadEdge.allCases.filter { trackpadAction(for: $0) != .off })
    }

    /// What this tap does: the saved choice, or nothing.
    public func trackpadTapAction(for trigger: TrackpadTapTrigger) -> TrackpadTapAction {
        trackpadTapActions[trigger.id].flatMap(TrackpadTapAction.init(rawValue:)) ?? .none
    }

    /// The app chosen for this tap (for the "open an app" action).
    public func trackpadTapApp(for trigger: TrackpadTapTrigger) -> String? {
        trackpadTapApps[trigger.id].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The Shortcut chosen for this tap (for the "run a Shortcut" action).
    public func trackpadTapShortcut(for trigger: TrackpadTapTrigger) -> String? {
        trackpadTapShortcuts[trigger.id].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The taps that do something right now: none while tapping is switched off.
    public var trackpadWantedTaps: Set<TrackpadTapTrigger> {
        trackpadTapsEnabled ? Set(TrackpadTapTrigger.all.filter { trackpadTapAction(for: $0) != .none }) : []
    }

    private static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
