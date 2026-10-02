import AppKit
import LyriciseCore
import Observation

@MainActor @Observable final class Store {
    var config = AppConfig()
    var hovering = false
    var quickSettingsPresented = false
    var title = "Lyricise"
    var artworkURL: URL?
    var artist = "Spotify lyrics, quietly."
    var lines: [LyricLine] = []
    var active: Int?
    var recenter = 0
    var animateLine = false
    var trackID = ""
    var message = "Open Spotify to get started"
    var configError: String?
    var connected = false
    @ObservationIgnored var bridge: Bridge?
    @ObservationIgnored var snapshot: Snapshot?
    @ObservationIgnored var retiredSessions: [String] = []
    @ObservationIgnored var received = ContinuousClock.now
    @ObservationIgnored var configWatcher: ConfigWatcher?
    @ObservationIgnored var timer: Task<Void, Never>?
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        ".config/lyricise")
    var configURL: URL { directory.appendingPathComponent("config.toml") }
    init() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configURL.path) {
                try AppConfig.example.write(to: configURL, atomically: true, encoding: .utf8)
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
                failure: { [weak self] error in Task { @MainActor in self?.message = error } },
                toggleWindow: { Task { @MainActor in PanelController.current?.toggle() } })
            try bridge?.start()
        } catch { message = error.localizedDescription }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                PanelController.current?.refreshHover()
                self.tick()
            }
        }
    }
    func reload() { configWatcher?.reload() }
    func accept(_ value: Snapshot) {
        guard !retiredSessions.contains(value.session) else { return }
        if let previous = snapshot, previous.session != value.session {
            retiredSessions.append(previous.session)
            if retiredSessions.count > 20 { retiredSessions.removeFirst() }
        }
        if let previous = snapshot, previous.session == value.session,
            value.sequence <= previous.sequence
        {
            return
        }
        let changed = value.trackID != snapshot?.trackID
        let elapsed = millisecondsSinceReceived
        let predicted = (snapshot?.position ?? 0) + (snapshot?.playing == true ? elapsed : 0)
        animateLine =
            connected && snapshot?.session == value.session && !changed
            && abs(value.position - predicted) < 1800
        if changed {
            lines = []
            active = nil
            trackID = value.trackID
        }
        snapshot = value
        received = .now
        connected = true
        artworkURL = value.artworkURL.flatMap(URL.init(string:))
        title = value.title.isEmpty ? "Lyricise" : value.title
        artist = value.artist
        if let incoming = value.lines, incoming != lines { lines = incoming }
        switch value.status {
        case "loading": message = "Finding lyrics…"
        case "ready": message = ""
        case "idle": message = "Play something on Spotify"
        case "unsupported": message = "Lyrics aren’t available for this item"
        case "auth_required": message = "Sign in to Spotify to load lyrics"
        case "rate_limited": message = "Spotify needs a moment. Try another track later."
        case "error": message = "Couldn’t load lyrics for this track"
        default: message = "No lyrics for this track"
        }
        tick()
        if changed || !animateLine { recenter += 1 }
    }
    private var millisecondsSinceReceived: Double {
        let duration = received.duration(to: .now).components
        return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    }
    func tick() {
        guard let snapshot else { return }
        if millisecondsSinceReceived > 6000 {
            connected = false
            message = "Waiting for Spotify…"
            return
        }
        let elapsed = snapshot.playing ? millisecondsSinceReceived : 0
        let next = LyricTiming.activeLine(
            in: lines, at: min(snapshot.duration, snapshot.position + elapsed) + config.offsetMS)
        if next != active { active = next }
    }
    func seek(to line: LyricLine) {
        guard connected, let time = line.time, let snapshot, time <= snapshot.duration else { return }
        bridge?.seek(trackID: snapshot.trackID, position: time)
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
