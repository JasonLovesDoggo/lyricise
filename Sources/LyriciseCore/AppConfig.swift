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
        var c = Self()
        if let w = decoded.window {
            c.width = w.width ?? c.width; c.height = w.height ?? c.height
            c.alwaysOnTop = w.always_on_top ?? c.alwaysOnTop; c.allSpaces = w.all_spaces ?? c.allSpaces
            c.rememberPosition = w.remember_position ?? c.rememberPosition
        }
        if let a = decoded.appearance {
            c.background = a.background ?? c.background; c.accent = a.accent ?? c.accent
            c.text = a.text ?? c.text; c.mutedText = a.muted_text ?? c.mutedText
            c.opacity = a.background_opacity ?? c.opacity; c.blurRadius = a.blur?.radius ?? c.blurRadius
            c.font = a.font ?? c.font; c.fontSize = a.font_size ?? c.fontSize; c.padding = a.padding ?? c.padding
            c.cornerRadius = a.corner_radius ?? c.cornerRadius
        }
        if let l = decoded.lyrics {
            c.showTrackTitle = l.show_track_title ?? c.showTrackTitle
            c.showArtwork = l.show_album_art ?? c.showArtwork
            c.followPlayback = l.follow_playback ?? c.followPlayback; c.offsetMS = l.offset_ms ?? c.offsetMS
        }
        guard (260...2000).contains(c.width), (120...2000).contains(c.height),
              (0...1).contains(c.opacity), (10...72).contains(c.fontSize), (0...80).contains(c.padding),
              (0...40).contains(c.cornerRadius), (0...100).contains(c.blurRadius),
              (-10000...10000).contains(c.offsetMS), !c.font.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              c.font.count <= 256,
              [c.background,c.accent,c.text,c.mutedText].allSatisfy(Self.validColor)
        else { throw ConfigError.invalidValue }
        return c
    }
    /// Serializes all supported settings. TOML comments and unknown keys are not retained.
    public func serialized() throws -> String {
        let file = FileConfig(
            window: .init(width: width, height: height, always_on_top: alwaysOnTop,
                          all_spaces: allSpaces, remember_position: rememberPosition),
            appearance: .init(background: background, background_opacity: opacity, blur: .init(radius: blurRadius),
                              accent: accent, text: text, muted_text: mutedText, font: font,
                              font_size: fontSize, padding: padding, corner_radius: cornerRadius),
            lyrics: .init(show_track_title: showTrackTitle, show_album_art: showArtwork, follow_playback: followPlayback,
                          offset_ms: offsetMS)
        )
        let source = try TOMLEncoder().encodeToString(file)
        _ = try Self.parse(source)
        return source + (source.hasSuffix("\n") ? "" : "\n")
    }

    private static func validColor(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 7 && bytes.first == 35 && bytes.dropFirst().allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }
    public static let example = """
    # Lyricise — changes are applied while the app is running.
    [window]
    width = 420
    height = 300
    always_on_top = true
    all_spaces = true
    remember_position = true

    [appearance]
    background = "#1e1e2e"
    background_opacity = 0.75
    blur = 0
    accent = "#b4befe"
    text = "#cdd6f4"
    muted_text = "#6c7086"
    font = "SF Pro"
    font_size = 20
    padding = 16
    corner_radius = 12

    [lyrics]
    show_track_title = true
    show_album_art = false
    follow_playback = true
    offset_ms = 0
    """
}
public enum ConfigError: LocalizedError {
    case invalidValue
    public var errorDescription: String? { "Check colors (#RRGGBB), window size (260–2000 × 120–2000), opacity (0–1), blur (0–100), font size (10–72), padding (0–80), corner radius (0–40), and offset (±10000 ms)." }
}
private struct FileConfig: Codable {
    var window: Window?, appearance: Appearance?, lyrics: Lyrics?
    struct Window: Codable { var width: Double?, height: Double?, always_on_top: Bool?, all_spaces: Bool?, remember_position: Bool? }
    struct Appearance: Codable { var background: String?, background_opacity: Double?, blur: BlurValue?, accent: String?, text: String?, muted_text: String?, font: String?, font_size: Double?, padding: Double?, corner_radius: Double? }
    struct Lyrics: Codable { var show_track_title: Bool?, show_album_art: Bool?, follow_playback: Bool?, offset_ms: Double? }
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
