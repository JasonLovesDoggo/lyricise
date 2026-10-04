import AppKit
import Observation

@MainActor @Observable final class SpotifySetup {
    private(set) var running = false
    private(set) var finished = false
    private(set) var failure: String?
    @ObservationIgnored private var process: Process?

    func prepare() {
        guard !running else { return }
        finished = false
        failure = nil
    }

    func connect() {
        guard !running else { return }
        failure = nil
        finished = false
        guard let script = Bundle.main.url(forResource: "setup-spotify", withExtension: "sh") else {
            failure = "Spotify setup is missing. Reinstall Lyricise and try again."
            return
        }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("lyricise-setup-\(UUID()).log")
        do {
            guard FileManager.default.createFile(
                atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            let output = try FileHandle(forWritingTo: log)
            defer { try? output.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, "--app", Bundle.main.bundleURL.path]
            if let spotify = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                process.arguments?.append(contentsOf: ["--spotify-app", spotify.path])
            }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                Task { @MainActor in self?.complete(status: status, log: log) }
            }
            self.process = process
            running = true
            try process.run()
        } catch {
            running = false
            process = nil
            failure = error.localizedDescription
            try? FileManager.default.removeItem(at: log)
        }
    }

    private func complete(status: Int32, log: URL) {
        defer { try? FileManager.default.removeItem(at: log) }
        process = nil
        running = false
        finished = status == 0
        if status != 0 {
            let output = (try? String(contentsOf: log, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            failure = output.flatMap { $0.isEmpty ? nil : $0 }
                ?? "Spotify setup stopped (exit \(status)). Try connecting again."
        }
    }
}
