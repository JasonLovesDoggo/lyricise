import Foundation
import Testing
@testable import LyriciseCore

@Suite("Configuration")
struct ConfigurationTests {
    @Test func exampleMatchesDefaults() throws {
        #expect(try AppConfig.parse(AppConfig.example) == AppConfig())
        #expect(try AppConfig.parse("") == AppConfig())
    }

    @Test func partialFilePreservesOtherDefaults() throws {
        let config = try AppConfig.parse("""
        [appearance]
        accent = "#ABCDef"
        blur = false
        [lyrics]
        offset_ms = -200
        """)
        #expect(config.accent == "#ABCDef")
        #expect(!config.blur)
        #expect(config.offsetMS == -200)
        #expect(config.width == 420)
        #expect(config.fontSize == 20)
        #expect(config.followPlayback)
    }

    @Test(arguments: [
        "[window]\nwidth = 259", "[window]\nheight = 2001",
        "[appearance]\nbackground_opacity = nan", "[appearance]\nbackground_opacity = 1.1",
        "[appearance]\nfont_size = inf", "[appearance]\nfont_size = 9",
        "[appearance]\npadding = -1", "[appearance]\nfont = '   '",
        "[appearance]\naccent = '#abcd'", "[appearance]\ntext = '#abcdefg'",
        "[appearance]\nbackground = '#zzzzzz'", "[appearance]\nmuted_text = \"#abcdef\\n\"",
        "[lyrics]\noffset_ms = 10001", "[lyrics]\noffset_ms = nan",
        "[window]\nwidth = '420'", "[window]\nalways_on_top = 'true'",
        "[window\nwidth = 420", "[window]\nwidth = 420\nwidth = 440"
    ])
    func rejectsInvalidFile(source: String) {
        #expect(throws: (any Error).self) { try AppConfig.parse(source) }
    }

    @Test func acceptsInclusiveBoundsAndTOMLComments() throws {
        let c = try AppConfig.parse("""
        [window]
        width = 260 # minimum
        height = 120
        [appearance]
        background_opacity = 0
        font_size = 72
        padding = 80
        [lyrics]
        offset_ms = -10000
        """)
        #expect(c.width == 260)
        #expect(c.opacity == 0)
        #expect(c.offsetMS == -10000)
    }
}

@Suite("Lyric timing in milliseconds")
struct TimingTests {
    let lines = [LyricLine(id: 10, time: 1000, text: "first"),
                 LyricLine(id: 20, time: 2500, text: "second"),
                 LyricLine(id: 21, time: 2500, text: "simultaneous"),
                 LyricLine(id: 30, time: 5000, text: "last")]

    @Test func boundariesAndDuplicateTimes() {
        #expect(LyricTiming.activeLine(in: lines, at: 999) == nil)
        #expect(LyricTiming.activeLine(in: lines, at: 1000) == 10)
        #expect(LyricTiming.activeLine(in: lines, at: 2499) == 10)
        #expect(LyricTiming.activeLine(in: lines, at: 2500) == 21)
        #expect(LyricTiming.activeLine(in: lines, at: 99999) == 30)
    }

    @Test func backwardAndForwardSeeksDoNotKeepOldIndex() {
        #expect(LyricTiming.activeLine(in: lines, at: 6000) == 30)
        #expect(LyricTiming.activeLine(in: lines, at: 1200) == 10)
        #expect(LyricTiming.activeLine(in: lines, at: 0) == nil)
        #expect(LyricTiming.activeLine(in: lines, at: 3000) == 21)
    }

    @Test func emptyUnsyncedAndInvalidPositions() {
        #expect(LyricTiming.activeLine(in: [], at: 1000) == nil)
        #expect(LyricTiming.activeLine(in: [LyricLine(id: 0, time: nil, text: "plain")], at: 1000) == nil)
        for value in [Double.nan, Double.infinity, -1] {
            #expect(LyricTiming.activeLine(in: lines, at: value) == nil)
        }
    }
}

@Suite("Companion payload validation")
struct SnapshotTests {
    func snapshot() -> Snapshot {
        Snapshot(trackID: "track", title: "Title", artist: "Artist", position: 1200,
                 duration: 200000, playing: true, status: "ready",
                 lines: [LyricLine(id: 0, time: 1000, text: "test"), LyricLine(id: 1, time: 2000, text: "next")],
                 provider: "Spotify", sequence: 1, session: "test-session")
    }

    @Test func JSONRoundTripMatchesWireTypes() throws {
        let encoded = try JSONEncoder().encode(snapshot())
        let received = try JSONDecoder().decode(Snapshot.self, from: encoded).validated()
        #expect(received.position == 1200)
        #expect(received.lines?.last?.time == 2000)
        #expect(received.sequence == 1)
        #expect(received.playing)
    }

    @Test func acceptsPlainLyricsAndHeartbeatWithoutLines() throws {
        var value = snapshot()
        value.lines = [LyricLine(id: 0, time: nil, text: "plain lyrics")]
        _ = try value.validated()
        value.lines = nil
        _ = try value.validated()
        value.lines = []
        value.status = "unavailable"
        _ = try value.validated()
    }

    @Test func acceptsDuplicateTimestampsButNotDuplicateIDs() throws {
        var value = snapshot()
        value.lines?[1].time = 1000
        _ = try value.validated()
        value.lines?[1].id = 0
        #expect(throws: ModelError.self) { try value.validated() }
    }

    @Test func rejectsDescendingAndMixedTiming() {
        var value = snapshot()
        value.lines?[1].time = 500
        #expect(throws: ModelError.self) { try value.validated() }
        value.lines?[1].time = nil
        #expect(throws: ModelError.self) { try value.validated() }
        value.lines?[0].time = nil
        value.lines?[1].time = 2000
        #expect(throws: ModelError.self) { try value.validated() }
    }

    @Test(arguments: [Double.nan, Double.infinity, -1, 86_400_000])
    func rejectsInvalidPosition(value: Double) {
        var payload = snapshot()
        payload.position = value
        #expect(throws: ModelError.self) { try payload.validated() }
        payload = snapshot()
        payload.lines?[0].time = value
        #expect(throws: ModelError.self) { try payload.validated() }
    }

    @Test(arguments: [Double.nan, Double.infinity, -1, 0.5, 9_007_199_254_740_992])
    func rejectsUnusableSequence(value: Double) {
        var payload = snapshot()
        payload.sequence = value
        #expect(throws: ModelError.self) { try payload.validated() }
    }

    @Test func rejectsUnknownStatusAndOversizedPayloadFields() {
        var value = snapshot()
        value.status = "unknown"
        #expect(throws: ModelError.self) { try value.validated() }
        value = snapshot()
        value.session = ""
        #expect(throws: ModelError.self) { try value.validated() }
        value = snapshot()
        value.title = String(repeating: "x", count: 2001)
        #expect(throws: ModelError.self) { try value.validated() }
        value = snapshot()
        value.lines = (0...5000).map { LyricLine(id: $0, time: nil, text: "") }
        #expect(throws: ModelError.self) { try value.validated() }
    }
}
