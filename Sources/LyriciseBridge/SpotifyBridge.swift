import Foundation
import HTTPTypes
import Hummingbird
import LyriciseCore

/// The companion's HTTP API. Hummingbird owns framing, connections and JSON encoding.
public struct SpotifyBridge: Sendable {
    private let token: String
    private let receive: @Sendable (Snapshot) async -> Void
    private let toggleWindow: @Sendable () async -> Void
    private let state = BridgeState()

    public init(
        token: String,
        receive: @escaping @Sendable (Snapshot) async -> Void,
        toggleWindow: @escaping @Sendable () async -> Void
    ) {
        self.token = token
        self.receive = receive
        self.toggleWindow = toggleWindow
    }

    public func run() async throws {
        // The app owns its lifecycle; do not install server signal handlers in AppKit.
        try await application().runService(gracefulShutdownSignals: [])
    }

    public func seek(trackID: String, position: Double) async {
        await state.seek(trackID: trackID, position: position)
    }

    public func control(_ action: PlaybackAction, trackID: String) async {
        await state.control(action, trackID: trackID)
    }

    func application() -> some ApplicationProtocol {
        let router = Router(context: BridgeContext.self)
        router.add(middleware: CompanionAccess(token: token))
        router.post("/snapshot") { request, context in
            let snapshot: Snapshot
            do {
                snapshot = try await request.decode(as: Snapshot.self, context: context).validated()
            } catch is ModelError {
                throw HTTPError(.badRequest)
            }
            await state.updateHealth(snapshot)
            await receive(snapshot)
            return EmptyResponse()
        }
        router.get("/command") { _, _ in await state.pendingCommand() }
        router.get("/health") { _, _ in await state.health }
        router.post("/toggle") { _, _ in
            await toggleWindow()
            return EmptyResponse()
        }
        return Application(
            router: router,
            server: .http1(
                configuration: .init(
                    idleTimeout: .seconds(5),
                    httpDecoderConfiguration: .init(maxHeaderFieldSize: 8192, maxHeaderListSize: 8192)
                )),
            configuration: .init(address: .hostname("127.0.0.1", port: 17389))
        )
    }
}

struct BridgeContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    // Match the companion payload contract without buffering arbitrary uploads.
    var maxUploadSize: Int { 1_000_000 }

    init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
    }
}

/// Preflight is public; every operation requires the per-install bearer token.
private struct CompanionAccess: RouterMiddleware {
    let token: String

    func handle(
        _ request: Request, context: BridgeContext,
        next: (Request, BridgeContext) async throws -> Response
    ) async throws -> Response {
        var response: Response
        if request.method == .options && ["/snapshot", "/command", "/toggle"].contains(request.uri.path) {
            response = Response(status: .noContent)
        } else if request.headers[.authorization] != "Bearer \(token)" {
            response = Response(status: .forbidden)
        } else {
            do {
                response = try await next(request, context)
            } catch let error as any HTTPResponseError {
                response = try error.response(from: request, context: context)
            }
        }
        response.headers[.accessControlAllowOrigin] = "*"
        response.headers[.accessControlAllowHeaders] = "Authorization, Content-Type"
        response.headers[.accessControlAllowMethods] = "GET, POST, OPTIONS"
        // Spotify's Chromium client requires this for access to loopback services.
        if let name = HTTPField.Name("Access-Control-Allow-Private-Network") {
            response.headers[name] = "true"
        }
        return response
    }
}

struct EmptyResponse: ResponseEncodable {}

struct PlayerCommand: ResponseEncodable {
    var id: String?
    var trackID: String?
    var position: Double?
    var action: PlaybackAction?
}

struct BridgeHealth: ResponseEncodable {
    var received = false
    var status: String?
    var lineCount: Int?
    var synced: Bool?
    var playing: Bool?
    var position: Double?
    var hasArtwork: Bool?
    var receivedAt: Double?
}

actor BridgeState {
    private var command = PlayerCommand()
    private var commandExpires = ContinuousClock.now
    private(set) var health = BridgeHealth()

    func seek(trackID: String, position: Double, now: ContinuousClock.Instant = .now) {
        command = PlayerCommand(id: UUID().uuidString, trackID: trackID, position: position)
        // Commands must not replay after a stalled companion reconnects.
        commandExpires = now.advanced(by: .seconds(2))
    }

    func control(_ action: PlaybackAction, trackID: String, now: ContinuousClock.Instant = .now) {
        command = PlayerCommand(id: UUID().uuidString, trackID: trackID, action: action)
        commandExpires = now.advanced(by: .seconds(2))
    }

    func pendingCommand(now: ContinuousClock.Instant = .now) -> PlayerCommand {
        commandExpires > now ? command : PlayerCommand()
    }

    func updateHealth(_ snapshot: Snapshot) {
        health = BridgeHealth(
            received: true, status: snapshot.status, lineCount: snapshot.lines?.count ?? 0,
            synced: snapshot.lines?.first?.time != nil, playing: snapshot.playing,
            position: snapshot.position, hasArtwork: snapshot.artworkURL != nil,
            receivedAt: Date().timeIntervalSince1970
        )
    }
}
