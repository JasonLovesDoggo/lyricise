import Carbon.HIToolbox
import LyriciseCore

/// Owns the one global registration. Carbon delivers application events on the main thread.
@MainActor final class GlobalHotKey {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var binding: WindowHotKey?
    private var configured = false

    func update(_ newBinding: WindowHotKey?) -> String? {
        guard !configured || newBinding != binding else { return nil }
        stop()
        guard let newBinding else { configured = true; return nil }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(), { _, event, _ in
                var identifier = EventHotKeyID()
                guard let event,
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                    identifier.signature == 0x4C595249, identifier.id == 1
                else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated { PanelController.current?.toggle() }
                return noErr
            }, 1, &event, nil, &handler)
        guard handlerStatus == noErr else {
            return "Could not listen for the window hotkey (macOS error \(handlerStatus))."
        }
        // 'LYRI' identifies Lyricise's single hotkey.
        let status = RegisterEventHotKey(
            newBinding.keyCode, newBinding.modifiers, EventHotKeyID(signature: 0x4C595249, id: 1),
            GetApplicationEventTarget(), 0, &registration)
        guard status == noErr else {
            stop()
            return "Could not register window.toggle_hotkey (macOS error \(status)). Choose another shortcut; it may already be in use."
        }
        binding = newBinding
        configured = true
        return nil
    }

    func stop() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
        binding = nil
        configured = false
    }
}
