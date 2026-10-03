import AppKit
import LyriciseCore
import Observation

@MainActor @Observable final class Store {
    let settings: Settings
    var hovering = false
    var hoveringControls = false
    var quickSettingsPresented = false
    let playback = PlaybackState()
    var connectionError: String?
    var message: String { connectionError ?? playback.message }
    @ObservationIgnored var bridge: Bridge?
    @ObservationIgnored var timer: Task<Void, Never>?
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        ".config/lyricise")
    init() {
        settings = Settings(url: directory.appendingPathComponent("config.toml"))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let tokenURL = directory.appendingPathComponent("bridge-token")
            let token: String
            if let existing = try? String(contentsOf: tokenURL, encoding: .utf8), !existing.isEmpty {
                token = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
                    .lowercased()
                try token.write(to: tokenURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            }
            bridge = Bridge(
                token: token, receive: { [weak self] data in Task { @MainActor in self?.accept(data) } },
                failure: { [weak self] error in Task { @MainActor in self?.connectionError = error } },
                toggleWindow: { Task { @MainActor in PanelController.current?.toggle() } })
            bridge?.start()
        } catch { connectionError = error.localizedDescription }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                PanelController.current?.refreshHover()
                self.playback.tick(at: .now, offsetMS: self.settings.value.offsetMS)
            }
        }
    }
    func accept(_ value: Snapshot) {
        if playback.accept(value, at: .now, offsetMS: settings.value.offsetMS) { connectionError = nil }
    }
    func seek(to line: LyricLine) {
        guard let position = playback.seekPosition(for: line, at: .now) else { return }
        bridge?.seek(trackID: playback.trackID, position: position)
    }
    func openConfig() { NSWorkspace.shared.open(settings.url) }
}
