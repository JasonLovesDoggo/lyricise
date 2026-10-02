import Foundation
import LyriciseCore
import Network

/// Mutable bridge state is confined to `queue`, including all connection callbacks.
final class Bridge: @unchecked Sendable {
    private enum Limits {
        static let receiveChunkBytes = 65_536
        static let requestBytes = 1_048_576
        static let headerBytes = 8_192
        static let snapshotBytes = 1_000_000
        static let connectionTimeout: TimeInterval = 5
        static let commandLifetime: Duration = .seconds(2)
    }

    private struct Request {
        let line: String
        let headers: [String: String]
        let body: Data

        init?(buffer: Data, headerRange: Range<Data.Index>) {
            guard headerRange.lowerBound < Limits.headerBytes,
                let header = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8)
            else {
                return nil
            }
            let rows = header.components(separatedBy: "\r\n")
            line = rows.first ?? ""
            var headers: [String: String] = [:]
            for row in rows.dropFirst() {
                let parts = row.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            self.headers = headers
            body = Data(buffer[headerRange.upperBound...])
        }

        var isPreflight: Bool {
            ["OPTIONS /snapshot HTTP/1.1", "OPTIONS /command HTTP/1.1", "OPTIONS /toggle HTTP/1.1"].contains(
                line)
        }
    }

    private let queue = DispatchQueue(label: "lyricise.bridge")
    private var listener: NWListener?
    private var health = "{\"received\":false}"
    private var command: (body: String, expires: ContinuousClock.Instant)?
    let toggleWindow: @Sendable () -> Void
    let token: String
    let receive: @Sendable (Snapshot) -> Void
    let failure: @Sendable (String) -> Void

    init(
        token: String,
        receive: @escaping @Sendable (Snapshot) -> Void,
        failure: @escaping @Sendable (String) -> Void,
        toggleWindow: @escaping @Sendable () -> Void
    ) {
        self.token = token
        self.receive = receive
        self.failure = failure
        self.toggleWindow = toggleWindow
    }

    func seek(trackID: String, position: Double) {
        queue.async { [self] in
            let payload: [String: Any] = ["id": UUID().uuidString, "trackID": trackID, "position": position]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
                let body = String(data: data, encoding: .utf8)
            {
                command = (body, .now.advanced(by: Limits.commandLifetime))
            }
        }
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 17389)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.failure("Couldn’t start Spotify bridge: \(error.localizedDescription)")
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.read(connection, buffer: Data())
            self.queue.asyncAfter(deadline: .now() + Limits.connectionTimeout) {
                connection.cancel()
            }
        }
        listener.start(queue: queue)
    }

    private func reply(_ connection: NWConnection, code: String, body: String = "{}") {
        let headers = [
            "HTTP/1.1 \(code)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Authorization, Content-Type",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Private-Network: true",
            "Content-Type: application/json",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
        ]
        let response = headers.joined(separator: "\r\n") + "\r\n\r\n" + body
        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Limits.receiveChunkBytes) {
            [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= Limits.requestBytes else {
                self.reply(connection, code: "413 Payload Too Large")
                return
            }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard let request = Request(buffer: buffer, headerRange: range) else {
                    connection.cancel()
                    return
                }
                if self.handle(request, connection: connection) { return }
            } else if buffer.count > Limits.headerBytes {
                connection.cancel()
                return
            }
            guard !complete, error == nil else {
                connection.cancel()
                return
            }
            self.read(connection, buffer: buffer)
        }
    }

    /// Returns false only when a valid snapshot request needs more body bytes.
    private func handle(_ request: Request, connection: NWConnection) -> Bool {
        if request.isPreflight {
            reply(connection, code: "204 No Content", body: "")
            return true
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            reply(connection, code: "403 Forbidden")
            return true
        }
        switch request.line {
        case "POST /toggle HTTP/1.1":
            toggleWindow()
            reply(connection, code: "200 OK")
        case "GET /command HTTP/1.1":
            let body = command.map { command in command.expires > .now ? command.body : "{}" } ?? "{}"
            reply(connection, code: "200 OK", body: body)
        case "GET /health HTTP/1.1":
            reply(connection, code: "200 OK", body: health)
        case "POST /snapshot HTTP/1.1":
            return handleSnapshot(request, connection: connection)
        default:
            reply(connection, code: "404 Not Found")
        }
        return true
    }

    private func handleSnapshot(_ request: Request, connection: NWConnection) -> Bool {
        guard request.headers["transfer-encoding"] == nil,
            let count = Int(request.headers["content-length"] ?? ""),
            (0...Limits.snapshotBytes).contains(count)
        else {
            reply(connection, code: "400 Bad Request")
            return true
        }
        guard request.body.count >= count else { return false }
        do {
            let snapshot = try JSONDecoder()
                .decode(Snapshot.self, from: Data(request.body.prefix(count)))
                .validated()
            updateHealth(snapshot)
            receive(snapshot)
            reply(connection, code: "200 OK")
        } catch {
            reply(connection, code: "400 Bad Request")
        }
        return true
    }

    private func updateHealth(_ snapshot: Snapshot) {
        let diagnostics: [String: Any] = [
            "received": true,
            "status": snapshot.status,
            "lineCount": snapshot.lines?.count ?? 0,
            "synced": snapshot.lines?.first?.time != nil,
            "playing": snapshot.playing,
            "position": snapshot.position,
            "hasArtwork": snapshot.artworkURL != nil,
            "receivedAt": Date().timeIntervalSince1970,
        ]
        if let encoded = try? JSONSerialization.data(withJSONObject: diagnostics),
            let string = String(data: encoded, encoding: .utf8)
        {
            health = string
        }
    }
}
