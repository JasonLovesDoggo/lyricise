import Foundation
import Observation

/// Playback decisions shared by incoming snapshots, the display timer, and lyric clicks.
/// Times are monotonic; snapshots have already passed wire validation.
@Observable public final class PlaybackState {
    public private(set) var lines: [LyricLine] = []
    public private(set) var active: Int?
    public private(set) var recenter = 0
    public private(set) var animateLine = false
    public private(set) var connected = false

    @ObservationIgnored private var snapshot: Snapshot?
    @ObservationIgnored private var received = ContinuousClock.now
    @ObservationIgnored private var retiredSessions: [String] = []
    private static let disconnectAfter: Duration = .seconds(6)
    private static let seekThresholdMS = 1800.0
    private static let retiredSessionLimit = 20

    public init() {}

    public private(set) var trackID = ""
    public private(set) var title = "Lyricise"
    public private(set) var artist = "Spotify lyrics, quietly."
    public private(set) var artworkURL: URL?
    private var status: String?
    public var message: String {
        guard let status else { return "Open Spotify to get started" }
        guard connected else { return "Waiting for Spotify…" }
        switch status {
        case "loading": return "Finding lyrics…"
        case "ready": return ""
        case "idle": return "Play something on Spotify"
        case "unsupported": return "Lyrics aren’t available for this item"
        case "auth_required": return "Sign in to Spotify to load lyrics"
        case "rate_limited": return "Spotify needs a moment. Try another track later."
        case "error": return "Couldn’t load lyrics for this track"
        default: return "No lyrics for this track"
        }
    }

    /// Returns false for a duplicate, out-of-order, or retired-session snapshot.
    @discardableResult
    public func accept(_ value: Snapshot, at now: ContinuousClock.Instant, offsetMS: Double = 0)
        -> Bool
    {
        guard !retiredSessions.contains(value.session) else { return false }
        if let snapshot, snapshot.session == value.session, value.sequence <= snapshot.sequence {
            return false
        }
        let changed = value.trackID != snapshot?.trackID
        animateLine =
            isFresh(at: now) && snapshot?.session == value.session && !changed
            && abs(value.position - predictedPosition(at: now)) < Self.seekThresholdMS
        if let snapshot, snapshot.session != value.session {
            retiredSessions.append(snapshot.session)
            if retiredSessions.count > Self.retiredSessionLimit { retiredSessions.removeFirst() }
        }
        if changed { lines = [] }
        if let incoming = value.lines, incoming != lines { lines = incoming }
        snapshot = value
        trackID = value.trackID
        title = value.title.isEmpty ? "Lyricise" : value.title
        artist = value.artist
        artworkURL = value.artworkURL.flatMap(URL.init(string:))
        status = value.status
        received = now
        tick(at: now, offsetMS: offsetMS)
        if changed || !animateLine { recenter += 1 }
        return true
    }

    public func tick(at now: ContinuousClock.Instant, offsetMS: Double = 0) {
        connected = isFresh(at: now)
        guard connected, let snapshot else { return }
        let position = min(snapshot.duration, predictedPosition(at: now)) + offsetMS
        // Last matching timestamp wins, including duplicate timestamps.
        active = lines.last(where: { line in line.time.map { $0 <= position } ?? false })?.id
    }

    /// Recheck freshness at the click, even if the display timer has not run yet.
    public func seekPosition(for line: LyricLine, at now: ContinuousClock.Instant) -> Double? {
        guard isFresh(at: now), let snapshot, lines.contains(line),
            let time = line.time, time.isFinite, time >= 0, time <= snapshot.duration
        else { return nil }
        return time
    }

    private func isFresh(at now: ContinuousClock.Instant) -> Bool {
        snapshot != nil && received.duration(to: now) <= Self.disconnectAfter
    }

    private func predictedPosition(at now: ContinuousClock.Instant) -> Double {
        guard let snapshot else { return 0 }
        let elapsed = received.duration(to: now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        return snapshot.position + (snapshot.playing ? milliseconds : 0)
    }
}
