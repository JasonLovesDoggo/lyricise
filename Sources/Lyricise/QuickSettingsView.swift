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
                    NumericSettingField(kind: .fontSize, value: store.config.fontSize) { size in
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
                    NumericSettingField(kind: .blur, value: Double(store.config.blurRadius)) { value in
                        store.set(\.blurRadius, to: Int(value))
                    }
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

/// Display values stay inert until clicked; incomplete edits remain local.
@MainActor private struct NumericSettingField: View {
    let kind: NumericSettingInput
    let value: Double
    let commit: (Double) -> Void
    @State private var draft = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(kind.label, text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .onAppear { isFocused = true }
                    .onSubmit { finishEditing() }
                    .onExitCommand { finishEditing(save: false) }
                    .onChange(of: isFocused) {
                        if !isFocused { finishEditing() }
                    }
            } else {
                Button {
                    draft = kind.display(value)
                    isEditing = true
                } label: {
                    Text(kind.display(value))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 70)
        .accessibilityLabel(kind.label)
        .help(kind.help)
        .onDisappear { finishEditing() }
    }

    private func finishEditing(save: Bool = true) {
        guard isEditing else { return }
        isEditing = false
        isFocused = false
        if save, let number = kind.parse(draft), number != value {
            commit(number)
        }
    }
}
