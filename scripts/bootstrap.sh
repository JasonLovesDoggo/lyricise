#!/bin/bash
# Public installer. Run with: curl -fsSL https://lyricise.jsn.cam/install.sh | bash
set -euo pipefail

main() {
  local version=v0.1.0 assume_yes=false check_only=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes) assume_yes=true ;;
      --check) check_only=true ;;
      --help|-h)
        printf 'Install Lyricise and its Spotify companion.\n\nOptions: --yes (skip confirmation), --check (check prerequisites only)\n'
        return 0 ;;
      *) printf 'Unknown option: %s\n' "$1" >&2; return 1 ;;
    esac
    shift
  done

  [ "$(uname -s)" = Darwin ] || { echo 'Lyricise requires macOS.' >&2; return 1; }
  [ "$(uname -m)" = arm64 ] || { echo 'This release requires an Apple silicon Mac.' >&2; return 1; }
  local os_version
  os_version=$(sw_vers -productVersion)
  [ "${os_version%%.*}" -ge 27 ] || { echo 'Lyricise requires macOS 27 or newer.' >&2; return 1; }
  [ "$(id -u)" -ne 0 ] || { echo 'Run this installer as yourself, without sudo.' >&2; return 1; }
  local spotify_app=/Applications/Spotify.app
  if [ ! -d "$spotify_app" ]; then spotify_app="$HOME/Applications/Spotify.app"; fi
  [ -d "$spotify_app" ] || {
    echo 'Install and open the Spotify desktop app first: https://www.spotify.com/download/mac/' >&2
    return 1
  }

  local brew_bin
  brew_bin=$(command -v brew || true)
  if [ -z "$brew_bin" ] && [ -x /opt/homebrew/bin/brew ]; then brew_bin=/opt/homebrew/bin/brew; fi
  [ -n "$brew_bin" ] || { echo 'Install Homebrew from https://brew.sh, then run this command again.' >&2; return 1; }
  if "$check_only"; then
    echo 'Ready: macOS, Apple silicon, Spotify and Homebrew found. No changes made.'
    return 0
  fi

  printf 'Install Lyricise %s in ~/Applications and connect it to Spotify.\n' "$version"
  printf 'Missing Python/Spicetify dependencies will be installed with Homebrew.\nSpotify will restart; existing preferences and extensions are preserved.\n'
  if ! "$assume_yes"; then
    local answer
    if ! { printf 'Continue? [y/N] ' > /dev/tty; read -r answer < /dev/tty; } 2>/dev/null; then
      echo 'No terminal available. Rerun with: bash -s -- --yes' >&2
      return 1
    fi
    case "$answer" in y|Y|yes|YES) ;; *) echo 'Cancelled.'; return 0 ;; esac
  fi

  local base archive expected actual
  installer_temp=$(mktemp -d "${TMPDIR:-/tmp}/lyricise-install.XXXXXX")
  trap 'rm -rf -- "$installer_temp"' EXIT
  base="https://github.com/JasonLovesDoggo/lyricise/releases/download/$version"
  archive=Lyricise-macos-arm64.zip
  echo 'Downloading Lyricise…'
  curl --fail --show-error --silent --location --retry 3 --proto '=https' --proto-redir '=https' "$base/$archive" -o "$installer_temp/$archive"
  curl --fail --show-error --silent --location --retry 3 --proto '=https' --proto-redir '=https' "$base/$archive.sha256" -o "$installer_temp/checksum"
  expected=$(awk 'NR == 1 { print $1 }' "$installer_temp/checksum")
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { echo 'Invalid release checksum.' >&2; return 1; }
  actual=$(shasum -a 256 "$installer_temp/$archive" | awk '{ print $1 }')
  [ "$expected" = "$actual" ] || { echo 'Download checksum mismatch. Nothing was installed.' >&2; return 1; }
  ditto -x -k "$installer_temp/$archive" "$installer_temp/package"
  local app="$installer_temp/package/Lyricise.app"
  [ -f "$installer_temp/package/install-companion.py" ] && [ -x "$app/Contents/MacOS/Lyricise" ] || {
    echo 'The release archive is incomplete.' >&2; return 1;
  }
  codesign --verify --deep --strict "$app"

  local dependencies=()
  "$brew_bin" list --versions python >/dev/null 2>&1 || dependencies+=(python)
  "$brew_bin" list --versions spicetify-cli >/dev/null 2>&1 || dependencies+=(spicetify-cli)
  if [ "${#dependencies[@]}" -gt 0 ]; then "$brew_bin" install "${dependencies[@]}"; fi
  local python_bin
  python_bin="$("$brew_bin" --prefix python)/bin/python3"
  export PATH="$("$brew_bin" --prefix)/bin:$PATH"

  mkdir -p "$HOME/Applications"
  if pgrep -x Lyricise >/dev/null; then
    pkill -x Lyricise
    local attempt
    for attempt in {1..30}; do
      if ! pgrep -x Lyricise >/dev/null; then break; fi
      sleep 0.1
    done
    if pgrep -x Lyricise >/dev/null; then echo 'Quit Lyricise and try again.' >&2; return 1; fi
  fi
  local target="$HOME/Applications/Lyricise.app" backup=''
  if [ -e "$target" ]; then
    mkdir -p "$HOME/.config/lyricise/backups"
    backup=$(mktemp -d "$HOME/.config/lyricise/backups/app.XXXXXX")
    mv "$target" "$backup/Lyricise.app"
  fi
  if ! ditto "$app" "$target"; then
    rm -rf -- "$target"
    if [ -n "$backup" ]; then mv "$backup/Lyricise.app" "$target"; fi
    echo 'App installation failed; the previous app was restored.' >&2
    return 1
  fi
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
  echo 'Connecting Spotify…'
  if ! "$python_bin" "$installer_temp/package/install-companion.py" --app "$target" --spotify-app "$spotify_app"; then
    echo 'Lyricise is installed, but Spotify setup failed. Fix the error above, then rerun this installer.' >&2
    return 1
  fi
  open "$target"
  echo 'Installed. Play a song in Spotify to see its lyrics.'
}

main "$@"
