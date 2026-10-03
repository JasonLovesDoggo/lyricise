# Lyricise

Spotify lyrics in a floating macOS window.

https://github.com/user-attachments/assets/604661a1-94d8-48f2-93fd-0d8f0ebc78e2

## Install

Requires **macOS 27 or newer**, an **Apple silicon Mac**, [Homebrew](https://brew.sh), and the **Spotify desktop app**.

```sh
curl -fsSL https://lyricise.jsn.cam/install.sh | bash
```

Installs the app in `~/Applications` and connects Spotify. No Xcode needed. The installer asks before making changes; Spotify restarts once. Your preferences and existing Spicetify extensions are preserved.

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
curl -fsSL https://lyricise.jsn.cam/install.sh | bash
```

Some songs have no lyrics or no timing.

## Development

Requires Xcode 27 and `brew install just spicetify-cli`.

```sh
just install # Build and install from source
just build  # Build the app
just test   # Run tests
```
