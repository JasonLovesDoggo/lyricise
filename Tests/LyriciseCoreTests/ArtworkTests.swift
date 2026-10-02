import Foundation
import Testing
@testable import LyriciseCore

@Suite("Spotify album artwork")
struct ArtworkTests {
    private func snapshot(artworkURL: String? = nil) -> Snapshot {
        Snapshot(trackID: "track", title: "Title", artist: "Artist", position: 0,
                 duration: 200000, playing: false, status: "ready", sequence: 1,
                 session: "session", artworkURL: artworkURL)
    }

    @Test func missingArtworkRemainsWireCompatible() throws {
        let data = try JSONEncoder().encode(snapshot())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["artworkURL"] == nil)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data).validated()
        #expect(decoded.artworkURL == nil)
    }

    @Test(arguments: [
        "https://i.scdn.co/image/abc123",
        "https://image-cdn-ak.spotifycdn.com/image/abc123",
        "https://image-cdn-fa.spotifycdn.com/image/abc123",
        "https://i.scdn.co:443/image/abc123?size=300"
    ])
    func acceptsSpotifyArtwork(url: String) throws {
        #expect(try snapshot(artworkURL: url).validated().artworkURL == url)
    }

    @Test(arguments: [
        "http://i.scdn.co/image/abc", "file:///tmp/image.png",
        "https://example.com/image", "https://i.scdn.co.example.com/image",
        "https://localhost/image", "https://127.0.0.1/image",
        "https://user@i.scdn.co/image", "https://user:secret@i.scdn.co/image",
        "https://i.scdn.co:8080/image", "https://i.scdn.co/image#fragment",
        "https://i.scdn.co/image with spaces", "", "//i.scdn.co/image"
    ])
    func rejectsUntrustedOrMalformedArtwork(url: String) {
        #expect(throws: ModelError.self) { try snapshot(artworkURL: url).validated() }
    }
}
