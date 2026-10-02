import Foundation
import TOML

public struct AppConfig: Sendable, Equatable {
    public var width = 420.0, height = 300.0
    public var alwaysOnTop = true, allSpaces = true, rememberPosition = true
    public var background = "#1e1e2e", accent = "#b4befe", text = "#cdd6f4", mutedText = "#6c7086"
    public var opacity = 0.75, fontSize = 20.0, padding = 16.0, cornerRadius = 12.0
    public var blurRadius = 0
    public var blur: Bool {
        get { blurRadius > 0 }
        set { blurRadius = newValue ? (blurRadius > 0 ? blurRadius : 20) : 0 }
    }
    public var showTrackTitle = true, followPlayback = true
    public var showArtwork = false
    public var font = "SF Pro", offsetMS = 0.0
    public init() {}
    public static func parse(_ source: String) throws -> Self {
        let decoded = try TOMLDecoder().decode(FileConfig.self, from: source)
        var config = Self()
        if let window = decoded.window {
            config.width = window.width ?? config.width
            config.height = window.height ?? config.height
            config.alwaysOnTop = window.always_on_top ?? config.alwaysOnTop
            config.allSpaces = window.all_spaces ?? config.allSpaces
            config.rememberPosition = window.remember_position ?? config.rememberPosition
        }
        if let appearance = decoded.appearance {
            config.background = appearance.background ?? config.background
            config.accent = appearance.accent ?? config.accent
            config.text = appearance.text ?? config.text
            config.mutedText = appearance.muted_text ?? config.mutedText
            config.opacity = appearance.background_opacity ?? config.opacity
            config.blurRadius = appearance.blur?.radius ?? config.blurRadius
            config.font = appearance.font ?? config.font
            config.fontSize = appearance.font_size ?? config.fontSize
            config.padding = appearance.padding ?? config.padding
            config.cornerRadius = appearance.corner_radius ?? config.cornerRadius
        }
        if let lyrics = decoded.lyrics {
            config.showTrackTitle = lyrics.show_track_title ?? config.showTrackTitle
            config.showArtwork = lyrics.show_album_art ?? config.showArtwork
            config.followPlayback = lyrics.follow_playback ?? config.followPlayback
            config.offsetMS = lyrics.offset_ms ?? config.offsetMS
        }
        guard (260...2000).contains(config.width), (120...2000).contains(config.height),
            (0...1).contains(config.opacity), (10...72).contains(config.fontSize),
            (0...80).contains(config.padding),
            (0...40).contains(config.cornerRadius), (0...100).contains(config.blurRadius),
            (-10000...10000).contains(config.offsetMS),
            !config.font.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            config.font.count <= 256,
            [config.background, config.accent, config.text, config.mutedText].allSatisfy(Self.validColor)
        else { throw ConfigError.invalidValue }
        return config
    }
    /// Serializes all supported settings. TOML comments and unknown keys are not retained.
    public func serialized() throws -> String {
        let file = FileConfig(
            window: .init(
                width: width, height: height, always_on_top: alwaysOnTop,
                all_spaces: allSpaces, remember_position: rememberPosition),
            appearance: .init(
                background: background, background_opacity: opacity, blur: .init(radius: blurRadius),
                accent: accent, text: text, muted_text: mutedText, font: font,
                font_size: fontSize, padding: padding, corner_radius: cornerRadius),
            lyrics: .init(
                show_track_title: showTrackTitle, show_album_art: showArtwork,
                follow_playback: followPlayback,
                offset_ms: offsetMS)
        )
        let source = try TOMLEncoder().encodeToString(file)
        _ = try Self.parse(source)
        return source + (source.hasSuffix("\n") ? "" : "\n")
    }

    private static func validColor(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 7 && bytes.first == 35
            && bytes.dropFirst().allSatisfy { byte in
                (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
            }
    }
    /// The bundled configuration written on first launch.
    public static var defaultTOML: String {
        get throws {
            guard let url = Bundle.module.url(forResource: "default", withExtension: "toml") else {
                throw ConfigError.missingDefaultResource
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
    }
}
public enum ConfigError: LocalizedError {
    case invalidValue
    case missingDefaultResource
    public var errorDescription: String? {
        switch self {
        case .missingDefaultResource:
            "The bundled default configuration is missing. Reinstall Lyricise to restore it."
        case .invalidValue:
            "Check colors (#RRGGBB), window size (260–2000 × 120–2000), opacity (0–1), blur (0–100), font size (10–72), padding (0–80), corner radius (0–40), and offset (±10000 ms)."
        }
    }
}
private struct FileConfig: Codable {
    var window: Window?, appearance: Appearance?, lyrics: Lyrics?
    struct Window: Codable {
        var width: Double?, height: Double?, always_on_top: Bool?, all_spaces: Bool?,
            remember_position: Bool?
    }
    struct Appearance: Codable {
        var background: String?, background_opacity: Double?, blur: BlurValue?, accent: String?,
            text: String?, muted_text: String?, font: String?, font_size: Double?, padding: Double?,
            corner_radius: Double?
    }
    struct Lyrics: Codable {
        var show_track_title: Bool?, show_album_art: Bool?, follow_playback: Bool?, offset_ms: Double?
    }
}

/// Reads legacy Boolean blur settings, but always writes the numeric intensity.
private struct BlurValue: Codable {
    let radius: Int
    init(radius: Int) { self.radius = radius }
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let boolean = try? value.decode(Bool.self) {
            radius = boolean ? 20 : 0
        } else {
            radius = try value.decode(Int.self)
        }
    }
    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(radius)
    }
}
