import AppKit
import LyriciseCore
import SwiftUI

@MainActor struct QuickSettingsView: View {
    let store: Store
    private static let fontNames =
        ["SF Pro"] + NSFontManager.shared.availableFontFamilies.filter { $0 != "SF Pro" }.sorted()
    private func setting<Value>(_ key: WritableKeyPath<AppConfig, Value>) -> Binding<Value> {
        Binding(get: { store.config[keyPath: key] }, set: { store.set(key, to: $0) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick Settings").font(.headline)
                Spacer()
                Button {
                    store.quickSettingsPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain).help("Close settings")
            }
            Picker("Font", selection: setting(\.font)) {
                ForEach(Self.fontNames, id: \.self) { name in
                    Text(name == "SF Pro" ? "System · SF Pro" : name).tag(name)
                }
                if !Self.fontNames.contains(store.config.font) {
                    Text(store.config.font).tag(store.config.font)
                }
            }
            VStack(spacing: 6) {
                HStack {
                    Text("Font size")
                    Spacer()
                    FontSizeField(size: store.config.fontSize) { size in
                        store.set(\.fontSize, to: size)
                    }
                }
                Slider(
                    value: Binding(
                        get: { store.config.fontSize }, set: { store.config.fontSize = $0.rounded() }),
                    in: 10...72
                ) { editing in
                    if !editing { store.set(\.fontSize, to: store.config.fontSize) }
                }.accessibilityLabel("Font size")
            }
            Divider()
            VStack(spacing: 6) {
                HStack {
                    Text("Blur intensity")
                    Spacer()
                    Text(store.config.blurRadius == 0 ? "Off" : "\(store.config.blurRadius)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(store.config.blurRadius) },
                        set: { store.config.blurRadius = Int($0.rounded()) }), in: 0...100
                ) { editing in
                    if !editing { store.set(\.blurRadius, to: store.config.blurRadius) }
                }.accessibilityLabel("Blur intensity")
            }
            Toggle("Always on top", isOn: setting(\.alwaysOnTop))
            Toggle("Show on all Spaces", isOn: setting(\.allSpaces))
            Toggle("Show song and artist", isOn: setting(\.showTrackTitle))
            Toggle("Show album cover", isOn: setting(\.showArtwork))
            Toggle("Follow current lyric", isOn: setting(\.followPlayback))
            if let error = store.configError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(
                    horizontal: false, vertical: true)
            }
            Button("Open Config") { store.openConfig() }
                .font(.callout)
        }
        .toggleStyle(.switch).controlSize(.small)
        .padding(20).frame(width: 340)
    }
}

/// Keeps incomplete edits local until they can be validated and saved.
@MainActor private struct FontSizeField: View {
    let size: Double
    let commit: (Double) -> Void
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField("Font size", text: $draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 70)
            .focused($isEditing)
            .accessibilityLabel("Font size in points")
            .help("Enter a size from 10 to 72 pt")
            .onAppear { resetDraft() }
            .onChange(of: size) {
                if !isEditing { resetDraft() }
            }
            .onChange(of: isEditing) {
                if !isEditing { saveDraft() }
            }
            .onSubmit { isEditing = false }
            .onExitCommand {
                resetDraft()
                isEditing = false
            }
            .onDisappear {
                if isEditing { saveDraft() }
            }
    }

    private func saveDraft() {
        if let value = FontSizeInput.parse(draft), value != size {
            commit(value)
        }
        resetDraft()
    }

    private func resetDraft() {
        draft = FontSizeInput.display(size)
    }
}
