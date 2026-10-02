import Foundation

public struct LyricLine: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var time: Double?
    public var text: String
    public init(id: Int, time: Double?, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}
public struct Snapshot: Codable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var position: Double
    public var duration: Double
    public var playing: Bool
    public var status: String
    public var lines: [LyricLine]?
    public var provider: String?
    public var artworkURL: String?
    public var sequence: Double
    public var session: String

    public init(
        trackID: String, title: String, artist: String, position: Double,
        duration: Double, playing: Bool, status: String, lines: [LyricLine]? = nil,
        provider: String? = nil, sequence: Double, session: String, artworkURL: String? = nil
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.position = position
        self.duration = duration
        self.playing = playing
        self.status = status
        self.lines = lines
        self.provider = provider
        self.sequence = sequence
        self.session = session
        self.artworkURL = artworkURL
    }

    public func validated() throws -> Self {
        guard position.isFinite, duration.isFinite, position >= 0, duration >= 0,
            position < 86_400_000, duration < 86_400_000,
            title.count <= 2000, artist.count <= 2000, trackID.count <= 200,
            !session.isEmpty, session.count <= 100,
            sequence.isFinite, sequence >= 0, sequence <= 9_007_199_254_740_991,
            sequence.rounded(.towardZero) == sequence, (provider?.count ?? 0) <= 200,
            [
                "ready", "loading", "unavailable", "error", "idle", "unsupported", "rate_limited",
                "auth_required",
            ].contains(status),
            (lines?.count ?? 0) <= 5000
        else { throw ModelError.invalidSnapshot }
        if let artworkURL {
            guard artworkURL.count <= 2048,
                let url = URL(string: artworkURL, encodingInvalidCharacters: false),
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                components.scheme?.lowercased() == "https",
                ["i.scdn.co", "image-cdn-ak.spotifycdn.com", "image-cdn-fa.spotifycdn.com"].contains(
                    components.host?.lowercased() ?? ""),
                components.user == nil, components.password == nil, components.fragment == nil,
                components.port == nil || components.port == 443
            else { throw ModelError.invalidSnapshot }
        }
        var previousTime: Double?
        let timed = lines?.first?.time != nil
        for line in lines ?? [] {
            guard line.text.count <= 10000,
                line.time.map({ $0.isFinite && $0 >= 0 && $0 < 86_400_000 }) ?? true
            else { throw ModelError.invalidSnapshot }
            // A payload is either fully timed or plain lyrics. Do not silently
            // highlight the wrong row if a malformed provider mixes both.
            guard (line.time != nil) == timed else { throw ModelError.invalidSnapshot }
            if let time = line.time {
                guard previousTime.map({ time >= $0 }) ?? true else { throw ModelError.invalidSnapshot }
                previousTime = time
            }
        }
        if let lines, Set(lines.map(\.id)).count != lines.count { throw ModelError.invalidSnapshot }
        return self
    }
}
public enum ModelError: Error { case invalidSnapshot }
