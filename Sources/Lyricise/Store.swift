import AppKit
import LyriciseCore
import Observation

@MainActor @Observable final class Store {
    var config = AppConfig()
    var hovering = false
    var quickSettingsPresented = false
    let playback = PlaybackState()
    var configError: String?
    var connectionError: String?
    var message: String { connectionError ?? playback.message }
    @ObservationIgnored var bridge: Bridge?
    @ObservationIgnored var configWatcher: ConfigWatcher?
    @ObservationIgnored var timer: Task<Void, Never>?
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        ".config/lyricise")
    var configURL: URL { directory.appendingPathComponent("config.toml") }
    init() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configURL.path) {
                try AppConfig.defaultTOML.write(to: configURL, atomically: true, encoding: .utf8)
            }
            config = (try? AppConfig.parse(String(contentsOf: configURL, encoding: .utf8))) ?? AppConfig()
            configWatcher = ConfigWatcher(url: configURL) { [weak self] result in
                switch result {
                case .success(let value):
                    self?.config = value
                    self?.configError = nil
                case .failure(let error): self?.configError = error.localizedDescription
                }
            }
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
                self.playback.tick(at: .now, offsetMS: self.config.offsetMS)
            }
        }
    }
    func reload() { configWatcher?.reload() }
    func accept(_ value: Snapshot) {
        if playback.accept(value, at: .now, offsetMS: config.offsetMS) { connectionError = nil }
    }
    func seek(to line: LyricLine) {
        guard let position = playback.seekPosition(for: line, at: .now) else { return }
        bridge?.seek(trackID: playback.trackID, position: position)
    }
    func set<Value>(_ key: WritableKeyPath<AppConfig, Value>, to value: Value) {
        var updated = config
        updated[keyPath: key] = value
        do {
            try updated.serialized().write(to: configURL, atomically: true, encoding: .utf8)
            config = updated
            configError = nil
        } catch { configError = error.localizedDescription }
    }
    func openConfig() { NSWorkspace.shared.open(configURL) }
}
