import Carbon.HIToolbox
import Foundation

/// Physical ANSI key positions, matching macOS global hotkey registration.
public struct WindowHotKey: Sendable, Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public static func parse(_ source: String) throws -> Self? {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source.isEmpty { return nil }
        let parts = source.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, let code = keys[key], parts.count > 1 else { throw InvalidHotKey() }
        let flags = ["cmd": cmdKey, "ctrl": controlKey, "alt": optionKey, "shift": shiftKey]
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            guard let flag = flags[part], modifiers & UInt32(flag) == 0 else { throw InvalidHotKey() }
            modifiers |= UInt32(flag)
        }
        // Avoid intercepting ordinary typing, including Shift+letter.
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { throw InvalidHotKey() }
        return Self(keyCode: UInt32(code), modifiers: modifiers)
    }

    private static let keys = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
}

private struct InvalidHotKey: LocalizedError {
    var errorDescription: String? {
        "Invalid window.toggle_hotkey. Use cmd/ctrl/alt/shift plus a key, such as cmd+shift+l, or an empty string to disable it. Include cmd, ctrl, or alt."
    }
}
