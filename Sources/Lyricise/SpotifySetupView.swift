import SwiftUI

struct SpotifySetupView: View {
    let store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Spotify").font(.title2.weight(.semibold))
            Text("Installs or updates Spicetify and connects Spotify. Spotify restarts once; your settings and extensions stay intact.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.spotifySetup.running {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Connecting… This can take a few minutes.")
                }
            } else if let failure = store.spotifySetup.failure {
                VStack(alignment: .leading, spacing: 8) {
                    Text(failure.split(separator: "\n").last.map(String.init) ?? failure)
                        .foregroundStyle(.red).textSelection(.enabled)
                    DisclosureGroup("Details") {
                        ScrollView {
                            Text(failure).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 160)
                    }
                }
            } else if store.spotifySetup.finished {
                Label(
                    store.playback.connected ? "Connected to Spotify" : "Waiting for Spotify…",
                    systemImage: store.playback.connected ? "checkmark.circle.fill" : "music.note")
                if !store.playback.connected {
                    Text("Keep Spotify open and play a song.").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button(store.spotifySetup.finished ? "Done" : "Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !store.spotifySetup.finished {
                    Button(store.spotifySetup.failure == nil ? "Connect" : "Try Again") {
                        store.spotifySetup.connect()
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(store.spotifySetup.running)
                }
            }
        }
        .padding(24).frame(width: 400)
        .onAppear { store.spotifySetup.prepare() }
    }
}
