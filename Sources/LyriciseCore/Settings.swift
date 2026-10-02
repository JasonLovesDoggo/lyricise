import Foundation
import Observation

/// Owns settings on disk and their live preview. A save merges only the edited setting into the
/// latest file; an invalid file or failed write leaves the last accepted settings in use.
@MainActor @Observable public final class Settings {
    public let url: URL
    public private(set) var value = AppConfig()
    public private(set) var error: String?
    @ObservationIgnored private var accepted = AppConfig()
    @ObservationIgnored private var previewChange: ((inout AppConfig) -> Void)?
    @ObservationIgnored private var watcher: ConfigWatcher?

    public init(url: URL) {
        self.url = url
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try AppConfig.defaultTOML.write(to: url, atomically: true, encoding: .utf8)
            }
            reload()
        } catch { self.error = error.localizedDescription }
        watcher = ConfigWatcher(url: url) { [weak self] in self?.reload() }
    }

    public func reload() {
        do {
            accepted = try read()
            value = accepted
            previewChange?(&value)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Slider changes remain in memory until their editing gesture ends.
    public func preview<Value>(_ key: WritableKeyPath<AppConfig, Value>, to newValue: Value) {
        previewChange = { $0[keyPath: key] = newValue }
        value = accepted
        previewChange?(&value)
    }

    public func set<Value>(_ key: WritableKeyPath<AppConfig, Value>, to newValue: Value) {
        previewChange = nil
        do {
            // Read here, even when a watch event is pending, to preserve unrelated external edits.
            accepted = try read()
            var updated = accepted
            updated[keyPath: key] = newValue
            try updated.serialized().write(to: url, atomically: true, encoding: .utf8)
            accepted = updated
            error = nil
        } catch { self.error = error.localizedDescription }
        value = accepted
    }

    private func read() throws -> AppConfig {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let maximumBytes = 256 * 1024
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw SettingsReadError.tooLarge }
        guard let source = String(data: data, encoding: .utf8) else {
            throw SettingsReadError.invalidEncoding
        }
        return try AppConfig.parse(source)
    }
}

private enum SettingsReadError: LocalizedError {
    case tooLarge, invalidEncoding
    var errorDescription: String? {
        switch self {
        case .tooLarge: "The configuration file must be smaller than 256 KiB."
        case .invalidEncoding: "The configuration file must contain UTF-8 text."
        }
    }
}
