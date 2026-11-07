import Testing
import Foundation
@testable import IslandCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func aPlayingTrackMovesOnFromItsLastReport() {
    let track = NowPlayingTrack(title: "A", duration: 425, elapsed: 192, timestamp: t0, rate: 1, isPlaying: true)
    #expect(track.elapsed(at: t0.addingTimeInterval(10)) == 202)
    #expect(track.fraction(at: t0)! > 0.45 && track.fraction(at: t0)! < 0.46)
}

@Test func aPausedTrackStaysWhereItWas() {
    let track = NowPlayingTrack(title: "A", duration: 425, elapsed: 192, timestamp: t0, rate: 0, isPlaying: false)
    #expect(track.elapsed(at: t0.addingTimeInterval(60)) == 192)
}

@Test func positionNeverPassesTheEndOrGoesNegative() {
    let track = NowPlayingTrack(title: "A", duration: 100, elapsed: 95, timestamp: t0, rate: 1, isPlaying: true)
    #expect(track.elapsed(at: t0.addingTimeInterval(500)) == 100)
    #expect(track.elapsed(at: t0.addingTimeInterval(-500)) == 95)   // a clock that ran backwards
    #expect(NowPlayingTrack(title: "Live").fraction(at: t0) == nil)  // no length, no fraction
}

@Test func pressingPlayPauseFreezesThePositionThenResumes() {
    let playing = NowPlayingTrack(title: "A", duration: 300, elapsed: 10, timestamp: t0, rate: 1, isPlaying: true)
    let paused = playing.toggled(at: t0.addingTimeInterval(5))
    #expect(!paused.isPlaying)
    #expect(paused.elapsed(at: t0.addingTimeInterval(50)) == 15)
    let resumed = paused.toggled(at: t0.addingTimeInterval(50))
    #expect(resumed.isPlaying && resumed.elapsed(at: t0.addingTimeInterval(52)) == 17)
}

@Test func theParserReadsATrack() {
    let line = #"{"title":"Song","artist":"Band","duration":425.5,"elapsed":192,"rate":1,"playing":true,"timestamp":1000000,"pid":321}"#
    guard case .track(let track)? = NowPlayingParser.parse(line, now: t0) else { Issue.record("not a track"); return }
    #expect(track.title == "Song" && track.artist == "Band" && track.album == nil)
    #expect(track.duration == 425.5 && track.elapsed == 192 && track.isPlaying && track.processID == 321)
    #expect(track.timestamp == Date(timeIntervalSince1970: 1_000_000))
}

@Test func theParserReadsNothingPlayingAndJunk() {
    #expect(NowPlayingParser.parse("{}") == .nothing)
    #expect(NowPlayingParser.parse(#"{"unsupported":true}"#) == .unsupported)
    #expect(NowPlayingParser.parse("not json") == nil)
    #expect(NowPlayingParser.parse(#"{"title":"No length","rate":0}"#, now: t0).map { reading in
        if case .track(let track) = reading { return track.duration == nil && !track.isPlaying }
        return false
    } == true)
}

@Test func clockTimesRead3m12sAndOverAnHour() {
    #expect(NowPlayingFormat.clock(192) == "3:12")
    #expect(NowPlayingFormat.clock(0) == "0:00")
    #expect(NowPlayingFormat.clock(3725) == "1:02:05")
    #expect(NowPlayingFormat.clock(-4) == "0:00")
}

@Test func theParserReadsWhatTheAppAllows() {
    let single = #"{"title":"One video","duration":600,"elapsed":1,"rate":1,"canNext":false,"canPrevious":false,"canSeek":true}"#
    guard case .track(let track)? = NowPlayingParser.parse(single, now: t0) else { Issue.record("not a track"); return }
    #expect(!track.canNext && !track.canPrevious && track.canSeek && track.isSeekable)
    // The helper could not ask: assume everything works.
    guard case .track(let unknown)? = NowPlayingParser.parse(#"{"title":"X","duration":9}"#, now: t0) else { Issue.record("not a track"); return }
    #expect(unknown.canNext && unknown.canPrevious && unknown.canSeek)
    // No length or no permission: the position cannot be moved.
    #expect(!NowPlayingTrack(title: "Live").isSeekable)
    #expect(!NowPlayingTrack(title: "A", duration: 10, canSeek: false).isSeekable)
}

@Test func seekedTrackKeepsInsideItsLength() {
    let track = NowPlayingTrack(title: "A", duration: 100, elapsed: 10, timestamp: t0, rate: 1, isPlaying: true)
    #expect(track.seeked(to: 500, at: t0).elapsed(at: t0) == 100)
    #expect(track.seeked(to: -3, at: t0).elapsed(at: t0) == 0)
    #expect(track.seeked(to: 40, at: t0).elapsed(at: t0.addingTimeInterval(5)) == 45)   // keeps playing on from there
}
