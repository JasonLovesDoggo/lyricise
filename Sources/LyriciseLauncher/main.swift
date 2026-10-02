import Foundation
import Darwin

// launchd owns the loopback listening socket. With inetd Wait=false, stdin is
// one accepted connection; this executable exits after its single response.
let fd = STDIN_FILENO
var timeout = timeval(tv_sec: 3, tv_usec: 0)
_ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
_ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
signal(SIGPIPE, SIG_IGN)
func reply(_ status: String) {
    let body = "{}"
    let response = "HTTP/1.1 \(status)\r\nAccess-Control-Allow-Origin: https://xpui.app.spotify.com\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Private-Network: true\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    let data = Array(response.utf8)
    data.withUnsafeBytes { pointer in
        var sent = 0
        while sent < data.count {
            let n = Darwin.send(fd, pointer.baseAddress!.advanced(by: sent), data.count - sent, 0)
            if n <= 0 { break }; sent += n
        }
    }
}
func handle() {
    var buffer = Data(), chunk = [UInt8](repeating: 0, count: 2048)
    let deadline = Date().addingTimeInterval(3)
    while buffer.count < 8192 && Date() < deadline {
        let n = recv(fd, &chunk, min(chunk.count, 8192 - buffer.count), 0)
        guard n > 0 else { return }
        buffer.append(contentsOf: chunk.prefix(n))
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) else { continue }
        let rows = head.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for row in rows.dropFirst() {
            let pair = row.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { reply("400 Bad Request"); return }
            let name = pair[0].lowercased()
            guard headers[name] == nil else { reply("400 Bad Request"); return }
            headers[name] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        guard headers["origin"] == nil || headers["origin"] == "https://xpui.app.spotify.com" else { reply("403 Forbidden"); return }
        if rows.first == "OPTIONS /launch HTTP/1.1" { reply("200 OK"); return }
        guard rows.first == "POST /launch HTTP/1.1", headers["transfer-encoding"] == nil,
              let count = Int(headers["content-length"] ?? ""), (0...1024).contains(count) else { reply("400 Bad Request"); return }
        let tokenURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/lyricise/bridge-token")
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              token.count == 64, headers["authorization"] == "Bearer \(token)" else { reply("403 Forbidden"); return }
        guard buffer.count - end.upperBound >= count else { continue }
        let app = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Lyricise.app").path
        guard FileManager.default.fileExists(atPath: app) else { reply("503 Service Unavailable"); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", app, "lyricise://show"]
        do { try process.run(); process.waitUntilExit(); reply(process.terminationStatus == 0 ? "200 OK" : "503 Service Unavailable") }
        catch { reply("503 Service Unavailable") }
        return
    }
    reply("413 Payload Too Large")
}
handle()
