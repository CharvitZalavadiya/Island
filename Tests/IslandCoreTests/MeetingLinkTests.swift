import Testing
import Foundation
@testable import IslandCore

private func find(url: String? = nil, location: String? = nil, notes: String? = nil) -> MeetingLink? {
    MeetingLink.find(url: url.flatMap(URL.init(string:)), location: location, notes: notes)
}

@Test func googleMeetInTheNotes() {
    let link = find(notes: "Agenda below.\n\nJoin with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial +1 555 0100")
    #expect(link?.provider == "Google Meet" && link?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
}

@Test func zoomInTheLocation() {
    let link = find(location: "https://acme.zoom.us/j/123456789?pwd=abc")
    #expect(link?.provider == "Zoom" && link?.url.host == "acme.zoom.us")
}

@Test func teamsInTheNotesEvenWhenWrappedInAnOutlookSafeLink() {
    let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"
    let wrapped = "https://nam06.safelinks.protection.outlook.com/?url=\(teams.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)&data=x"
    let link = find(location: "Microsoft Teams Meeting", notes: "Click here to join the meeting <\(wrapped)>")
    #expect(link?.provider == "Microsoft Teams")
    #expect(link?.url.host == "teams.microsoft.com")
}

@Test func theEventsOwnLinkCountsAndAKnownServiceBeatsAnUnknownOne() {
    #expect(find(url: "https://calls.example.org/room/42")?.provider == "Meeting")
    let both = find(url: "https://calls.example.org/room/42", notes: "backup: https://meet.google.com/abc-defg-hij")
    #expect(both?.provider == "Google Meet")
}

@Test func otherServicesAreRecognised() {
    #expect(find(notes: "https://acme.webex.com/meet/jane")?.provider == "Webex")
    #expect(find(notes: "https://whereby.com/standup")?.provider == "Whereby")
    #expect(find(notes: "https://meet.jit.si/DailySync")?.provider == "Jitsi")
    #expect(find(notes: "https://join.skype.com/AbCdEf")?.provider == "Skype")
    #expect(find(notes: "https://app.slack.com/huddle/T1/C2")?.provider == "Slack Huddle")
}

@Test func ordinaryLinksAndPlaceNamesAreNotMeetings() {
    #expect(find(location: "Room 4, 2nd floor") == nil)
    #expect(find(notes: "Docs: https://example.com/join-our-newsletter and https://zoom.us/pricing") == nil)  // notes need a known service
    #expect(find(location: "mailto:jane@example.com") == nil)
    #expect(find() == nil)
}

@Test func aLocationLinkThatLooksLikeACallIsAMeeting() {
    #expect(find(location: "https://video.acme.dev/standup")?.provider == "Meeting")
    #expect(find(location: "https://acme.dev/menu") == nil)
}
