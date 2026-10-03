import Foundation
import Observation
import Synchronization
import Testing

@testable import LyriciseCore

@Suite("Playback")
struct PlaybackTests {
    let start = ContinuousClock.now
    let lines = [
        LyricLine(id: 10, time: 1000, text: "first"),
        LyricLine(id: 20, time: 2500, text: "second"),
        LyricLine(id: 21, time: 2500, text: "simultaneous"),
        LyricLine(id: 30, time: 5000, text: "last"),
    ]

    private func snapshot() -> Snapshot {
        Snapshot(
            trackID: "track", title: "Title", artist: "Artist", position: 0,
            duration: 6000, playing: true, status: "ready", lines: lines,
            sequence: 1, session: "first")
    }

    @Test func playbackControlsUseFreshAcceptedPlaybackState() {
        let playback = PlaybackState()
        var value = snapshot()
        value.trackID = "spotify:track:abc"
        #expect(playback.controllableTrack(at: start) == nil)
        playback.accept(value, at: start)
        #expect(playback.playing)
        #expect(playback.controllableTrack(at: start) == value.trackID)
        value.playing = false
        playback.accept(value, at: start)
        #expect(playback.playing) // Duplicate snapshots cannot change the button state.
        value.sequence = 2
        playback.accept(value, at: start)
        #expect(!playback.playing)
        #expect(playback.controllableTrack(at: start.advanced(by: .seconds(7))) == nil)
    }

    @Test func unchangedTicksAndHeartbeatsDoNotInvalidateDisplayedLyrics() {
        let playback = PlaybackState()
        var value = snapshot()
        value.position = 1000
        playback.accept(value, at: start)
        let invalidations = Mutex(0)
        withObservationTracking {
            _ = playback.lines
            _ = playback.active
            _ = playback.title
            _ = playback.artist
            _ = playback.artworkURL
            _ = playback.trackID
            _ = playback.message
            _ = playback.connected
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }
        playback.tick(at: start.advanced(by: .milliseconds(100)))
        value.sequence = 2
        value.position = 1200
        playback.accept(value, at: start.advanced(by: .milliseconds(200)))
        #expect(invalidations.withLock { $0 } == 0)
        playback.tick(at: start.advanced(by: .milliseconds(1500)))
        #expect(playback.active == 21)
        #expect(invalidations.withLock { $0 } == 1)
    }

    @Test func clockSelectsLinesWithOffsetsAndDuplicateTimestamps() {
        let playback = PlaybackState()
        playback.accept(snapshot(), at: start)
        #expect(playback.active == nil)
        for (elapsed, expected) in [(999, nil), (1000, 10), (2499, 10), (2500, 21), (6000, 30)] {
            playback.tick(at: start.advanced(by: .milliseconds(elapsed)))
            #expect(playback.active == expected)
        }
        playback.tick(at: start.advanced(by: .seconds(6)), offsetMS: -3500)
        #expect(playback.active == 21)
        playback.tick(at: start.advanced(by: .seconds(6)), offsetMS: -6001)
        #expect(playback.active == nil)
    }

    @Test func pauseAndDurationStopPrediction() {
        let playback = PlaybackState()
        var value = snapshot()
        value.duration = 2000
        playback.accept(value, at: start)
        playback.tick(at: start.advanced(by: .seconds(5)))
        #expect(playback.active == 10)
        value.sequence = 2
        value.position = 1000
        value.playing = false
        playback.accept(value, at: start.advanced(by: .seconds(5)))
        playback.tick(at: start.advanced(by: .seconds(10)))
        #expect(playback.active == 10)
    }

    @Test func heartbeatKeepsLyricsButExplicitEmptyAndTrackChangesClearThem() {
        let playback = PlaybackState()
        var value = snapshot()
        value.position = 1000
        playback.accept(value, at: start)
        value.sequence = 2
        value.lines = nil
        playback.accept(value, at: start)
        #expect(playback.lines == lines)
        #expect(playback.active == 10)
        value.sequence = 3
        value.lines = []
        playback.accept(value, at: start)
        #expect(playback.lines.isEmpty)
        #expect(playback.active == nil)
        value.sequence = 4
        value.lines = lines
        playback.accept(value, at: start)
        value.sequence = 5
        value.lines = nil
        value.trackID = "other-track"
        value.title = "Other"
        value.artist = "Other artist"
        value.artworkURL = "https://i.scdn.co/image/other"
        value.status = "loading"
        playback.accept(value, at: start)
        #expect(playback.lines.isEmpty)
        #expect(playback.active == nil)
        #expect(playback.trackID == "other-track")
        #expect(playback.title == "Other")
        #expect(playback.artist == "Other artist")
        #expect(playback.artworkURL?.absoluteString == value.artworkURL)
        #expect(playback.message == "Finding lyrics…")
        #expect(!playback.animateLine)
    }

