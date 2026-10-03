/// Explicit play/pause actions remain safe if a command is polled more than once.
public enum PlaybackAction: String, Codable, Sendable, Hashable, CaseIterable {
    case play, pause, previous, next
}
