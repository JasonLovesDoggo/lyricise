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
                HStack(spacing: 0) {
                    Button {
                        if store.recordingHotKey { stop() } else { start() }
                    } label: {
                        Text(store.recordingHotKey ? "Type shortcut…" : label)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Record a global shortcut. Escape cancels; Delete clears it.")
                    .accessibilityLabel("Record shortcut")
                    if !store.settings.value.toggleHotKey.isEmpty && !store.recordingHotKey {
                        Button {
                            stop()
                            store.settings.set(\.toggleHotKey, to: "")
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 25, height: 26)
                                .background(.primary.opacity(0.04))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("Clear shortcut")
                        .accessibilityLabel("Clear shortcut")
                    }
                }
                .frame(width: 164)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(store.recordingHotKey ? Color.accentColor : .clear, lineWidth: 2)
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
        guard !shortcut.isEmpty else { return "Record Shortcut" }
        let symbols = ["cmd": "⌘", "ctrl": "⌃", "alt": "⌥", "shift": "⇧",
                       "space": "Space", "return": "↩", "tab": "⇥", "escape": "⎋",
                       "left": "←", "right": "→", "up": "↑", "down": "↓"]
        return shortcut.lowercased().components(separatedBy: "+").map { part in
            let key = part.trimmingCharacters(in: .whitespaces)
            return symbols[key] ?? key.uppercased()
        }.joined()
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
