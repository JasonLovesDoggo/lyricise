import Foundation
import Network
import LyriciseCore

final class Bridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "lyricise.bridge")
    private var listener: NWListener?
    private var health = "{\"received\":false}"
    private var command: (body: String, expires: ContinuousClock.Instant)?
    let toggleWindow: @Sendable () -> Void
    let token: String
    let receive: @Sendable (Snapshot) -> Void
    let failure: @Sendable (String) -> Void
    init(token: String, receive: @escaping @Sendable (Snapshot) -> Void, failure: @escaping @Sendable (String) -> Void, toggleWindow: @escaping @Sendable () -> Void) { self.token = token; self.receive = receive; self.failure = failure; self.toggleWindow = toggleWindow }
    func seek(trackID: String, position: Double) {
        queue.async { [self] in
            let payload: [String: Any] = ["id": UUID().uuidString, "trackID": trackID, "position": position]
            if let data = try? JSONSerialization.data(withJSONObject: payload), let body = String(data: data, encoding: .utf8) {
                command = (body, .now.advanced(by: .seconds(2)))
            }
        }
    }
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 17389)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.failure("Couldn’t start Spotify bridge: \(error.localizedDescription)") }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.read(connection, buffer: Data())
            self.queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        }
        listener.start(queue: queue)
    }
    private func reply(_ connection: NWConnection, code: String, body: String = "{}") {
        let response = "HTTP/1.1 \(code)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Private-Network: true\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer; if let data { buffer.append(data) }
            guard buffer.count <= 1_048_576 else { self.reply(connection, code: "413 Payload Too Large"); return }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard range.lowerBound < 8192, let header = String(data: buffer[..<range.lowerBound], encoding: .utf8) else { connection.cancel(); return }
                let rows = header.components(separatedBy: "\r\n")
                if rows.first == "OPTIONS /snapshot HTTP/1.1" || rows.first == "OPTIONS /command HTTP/1.1" || rows.first == "OPTIONS /toggle HTTP/1.1" { self.reply(connection, code: "204 No Content", body: ""); return }
                var headers: [String: String] = [:]
                for row in rows.dropFirst() {
                    let parts = row.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 { headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
                }
                guard headers["authorization"] == "Bearer \(self.token)" else { self.reply(connection, code: "403 Forbidden"); return }
                if rows.first == "POST /toggle HTTP/1.1" {
                    self.toggleWindow()
                    self.reply(connection, code: "200 OK")
                    return
                }
                if rows.first == "GET /command HTTP/1.1" {
                    self.reply(connection, code: "200 OK", body: self.command.map { $0.expires > .now ? $0.body : "{}" } ?? "{}")
                    return
                }
                if rows.first == "GET /health HTTP/1.1" { self.reply(connection, code: "200 OK", body: self.health); return }
                guard rows.first == "POST /snapshot HTTP/1.1" else { self.reply(connection, code: "404 Not Found"); return }
                guard headers["transfer-encoding"] == nil, let count = Int(headers["content-length"] ?? ""), (0...1_000_000).contains(count) else { self.reply(connection, code: "400 Bad Request"); return }
                let body = buffer[range.upperBound...]
                if body.count >= count {
                    do {
                        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(body.prefix(count))).validated()
                        let diagnostics: [String: Any] = ["received": true, "status": snapshot.status, "lineCount": snapshot.lines?.count ?? 0, "synced": snapshot.lines?.first?.time != nil, "playing": snapshot.playing, "position": snapshot.position, "hasArtwork": snapshot.artworkURL != nil, "receivedAt": Date().timeIntervalSince1970]
                        if let encoded = try? JSONSerialization.data(withJSONObject: diagnostics), let string = String(data: encoded, encoding: .utf8) { self.health = string }
                        self.receive(snapshot)
                        self.reply(connection, code: "200 OK")
                    } catch { self.reply(connection, code: "400 Bad Request") }
                    return
                }
            } else if buffer.count > 8192 { connection.cancel(); return }
            if complete || error != nil { connection.cancel(); return }
            self.read(connection, buffer: buffer)
        }
    }
}
