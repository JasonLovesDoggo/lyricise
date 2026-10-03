import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import LyriciseCore
import Testing

@testable import LyriciseBridge

private actor BridgeEvents {
    private(set) var snapshots: [Snapshot] = []
    private(set) var toggles = 0

    func receive(_ snapshot: Snapshot) { snapshots.append(snapshot) }
    func toggle() { toggles += 1 }
}

@Suite("Spotify bridge HTTP contract")
struct BridgeTests {
    private let headers: HTTPFields = [
        .authorization: "Bearer test-token",
        .contentType: "application/json",
    ]
    // Older companions include provider; decoding must continue to accept it.
    private let snapshotJSON =
        #"{"trackID":"spotify:track:abc","title":"Title","artist":"Artist","position":1200,"duration":200000,"playing":true,"status":"ready","lines":[{"id":0,"time":1000,"text":"Test line"}],"provider":"Spotify","sequence":1,"session":"test-session"}"#

    private func bridge(events: BridgeEvents) -> SpotifyBridge {
        SpotifyBridge(
            token: "test-token",
            receive: { snapshot in await events.receive(snapshot) },
            toggleWindow: { await events.toggle() }
        )
    }

    @Test func authorizationAndPreflight() async throws {
        let events = BridgeEvents()
        try await bridge(events: events).application().test(.router) { client in
            for path in ["/snapshot", "/command", "/toggle"] {
                let preflight = try await client.execute(uri: path, method: .options)
                #expect(preflight.status == .noContent)
                #expect(preflight.body.readableBytes == 0)
                #expect(preflight.headers[.accessControlAllowOrigin] == "*")
                #expect(preflight.headers[.accessControlAllowMethods] == "GET, POST, OPTIONS")
                let privateNetwork = try #require(HTTPField.Name("Access-Control-Allow-Private-Network"))
                #expect(preflight.headers[privateNetwork] == "true")
            }
            for authorization in ["", "Bearer wrong-token", "test-token"] {
                let response = try await client.execute(
                    uri: "/toggle", method: .post, headers: [.authorization: authorization]
                )
                #expect(response.status == .forbidden)
                #expect(response.headers[.accessControlAllowOrigin] == "*")
            }
            let health = try await client.execute(uri: "/health", method: .get)
            #expect(health.status == .forbidden)
            let snapshot = try await client.execute(uri: "/snapshot", method: .post)
            #expect(snapshot.status == .forbidden)
            let command = try await client.execute(uri: "/command", method: .get)
            #expect(command.status == .forbidden)
            #expect(await events.toggles == 0)
            #expect(await events.snapshots.isEmpty)
        }
    }

    @Test func invalidSnapshotsNeverReachTheApp() async throws {
        let events = BridgeEvents()
        try await bridge(events: events).application().test(.router) { client in
            for body in ["not json", "{}", snapshotJSON.replacingOccurrences(of: "1200", with: "-1")] {
                let response = try await client.execute(
                    uri: "/snapshot", method: .post, headers: headers, body: ByteBuffer(string: body)
                )
                #expect(response.status == .badRequest)
                #expect(response.headers[.accessControlAllowOrigin] == "*")
            }
            #expect(await events.snapshots.isEmpty)
            let health = try await client.execute(uri: "/health", method: .get, headers: headers)
            let value = try JSONDecoder().decode(Health.self, from: Data(health.body.readableBytesView))
            #expect(!value.received)
        }
    }

    @Test func liveSnapshotHealthToggleAndCommand() async throws {
        let events = BridgeEvents()
        let bridge = bridge(events: events)
        try await bridge.application().test(.live) { client in
            let snapshot = try await client.execute(
                uri: "/snapshot", method: .post, headers: headers, body: ByteBuffer(string: snapshotJSON)
            )
            #expect(snapshot.status == .ok)
            #expect(await events.snapshots.count == 1)
            #expect(await events.snapshots.first?.trackID == "spotify:track:abc")

            let health = try await client.execute(uri: "/health", method: .get, headers: headers)
            #expect(health.status == .ok)
            let value = try JSONDecoder().decode(Health.self, from: Data(health.body.readableBytesView))
            #expect(value.received)
            #expect(value.status == "ready")
            #expect(value.lineCount == 1)
            #expect(value.synced == true)
            #expect(value.playing == true)
            #expect(value.position == 1200)
            #expect(value.hasArtwork == false)
            #expect(value.receivedAt != nil)

            let toggle = try await client.execute(uri: "/toggle", method: .post, headers: headers)
            #expect(toggle.status == .ok)
            #expect(await events.toggles == 1)

            let empty = try await client.execute(uri: "/command", method: .get, headers: headers)
            #expect(String(buffer: empty.body) == "{}")

            await bridge.seek(trackID: "spotify:track:abc", position: 5000)
            let command = try await client.execute(uri: "/command", method: .get, headers: headers)
            #expect(command.status == .ok)
            let seek = try JSONDecoder().decode(Command.self, from: Data(command.body.readableBytesView))
            #expect(seek.trackID == "spotify:track:abc")
            #expect(seek.position == 5000)
            #expect(seek.id?.isEmpty == false)

            await bridge.control(.pause, trackID: "spotify:track:abc")
            let response = try await client.execute(uri: "/command", method: .get, headers: headers)
            let control = try JSONDecoder().decode(Command.self, from: Data(response.body.readableBytesView))
            #expect(control.action == .pause)
            #expect(control.trackID == "spotify:track:abc")
            #expect(control.position == nil)
            #expect(control.id?.isEmpty == false)

            let missing = try await client.execute(uri: "/missing", method: .get, headers: headers)
            #expect(missing.status == .notFound)
            #expect(missing.headers[.accessControlAllowOrigin] == "*")
        }
    }

    @Test func liveBodyLimitRejectsOversizedUpload() async throws {
        let events = BridgeEvents()
        try await bridge(events: events).application().test(.live) { client in
            let response = try await client.execute(
                uri: "/snapshot", method: .post, headers: headers,
                body: ByteBuffer(string: String(repeating: " ", count: 1_000_001))
            )
            #expect(response.status == .contentTooLarge)
            #expect(response.headers[.accessControlAllowOrigin] == "*")
            #expect(await events.snapshots.isEmpty)
        }
    }

    @Test func commandsExpireAndReplaceEachOther() async {
        let state = BridgeState()
        let now = ContinuousClock.now
        #expect(await state.pendingCommand(now: now).id == nil)
        await state.seek(trackID: "first", position: 1000, now: now)
        let first = await state.pendingCommand(now: now)
        #expect(first.trackID == "first")
        #expect(first.position == 1000)
        #expect(first.id != nil)
        await state.control(.pause, trackID: "second", now: now.advanced(by: .seconds(1)))
        let second = await state.pendingCommand(now: now.advanced(by: .seconds(2)))
        #expect(second.trackID == "second")
        #expect(second.action == .pause)
        #expect(second.position == nil)
        #expect(second.id != first.id)
        #expect(await state.pendingCommand(now: now.advanced(by: .seconds(3))).id == nil)
    }

    private struct Health: Decodable {
        var received: Bool
        var status: String?
        var lineCount: Int?
        var synced: Bool?
        var playing: Bool?
        var position: Double?
        var hasArtwork: Bool?
        var receivedAt: Double?
    }

    private struct Command: Decodable {
        var id: String?
        var trackID: String?
        var position: Double?
        var action: PlaybackAction?
    }
}
