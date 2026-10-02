import Darwin
import Foundation

/// Watches both the file and its directory so editors may either overwrite or atomically replace it.
/// Delivers invalidations, not parsed values: the owner always reads the current file.
@MainActor
final class ConfigWatcher {
    private let worker: ConfigWatchWorker

    init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        worker = ConfigWatchWorker(url: url, onChange: onChange)
        worker.start()
    }

    deinit { worker.stop() }
}

/// All mutable fields below are confined to `queue`. The unchecked conformance lets filesystem
/// event handlers enqueue work without moving file descriptors or watch state between threads.
private final class ConfigWatchWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.json.lyricise.config", qos: .utility)
    private let url: URL
    private let onChange: @MainActor @Sendable () -> Void
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var pendingNotification: DispatchWorkItem?
    private var stopped = false

    init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            watchDirectory()
            watchFile()
            onInvalidation()
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            pendingNotification?.cancel()
            pendingNotification = nil
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
            self.scheduleNotification()
        }
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: url.path) { [weak self] in
            guard let self, !self.stopped else { return }
            self.scheduleNotification()
        }
    }

    private func makeSource(path: String, handler: @escaping @Sendable () -> Void) -> (
        any DispatchSourceFileSystemObject
    )? {
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

    private func scheduleNotification() {
        pendingNotification?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.pendingNotification = nil
            self.onInvalidation()
        }
        pendingNotification = item
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }

    private func onInvalidation() {
        let callback = onChange
        Task { @MainActor in callback() }
    }
}
