# Lyricise

Spotify lyrics in a floating macOS window.

https://github.com/user-attachments/assets/604661a1-94d8-48f2-93fd-0d8f0ebc78e2

## Install

Requires **macOS 27**, **Xcode 27**, and the **Spotify desktop app**. Open Xcode once to finish its setup.

From this repo:

```sh
brew install just spicetify-cli
just install
```

Installs Lyricise in `~/Applications` and sets up its Spotify companion. Spotify restarts once; existing Spicetify settings and extensions are preserved.

## Use

- Play a song in Spotify. The current lyric stays centered.
- Click Spotify’s Lyricise button to open or hide the window.
- Drag the window to move it; use the bottom-right handle to resize.
- Hover for the **×** and **…** controls. Right-click for common settings.
- Click a lyric to seek. Scroll to browse; **Back to current line** resumes following.

## Customize

Click **Open Config** in settings, or edit:

```text
~/.config/lyricise/config.toml
```

Browse the [theme gallery](docs/THEMES.md).

Changes reload automatically. See the [default config](Sources/LyriciseCore/Resources/default.toml) for all settings.

## Troubleshooting

If lyrics stop working after a Spotify update, reapply the companion:

```sh
just companion
```

Some songs have no lyrics or no timing.

## Development

```sh
just build  # Build the app
just test   # Run tests
```
