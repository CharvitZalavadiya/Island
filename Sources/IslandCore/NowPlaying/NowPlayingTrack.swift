import Foundation

/// What the Mac is playing right now (a song, a video, a podcast), as the system's Now Playing reports it.
public struct NowPlayingTrack: Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    /// The length in seconds, or nil for something with no length (a live stream).
    public var duration: TimeInterval?
    /// Seconds played at `timestamp`.
    public var elapsed: TimeInterval
    /// When `elapsed` was true.
    public var timestamp: Date
    public var rate: Double
    public var isPlaying: Bool
    /// The program playing it, when the system says which.
    public var processID: Int32?
    /// What the playing app lets Island do. A single YouTube video, for one, has no next or previous track, and a live
    /// stream cannot be moved around in.
    public var canNext: Bool
    public var canPrevious: Bool
    public var canSeek: Bool

    public init(
        title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval? = nil,
        elapsed: TimeInterval = 0, timestamp: Date = Date(), rate: Double = 1, isPlaying: Bool = true,
        processID: Int32? = nil, canNext: Bool = true, canPrevious: Bool = true, canSeek: Bool = true
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.rate = rate
        self.isPlaying = isPlaying
        self.processID = processID
        self.canNext = canNext
        self.canPrevious = canPrevious
        self.canSeek = canSeek
    }

    /// Whether the position can be changed: the app allows it and the track has a length.
    public var isSeekable: Bool { canSeek && (duration ?? 0) > 0 }

    /// How far in the track is at `date`. The system only reports the position now and then; while playing it keeps
    /// moving, so the position is worked out from the last report. Never negative and never past the end.
    public func elapsed(at date: Date) -> TimeInterval {
        var position = elapsed
        if isPlaying, rate > 0 { position += max(0, date.timeIntervalSince(timestamp)) * rate }
        if let duration { position = min(position, duration) }
        return max(position, 0)
    }

    /// How much of the track has played, 0 to 1; nil when the track has no length.
    public func fraction(at date: Date) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(elapsed(at: date) / duration, 0), 1)
    }

    /// The track after the position was moved to `seconds` (kept inside the track), before the system has confirmed it.
    public func seeked(to seconds: TimeInterval, at date: Date) -> NowPlayingTrack {
        var copy = self
        copy.elapsed = min(max(seconds, 0), duration ?? .infinity)
        copy.timestamp = date
        return copy
    }

    /// This track after play/pause was pressed, before the system has confirmed it: the position is fixed at `date`.
    public func toggled(at date: Date) -> NowPlayingTrack {
        var copy = self
        copy.elapsed = elapsed(at: date)
        copy.timestamp = date
        copy.isPlaying.toggle()
        copy.rate = copy.isPlaying ? max(rate, 1) : 0
        return copy
    }
}

/// The keys of the player, as the numbers the system's media commands use.
public enum NowPlayingCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

/// One report from the helper that watches Now Playing.
public enum NowPlayingReading: Equatable, Sendable {
    case nothing
    case track(NowPlayingTrack)
    /// The system does not answer the Now Playing questions at all.
    case unsupported
}

public enum NowPlayingParser {
    /// Reads one line of the helper's output (a JSON object). Anything that is not a JSON object gives nil.
    public static func parse(_ line: String, now: Date = Date()) -> NowPlayingReading? {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if object["unsupported"] as? Bool == true { return .unsupported }
        guard let title = object["title"] as? String, !title.isEmpty else { return .nothing }

        let rate = (object["rate"] as? Double) ?? 0
        let playing = (object["playing"] as? Bool) ?? (rate > 0)
        let stamp = (object["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? now
        return .track(NowPlayingTrack(
            title: title,
            artist: nonEmpty(object["artist"] as? String),
            album: nonEmpty(object["album"] as? String),
            duration: (object["duration"] as? Double).flatMap { $0 > 0 ? $0 : nil },
            elapsed: max((object["elapsed"] as? Double) ?? 0, 0),
            timestamp: stamp,
            rate: rate,
            isPlaying: playing,
            processID: (object["pid"] as? Int).map { Int32(truncatingIfNeeded: $0) },
            // Unknown (the helper could not ask) counts as allowed.
            canNext: (object["canNext"] as? Bool) ?? true,
            canPrevious: (object["canPrevious"] as? Bool) ?? true,
            canSeek: (object["canSeek"] as? Bool) ?? true))
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

public enum NowPlayingFormat {
    /// "3:12", or "1:02:03" once it passes an hour.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