    @Test func staleSnapshotsDoNotChangeStateOrRefreshConnection() {
        let playback = PlaybackState()
        var value = snapshot()
        value.sequence = 2
        playback.accept(value, at: start)
        value.title = "Stale title"
        #expect(!playback.accept(value, at: start.advanced(by: .seconds(5))))
        value.sequence = 1
        #expect(!playback.accept(value, at: start.advanced(by: .seconds(5))))
        #expect(playback.title == "Title")
        #expect(playback.recenter == 1)
        playback.tick(at: start.advanced(by: .seconds(7)))
        #expect(!playback.connected)
    }

    @Test func newSessionReplacesOldAndRetiredSessionCannotReturn() {
        let playback = PlaybackState()
        var value = snapshot()
        value.sequence = 50
        playback.accept(value, at: start)
        value.session = "second"
        value.sequence = 1
        value.title = "New session"
        playback.accept(value, at: start.advanced(by: .seconds(1)))
        #expect(!playback.animateLine)
        #expect(playback.recenter == 2)
        value.session = "first"
        value.sequence = 51
        #expect(!playback.accept(value, at: start.advanced(by: .seconds(5))))
        #expect(playback.title == "New session")
        playback.tick(at: start.advanced(by: .seconds(8)))
        #expect(!playback.connected)
    }

    @Test func naturalProgressAnimatesButSeeksRecenterImmediately() {
        let playback = PlaybackState()
        var value = snapshot()
        playback.accept(value, at: start)
        #expect(!playback.animateLine)
        #expect(playback.recenter == 1)
        value.sequence = 2
        value.position = 1000
        playback.accept(value, at: start.advanced(by: .seconds(1)))
        #expect(playback.animateLine)
        #expect(playback.recenter == 1)
        value.sequence = 3
        value.position = 5000
        playback.accept(value, at: start.advanced(by: .seconds(2)))
        #expect(playback.active == 30)
        #expect(!playback.animateLine)
        #expect(playback.recenter == 2)
        value.sequence = 4
        value.position = 1000
        playback.accept(value, at: start.advanced(by: .seconds(3)))
        #expect(playback.active == 10)
        #expect(!playback.animateLine)
        #expect(playback.recenter == 3)
    }

    @Test func disconnectAndReconnectUseFreshnessEvenWithoutTimerTick() {
        let playback = PlaybackState()
        var value = snapshot()
        playback.accept(value, at: start)
        playback.tick(at: start.advanced(by: .seconds(6)))
        #expect(playback.connected)
        playback.tick(at: start.advanced(by: .milliseconds(6001)))
        #expect(!playback.connected)
        #expect(playback.message == "Waiting for Spotify…")
        value.sequence = 2
        value.position = 6000
        playback.accept(value, at: start.advanced(by: .seconds(7)))
        #expect(playback.connected)
        #expect(playback.message.isEmpty)
        #expect(!playback.animateLine)
        #expect(playback.recenter == 2)
        // No tick between these snapshots: elapsed time must still forbid animation.
        value.sequence = 3
        value.position = 13000
        playback.accept(value, at: start.advanced(by: .seconds(14)))
        #expect(!playback.animateLine)
        #expect(playback.recenter == 3)
    }

    @Test func seekingRequiresFreshCurrentTimedLyricsWithinDuration() {
        let playback = PlaybackState()
        #expect(playback.seekPosition(for: lines[0], at: start) == nil)
        var value = snapshot()
        value.duration = 2500
        playback.accept(value, at: start)
        #expect(playback.seekPosition(for: lines[0], at: start) == 1000)
        #expect(playback.seekPosition(for: lines[1], at: start) == 2500)
        #expect(playback.seekPosition(for: lines[3], at: start) == nil)
        #expect(playback.seekPosition(for: lines[0], at: start.advanced(by: .seconds(7))) == nil)
        value.sequence = 2
        value.trackID = "other"
        value.lines = [LyricLine(id: 10, time: nil, text: "plain lyrics")]
        playback.accept(value, at: start)
        #expect(playback.seekPosition(for: lines[0], at: start) == nil)
        #expect(playback.seekPosition(for: playback.lines[0], at: start) == nil)
        #expect(playback.active == nil)
    }
}
