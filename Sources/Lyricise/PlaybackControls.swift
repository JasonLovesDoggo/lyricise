import LyriciseCore
import SwiftUI

@MainActor struct PlaybackControls: View {
    let store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedAction: PlaybackAction?

    private var visible: Bool {
        store.settings.value.playbackControlsVisibility.isVisible(
            hovering: store.hovering || focusedAction != nil)
    }
    private var available: Bool {
        store.playback.connected && store.playback.trackID.hasPrefix("spotify:track:")
    }

    var body: some View {
        HStack(spacing: 4) {
            control(.previous, title: "Previous track", symbol: "backward.end.fill")
            control(
                store.playback.playing ? .pause : .play,
                title: store.playback.playing ? "Pause" : "Play",
                symbol: store.playback.playing ? "pause.fill" : "play.fill",
                prominent: true)
            control(.next, title: "Next track", symbol: "forward.end.fill")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: visible)
    }

    private func control(_ action: PlaybackAction, title: String, symbol: String, prominent: Bool = false) -> some View {
        Button { store.control(action) } label: {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 13, weight: .semibold))
                .frame(width: prominent ? 38 : 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .disabled(!available || !visible)
        .focused($focusedAction, equals: action)
    }
}
