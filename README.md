# Lyricise

Spotify lyrics in a small, floating macOS window. Drag it anywhere, resize it, and click a lyric to jump to that moment.

https://github.com/user-attachments/assets/604661a1-94d8-48f2-93fd-0d8f0ebc78e2

## Install

Requires **macOS 27**, **Xcode 27**, and the **Spotify desktop app**. Open Xcode once to finish its setup.

From this repo:

```sh
brew install just spicetify-cli
just install
```

This builds Lyricise, installs it in `~/Applications`, and sets up its Spotify companion. Spotify restarts once. Existing Spicetify settings are backed up and other extensions are kept.

This is currently a local source install; a signed, prebuilt download is not available yet.

## Use

- Play a song in Spotify. The current lyric stays centered.
- Click Spotify’s Lyricise button to open or hide the window.
- Drag the window to move it; use the bottom-right handle to resize.
- Hover for the **×** and **…** controls. Right-click for common settings.
- In quick settings, choose a font and adjust size or blur. Click either number to type an exact value, such as `20pt` or `40`.
- Click a lyric to seek. Scroll to browse; **Back to current line** resumes following.

## Customize

Click **Open Config** in settings, or edit:

```text
~/.config/lyricise/config.toml
```

Browse the [theme gallery](docs/THEMES.md) for 14 presets with screenshots and ready-to-copy TOML.

Changes reload automatically. The [default config](Sources/LyriciseCore/Resources/default.toml) lists every setting: colors, opacity, blur, font, corner radius, artwork, and window behavior. Settings changed in the app are saved to the same file.

## Troubleshooting

If lyrics stop working after a Spotify update, reapply the companion:

```sh
just companion
```

Some songs have no lyrics or no timing. Spotify credentials stay inside Spotify; the companion talks to Lyricise over an authenticated connection on your Mac.

## Development

```sh
just build  # Build the app
just test   # Swift, bridge, companion, and launcher tests
```

[Hummingbird](https://github.com/hummingbird-project/hummingbird) local bridge, and a [Spicetify](https://spicetify.app/) companion. Open `Package.swift` in Xcode or this folder in your editor.
