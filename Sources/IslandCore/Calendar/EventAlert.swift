import Foundation

/// What the island announces shortly before an event starts.
public struct EventAlert: Equatable, Sendable {
    public let eventID: String
    public let title: String
    public let start: Date
    /// The calendar's colour as 0xRRGGBB, if it has one.
    public let colorHex: UInt32?
    /// How to join, when the event is an online meeting: the banner then has a Join button.
    public let meeting: MeetingLink?

    public init(eventID: String, title: String, start: Date, colorHex: UInt32?, meeting: MeetingLink? = nil) {
        self.eventID = eventID
        self.title = title
        self.start = start
        self.colorHex = colorHex
        self.meeting = meeting
    }
}
