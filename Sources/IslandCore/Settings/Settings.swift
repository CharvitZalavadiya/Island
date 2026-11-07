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
    public var cameraMirrored = true
    /// Island makes a short sound when the Mac locks (or the screen saver starts) and when it unlocks.
    public var lockSounds = true
    /// The background sound on the Focus tab and how loud it plays (0 to 1).
    public var ambientSound = AmbientSound.rain.rawValue
    public var ambientVolume = 0.5
    /// While music or a video plays, the minimal view (the wings beside the notch) shows the app's icon with the track's
    /// progress, and a little animated equalizer.
    public var mediaInMinimalView = true

    public static let focusMinutesRange = 1...180
    public static let shortBreakMinutesRange = 1...60
    public static let longBreakMinutesRange = 1...120

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hoverOpens, collapseDelay, mascotID, shuffleMascots, focusMinutes, shortBreakMinutes, longBreakMinutes
        case longBreakEvery, autoChain, launchAtLogin, tabOrder, cameraMirrored, lockSounds, ambientSound, ambientVolume
        case mediaInMinimalView
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
        cameraMirrored = try values.decodeIfPresent(Bool.self, forKey: .cameraMirrored) ?? cameraMirrored
        lockSounds = try values.decodeIfPresent(Bool.self, forKey: .lockSounds) ?? lockSounds
        ambientSound = try values.decodeIfPresent(String.self, forKey: .ambientSound) ?? ambientSound
        ambientVolume = Self.clamp(try values.decodeIfPresent(Double.self, forKey: .ambientVolume) ?? ambientVolume, 0...1)
        mediaInMinimalView = try values.decodeIfPresent(Bool.self, forKey: .mediaInMinimalView) ?? mediaInMinimalView
    }

    private static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
