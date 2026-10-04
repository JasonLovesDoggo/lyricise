import Darwin
import Foundation

private enum LauncherPolicy {
    static let socketTimeoutSeconds = 3
    static let maximumRequestBytes = 8192
    static let maximumBodyBytes = 1024
    static let spotifyOrigin = "https://xpui.app.spotify.com"
}

private enum HTTPStatus: String, Error {
    case ok = "200 OK"
    case badRequest = "400 Bad Request"
    case forbidden = "403 Forbidden"
    case payloadTooLarge = "413 Payload Too Large"
    case unavailable = "503 Service Unavailable"
}

private struct RequestHead {
    let requestLine: String
    let headers: [String: String]

    init(_ text: String) throws {
        let rows = text.components(separatedBy: "\r\n")
        requestLine = rows.first ?? ""
        var parsed: [String: String] = [:]
        for row in rows.dropFirst() {
            let pair = row.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { throw HTTPStatus.badRequest }
            let name = pair[0].lowercased()
            guard parsed[name] == nil else { throw HTTPStatus.badRequest }
            parsed[name] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        headers = parsed
    }

    func validateOrigin() throws {
        guard headers["origin"] == nil || headers["origin"] == LauncherPolicy.spotifyOrigin else {
            throw HTTPStatus.forbidden
        }
    }

    func authorizedBodyLength() throws -> Int {
        guard requestLine == "POST /launch HTTP/1.1", headers["transfer-encoding"] == nil,
            let count = Int(headers["content-length"] ?? ""),
            (0...LauncherPolicy.maximumBodyBytes).contains(count)
        else {
            throw HTTPStatus.badRequest
        }
        let tokenURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lyricise/bridge-token")
        guard
            let token = try? String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            token.count == 64, headers["authorization"] == "Bearer \(token)"
        else {
            throw HTTPStatus.forbidden
        }
        return count
    }
}

private func reply(_ status: HTTPStatus, to socket: Int32) {
    let body = "{}"
    let response = [
        "HTTP/1.1 \(status.rawValue)",
        "Access-Control-Allow-Origin: \(LauncherPolicy.spotifyOrigin)",
        "Access-Control-Allow-Headers: Authorization, Content-Type",
        "Access-Control-Allow-Methods: POST, OPTIONS",
        "Access-Control-Allow-Private-Network: true",
        "Content-Type: application/json",
        "Content-Length: \(body.utf8.count)",
        "Connection: close", "", body,
    ].joined(separator: "\r\n")
    let data = Array(response.utf8)
    data.withUnsafeBytes { pointer in
        guard let baseAddress = pointer.baseAddress else { return }
        var sent = 0
        while sent < data.count {
            let count = Darwin.send(socket, baseAddress.advanced(by: sent), data.count - sent, 0)
            // The peer may have closed the connection; there is no response to retry.
            guard count > 0 else { return }
            sent += count
        }
    }
}

private func launchApp() -> HTTPStatus {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let app: String
    switch arguments.count {
    case 0:
        // Existing launch agents predate the explicit installation path.
        app = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Lyricise.app").path
    case 2 where arguments[0] == "--app" && arguments[1].hasPrefix("/"):
        app = arguments[1]
    default:
        return .unavailable
    }
    guard URL(fileURLWithPath: app).pathExtension == "app",
        Bundle(path: app)?.bundleIdentifier == "cam.jsn.lyricise"
    else { return .unavailable }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", app, "lyricise://show"]
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? .ok : .unavailable
    } catch {
        return .unavailable
    }
}

/// Returns nil until the complete authorized request body has arrived.
private func responseStatus(for buffer: Data) throws -> HTTPStatus? {
    guard let end = buffer.range(of: Data("\r\n\r\n".utf8)),
        let text = String(data: buffer[..<end.lowerBound], encoding: .utf8)
    else { return nil }
    let request = try RequestHead(text)
    try request.validateOrigin()
    if request.requestLine == "OPTIONS /launch HTTP/1.1" { return .ok }
    let bodyLength = try request.authorizedBodyLength()
    guard buffer.count - end.upperBound >= bodyLength else { return nil }
    return launchApp()
}

private func handle(connection: Int32) {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 2048)
    let deadline = Date().addingTimeInterval(TimeInterval(LauncherPolicy.socketTimeoutSeconds))
    while buffer.count < LauncherPolicy.maximumRequestBytes && Date() < deadline {
        let capacity = min(chunk.count, LauncherPolicy.maximumRequestBytes - buffer.count)
        let count = recv(connection, &chunk, capacity, 0)
        guard count > 0 else { return }
        buffer.append(contentsOf: chunk.prefix(count))
        do {
            guard let status = try responseStatus(for: buffer) else { continue }
            reply(status, to: connection)
        } catch let status as HTTPStatus {
            reply(status, to: connection)
        } catch {
            reply(.unavailable, to: connection)
        }
        return
    }
    reply(.payloadTooLarge, to: connection)
}

// launchd owns the loopback listening socket. With inetd Wait=false, stdin is
// one accepted connection; this executable exits after its single response.
let connection = STDIN_FILENO
var timeout = timeval(tv_sec: LauncherPolicy.socketTimeoutSeconds, tv_usec: 0)
let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
guard setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize) == 0,
    setsockopt(connection, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize) == 0
else {
    exit(EXIT_FAILURE)
}
signal(SIGPIPE, SIG_IGN)
handle(connection: connection)
