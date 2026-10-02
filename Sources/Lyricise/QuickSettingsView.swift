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
                    }.frame(width: 70, height: 18)
                }
                Slider(
                    value: Binding(
                        get: { store.config.fontSize },
                        set: { store.settings.preview(\.fontSize, to: $0.rounded()) }),
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
                    }.frame(width: 70, height: 18)
                }
                Slider(
                    value: Binding(
                        get: { Double(store.config.blurRadius) },
                        set: { store.settings.preview(\.blurRadius, to: Int($0.rounded())) }), in: 0...100
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

/// A native field accepts the first click without taking focus when the popover opens.
@MainActor private struct NumericSettingField: NSViewRepresentable {
    let kind: NumericSettingInput
    let value: Double
    let commit: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> ClickFocusedTextField {
        let field = ClickFocusedTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.delegate = context.coordinator
        field.setAccessibilityLabel(kind.label)
        field.toolTip = kind.help
        return field
    }

    func updateNSView(_ field: ClickFocusedTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil { field.stringValue = kind.display(value) }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumericSettingField
        init(parent: NumericSettingField) { self.parent = parent }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let value = parent.kind.parse(field.stringValue) {
                field.stringValue = parent.kind.display(value)
                if value != parent.value { parent.commit(value) }
            } else {
                field.stringValue = parent.kind.display(parent.value)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if command == #selector(NSResponder.cancelOperation(_:)) {
                textView.string = parent.kind.display(parent.value)
            } else if command != #selector(NSResponder.insertNewline(_:)) {
                return false
            }
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

@MainActor private final class ClickFocusedTextField: NSTextField {
    private var focusingFromClick = false
    override var acceptsFirstResponder: Bool { focusingFromClick }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        focusingFromClick = true
        defer { focusingFromClick = false }
        window?.makeFirstResponder(self)
        selectText(nil)
    }
}
