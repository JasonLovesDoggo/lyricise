#!/bin/bash
# Bundled entry point for first-run setup and repairs from the app.
set -euo pipefail

app=''
spotify_app=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || { echo 'Missing app path.' >&2; exit 1; }
      app=$2
      shift ;;
    --spotify-app)
      [ "$#" -ge 2 ] || { echo 'Missing Spotify app path.' >&2; exit 1; }
      spotify_app=$2
      shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

[ "$(uname -s)" = Darwin ] || { echo 'Lyricise requires macOS.' >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || { echo 'Run Spotify setup without sudo.' >&2; exit 1; }
[ -n "$app" ] && [ -f "$app/Contents/Resources/install-companion.py" ] &&
  [ -f "$app/Contents/Resources/lyricise.js" ] && [ -x "$app/Contents/MacOS/LyriciseLauncher" ] || {
  echo 'Spotify setup is missing from this app. Reinstall Lyricise and try again.' >&2; exit 1;
}

if [ -z "$spotify_app" ]; then
  spotify_app=/Applications/Spotify.app
  if [ ! -d "$spotify_app" ]; then spotify_app="$HOME/Applications/Spotify.app"; fi
fi
[ -d "$spotify_app" ] || {
  echo 'Install the Spotify desktop app, open it and sign in, then try again: https://www.spotify.com/download/mac/' >&2
  exit 1
}
[ -f "$HOME/Library/Application Support/Spotify/prefs" ] || {
  echo 'Open Spotify and sign in first. Leave it open for a minute, then try connecting again.' >&2
  exit 1
}

brew_bin=$(command -v brew || true)
if [ -z "$brew_bin" ] && [ -x /opt/homebrew/bin/brew ]; then brew_bin=/opt/homebrew/bin/brew; fi
[ -n "$brew_bin" ] || { echo 'Install Homebrew from https://brew.sh, then try connecting again.' >&2; exit 1; }

mkdir -p "$HOME/.config/lyricise"
lock="$HOME/.config/lyricise/install.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "Another Lyricise setup may be running. If it has stopped, remove $lock and try again." >&2
  exit 1
fi
trap 'rmdir "$lock"' EXIT

# GUI apps do not inherit a terminal's Homebrew PATH.
brew_prefix=$("$brew_bin" --prefix)
export PATH="$brew_prefix/bin:$PATH"
export HOMEBREW_NO_ASK=1
dependencies=()
"$brew_bin" list --versions python@3.14 >/dev/null 2>&1 || dependencies+=(python@3.14)
if "$brew_bin" list --versions spicetify-cli >/dev/null 2>&1; then
  # Spotify updates can require a newer Spicetify. Respect deliberately pinned versions.
  pinned=$("$brew_bin" list --pinned)
  if ! printf '%s\n' "$pinned" | grep -qx spicetify-cli; then
    "$brew_bin" upgrade spicetify-cli
  else
    echo 'Spicetify is pinned in Homebrew; keeping its current version.'
  fi
else
  dependencies+=(spicetify-cli)
fi
if [ "${#dependencies[@]}" -gt 0 ]; then "$brew_bin" install "${dependencies[@]}"; fi
python_bin="$("$brew_bin" --prefix python@3.14)/bin/python3"
"$python_bin" "$app/Contents/Resources/install-companion.py" --app "$app" --spotify-app "$spotify_app"
