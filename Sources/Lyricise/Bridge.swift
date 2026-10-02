import LyriciseBridge
import LyriciseCore

/// Owns the server task for the lifetime of the AppKit application.
@MainActor final class Bridge {
    private let server: SpotifyBridge
    private let failure: @Sendable (String) -> Void
    private var task: Task<Void, Never>?

    init(
        token: String,
        receive: @escaping @Sendable (Snapshot) -> Void,
        failure: @escaping @Sendable (String) -> Void,
        toggleWindow: @escaping @Sendable () -> Void
    ) {
        server = SpotifyBridge(token: token, receive: receive, toggleWindow: toggleWindow)
        self.failure = failure
    }

    func start() {
        guard task == nil else { return }
        task = Task { [server, failure] in
            do {
                try await server.run()
            } catch is CancellationError {
                // App shutdown cancels the server task.
            } catch {
                failure("Couldn’t start Spotify bridge: \(error.localizedDescription)")
            }
        }
    }

    func seek(trackID: String, position: Double) {
        Task { await server.seek(trackID: trackID, position: position) }
    }

    deinit { task?.cancel() }
}
