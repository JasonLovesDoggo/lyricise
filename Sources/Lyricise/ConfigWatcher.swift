import Darwin
import Foundation
import LyriciseCore

/// Watches both the file and its directory so editors may either overwrite or atomically replace it.
/// Parsing happens on a serial background queue; the owner decides how to present failures while
/// retaining its last valid configuration.
@MainActor
final class ConfigWatcher {
    private let worker: ConfigWatchWorker

    init(url: URL, onChange: @escaping @MainActor @Sendable (Result<AppConfig, any Error>) -> Void) {
        worker = ConfigWatchWorker(url: url, onChange: onChange)
        worker.start()
    }

    func reload() { worker.reload() }
    func stop() { worker.stop() }
    deinit { worker.stop() }
}

/// All mutable fields below are confined to `queue`. The unchecked conformance lets filesystem
/// event handlers enqueue work without moving file descriptors or parser state between threads.
private final class ConfigWatchWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.json.lyricise.config", qos: .utility)
    private let url: URL
    private let onChange: @MainActor @Sendable (Result<AppConfig, any Error>) -> Void
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var pendingRead: DispatchWorkItem?
    private var lastData: Data?
    private var stopped = false
    private static let maximumBytes = 256 * 1024

    init(url: URL, onChange: @escaping @MainActor @Sendable (Result<AppConfig, any Error>) -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            watchDirectory()
            watchFile()
            read(force: true)
        }
    }

    func reload() {
        queue.async { [self] in
            guard !stopped else { return }
            pendingRead?.cancel()
            pendingRead = nil
            if directorySource == nil { watchDirectory() }
            watchFile()
            read(force: true)
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            pendingRead?.cancel()
            pendingRead = nil
            fileSource?.cancel()
            directorySource?.cancel()
            fileSource = nil
            directorySource = nil
        }
    }

    private func watchDirectory() {
        directorySource?.cancel()
        directorySource = makeSource(path: url.deletingLastPathComponent().path) { [weak self] in
            guard let self, !self.stopped else { return }
            // A replacement creates a new inode, so attach a fresh watch to the current path.
            self.watchFile()
            self.scheduleRead()
        }
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: url.path) { [weak self] in
            guard let self, !self.stopped else { return }
            self.scheduleRead()
        }
    }

    private func makeSource(path: String, handler: @escaping @Sendable () -> Void) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .revoke],
            queue: queue
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleRead() {
        pendingRead?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.pendingRead = nil
            self.read(force: false)
        }
        pendingRead = item
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }

    private func read(force: Bool) {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count <= Self.maximumBytes else { throw ConfigWatchError.tooLarge }
        } catch {
            lastData = nil
            deliver(.failure(error))
            return
        }
        guard force || data != lastData else { return }
        lastData = data
        do {
            guard let source = String(data: data, encoding: .utf8) else { throw ConfigWatchError.invalidEncoding }
            deliver(.success(try AppConfig.parse(source)))
        } catch {
            deliver(.failure(error))
        }
    }

    private func deliver(_ result: Result<AppConfig, any Error>) {
        let callback = onChange
        Task { @MainActor in callback(result) }
    }
}

private enum ConfigWatchError: LocalizedError {
    case tooLarge, invalidEncoding
    var errorDescription: String? {
        switch self {
        case .tooLarge: "The configuration file must be smaller than 256 KiB."
        case .invalidEncoding: "The configuration file must contain UTF-8 text."
        }
    }
}
