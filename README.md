# Lyricise

A small native Spotify lyrics window for macOS. SwiftUI, native background blur, Catppuccin Mocha, and a lavender current line.

## Run locally

Requires `just` (Homebrew), macOS 27, Xcode 27 (Swift 6.4), Spotify desktop, and Spicetify installed via Homebrew. This is a personal local build, ad-hoc signed rather than notarized.

```sh
just install
```

This builds `build/Lyricise.app`, installs the Spotify companion, restarts Spotify, copies the app to `~/Applications`, and opens it. Existing Spicetify configuration is backed up under `~/.config/lyricise/spicetify-backup-*`; other configured extensions are preserved.

For development:

```sh
just build
just test
```

Open the directory in Zed or open `Package.swift` in Xcode. `Package.resolved` pins the TOML parser dependency.

## Use

- Click and drag the window to move it. Hover to reveal hide/settings controls and the bottom-right resize handle.
- Spotify’s top-left Lyricise button shows or hides the running window, or launches the app when it is closed. Cold launch uses a token-authenticated, socket-activated local helper; macOS starts it only for that request.
- The active lyric stays centered beneath the song heading. Scrolling manually pauses following; “Back to current line” resumes it.
- Open the ellipsis button (or right-click → Quick Settings) for an installed-font picker and live font-size/blur sliders. Slider values save to TOML when released. `appearance.font` accepts a font name; `font_size` accepts a number from 10–72 points.
- Right-click for always-on-top, all Spaces, blur, song heading, album cover, and lyric-following toggles. These settings persist to TOML.
- Click a timed lyric to seek Spotify to that line. Timed lyrics underline on hover and show a pointing-hand cursor; untimed lyrics cannot seek.
- The menu-bar quote icon shows/hides the window, opens Spotify or the configuration, and quits.
- Unsynced lyrics are scrollable; no timing is invented.
- Track changes clear old lyrics. Pause freezes progress; seeking recenters without scrolling through skipped lines.

## Configuration

Edit `~/.config/lyricise/config.toml`. The app creates a commented example on its first launch. Right-click settings rewrite the supported TOML fields; custom comments and unknown keys are not preserved by that rewrite. Changes reload automatically, including atomic saves from editors. Invalid edits retain the last valid settings and show the error in the menu.

```toml
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
```

Window size and remember_position apply at launch; remembered geometry takes precedence. Opacity affects the background tint, keeping text crisp. Blur accepts an integer from 0–100; omitted or 0 means no blur. `20` matches Ghostty’s default enabled intensity. Legacy `true`/`false` remain readable as 20/0. The right-click menu offers intensity presets; TOML accepts exact values. The implementation uses the same private WindowServer blur mechanism as Ghostty, dynamically resolved so unavailable APIs fail safely. Corner radius accepts 0–40 points; the default is 12 points (Ghostty has no explicit radius override). Positive offset advances the lyric timing. Reduce Motion and Reduce Transparency are respected.

## Spotify companion

`companion/lyricise.js` runs inside Spicetify. It reads playback through `Spicetify.Player` and requests lyrics using Spotify's native `Platform.RequestBuilder` (with `CosmosAsync` fallback for older Spotify builds). Spotify credentials stay inside Spotify. There is no separate login, cookie extraction, backend, analytics, or fallback lyrics service.

Normalized playback and lyrics are posted to **127.0.0.1:17389**. Requests require a random per-install bridge key; the installer writes it to `~/.config/lyricise/bridge-token` with owner-only file permissions. That key is only for the local bridge, not a Spotify credential. Do not commit rendered copies of the installed extension.

Spotify's lyrics API is undocumented and Spicetify can need reapplying after Spotify updates. To repair the companion:

```sh
just companion
```

The bridge offers an authenticated `/health` endpoint containing only status, line count, synchronization, playing state, and receipt time. It never returns lyric text or Spotify credentials. A separate launcher on **127.0.0.1:17390** accepts only authenticated `POST /launch` requests and opens the installed app at `~/Applications/Lyricise.app`. Launchd owns its listening socket; no helper process stays running while idle. Background playback polling never launches the app. Its job is `~/Library/LaunchAgents/cam.jsn.lyricise.launcher.plist`.

The companion also polls an authenticated `/command` endpoint for short-lived seek commands, checks the track ID, and ignores duplicates.

## Scope

Spotify desktop is the target. Remote-device playback, public distribution/notarization, login-at-startup, and a menu-bar lyrics display are not part of this build. The original design and mockup are in `PLAN.md` and `plan.html`.

Native window dragging uses [SwiftUI WindowDragGesture](https://developer.apple.com/documentation/swiftui/windowdraggesture). The companion uses the [Spicetify extension API](https://spicetify.app/docs/development/extensions).
