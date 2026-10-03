import AppKit
import Carbon.HIToolbox
import LyriciseCore
import SwiftUI

@MainActor struct HotKeyRecorder: View {
    let store: Store
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Show / hide")
                Spacer()
                Button(store.recordingHotKey ? "Press shortcut…" : label) {
                    if store.recordingHotKey { stop() } else { start() }
                }
                .help("Record a global shortcut. Escape cancels; Delete clears it.")
                if !store.settings.value.toggleHotKey.isEmpty {
                    Button {
                        stop()
                        store.settings.set(\.toggleHotKey, to: "")
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).help("Clear shortcut")
                    .accessibilityLabel("Clear shortcut")
                }
            }
            if let message = hint ?? store.hotKeyError {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private var label: String {
        let shortcut = store.settings.value.toggleHotKey
        return shortcut.isEmpty ? "Record shortcut" : shortcut.uppercased()
    }

    private func start() {
        store.recordingHotKey = true
        hint = "Press a shortcut with ⌘, ⌃ or ⌥. Esc cancels."
        PanelController.current?.hotKey.stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { capture(event) }
            return nil
        }
    }

    private func capture(_ event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        if plain && event.keyCode == kVK_Escape { stop(); return }
        if plain && (event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete) {
            stop()
            store.settings.set(\.toggleHotKey, to: "")
            return
        }
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard let shortcut = WindowHotKey.recording(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            hint = "Use ⌘, ⌃ or ⌥ with a letter, number, arrow, or function key."
            return
        }
        stop()
        store.settings.set(\.toggleHotKey, to: shortcut)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        store.recordingHotKey = false
        hint = nil
    }
}
