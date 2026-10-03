#!/bin/bash
# Public installer. Download completely before running; see README.md.
set -Eeuo pipefail
trap 'status=$?; printf "Installation stopped at line %s (exit %s).\n" "$LINENO" "$status" >&2; exit "$status"' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

# Packaging stamps these together; do not fetch a replacement checksum at runtime.
release_version=v0.1.2
release_sha256=871603f17765635fe79c5c26499ca4c99fce12fcd68fd3fe62238769e8f37be6

cleanup() {
  local status=$?
  trap - EXIT ERR
  # If replacement was interrupted after moving the old app, put it back.
  if [ -n "${backup:-}" ] && [ ! -e "$target" ] && [ -d "$backup/Lyricise.app" ]; then
    if ! mv "$backup/Lyricise.app" "$target"; then
      echo "Restore your previous app from $backup/Lyricise.app." >&2
      status=1
    fi
  fi
  [ -z "${staging:-}" ] || rm -rf -- "$staging"
  [ -z "${installer_temp:-}" ] || rm -rf -- "$installer_temp"
  [ -z "${install_lock:-}" ] || rmdir "$install_lock"
  exit "$status"
}

main() {
  local assume_yes=false check_only=false
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
  [ "${os_version%%.*}" -ge 15 ] || { echo 'Lyricise requires macOS 15 or newer.' >&2; return 1; }
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

  printf 'Install Lyricise %s in ~/Applications and connect it to Spotify.\n' "$release_version"
  printf 'Missing Python/Spicetify dependencies will be installed with Homebrew.\nSpotify will restart; existing preferences and extensions are preserved.\n'
  if ! "$assume_yes"; then
    local answer
    if ! { printf 'Continue? [y/N] ' > /dev/tty; read -r answer < /dev/tty; } 2>/dev/null; then
      echo 'No terminal available. Run the downloaded installer with --yes to skip confirmation.' >&2
      return 1
    fi
    case "$answer" in y|Y|yes|YES) ;; *) echo 'Cancelled.'; return 0 ;; esac
  fi

  local base archive actual
  installer_temp=$(mktemp -d "${TMPDIR:-/tmp}/lyricise-install.XXXXXX")
  trap cleanup EXIT
  base="https://github.com/JasonLovesDoggo/lyricise/releases/download/$release_version"
  archive=Lyricise-macos-arm64.zip
  echo 'Downloading Lyricise…'
  # -q must be first: a user's .curlrc must not disable TLS verification.
  curl -q --fail --show-error --silent --location --retry 3 --connect-timeout 15 --max-time 300 --retry-max-time 600 --proto '=https' --proto-redir '=https' "$base/$archive" -o "$installer_temp/$archive"
  actual=$(shasum -a 256 "$installer_temp/$archive" | awk '{ print $1 }')
  [ "$release_sha256" = "$actual" ] || { echo 'Download checksum mismatch. Nothing was installed.' >&2; return 1; }
  ditto -x -k "$installer_temp/$archive" "$installer_temp/package"
  local app="$installer_temp/package/Lyricise.app"
  [ -f "$installer_temp/package/install-companion.py" ] &&
    [ -x "$app/Contents/MacOS/Lyricise" ] &&
    [ -x "$app/Contents/MacOS/LyriciseLauncher" ] &&
    [ -f "$app/Contents/Resources/lyricise.js" ] || {
    echo 'The release archive is incomplete.' >&2; return 1;
  }
  codesign --verify --deep --strict "$app"

  mkdir -p "$HOME/.config/lyricise"
  local lock_path="$HOME/.config/lyricise/install.lock"
  if ! mkdir "$lock_path" 2>/dev/null; then
    echo "Installer lock exists: $lock_path. If no installer is running, remove that directory and retry." >&2
    return 1
  fi
  install_lock=$lock_path

  local dependencies=()
  "$brew_bin" list --versions python >/dev/null 2>&1 || dependencies+=(python)
  "$brew_bin" list --versions spicetify-cli >/dev/null 2>&1 || dependencies+=(spicetify-cli)
  if [ "${#dependencies[@]}" -gt 0 ]; then "$brew_bin" install "${dependencies[@]}"; fi
  local python_bin
  python_bin="$("$brew_bin" --prefix python)/bin/python3"
  local brew_prefix
  brew_prefix=$("$brew_bin" --prefix)
  export PATH="$brew_prefix/bin:$PATH"
  [ -x "$python_bin" ] || { echo "Python was not installed at $python_bin." >&2; return 1; }

  mkdir -p "$HOME/Applications"
  staging=$(mktemp -d "$HOME/Applications/.lyricise-install.XXXXXX")
  ditto "$app" "$staging/Lyricise.app"
  codesign --verify --deep --strict "$staging/Lyricise.app"
  if pgrep -x Lyricise >/dev/null; then
    pkill -x Lyricise
    local attempt
    for attempt in {1..30}; do
      if ! pgrep -x Lyricise >/dev/null; then break; fi
      sleep 0.1
    done
    if pgrep -x Lyricise >/dev/null; then echo 'Quit Lyricise and try again.' >&2; return 1; fi
  fi
  target="$HOME/Applications/Lyricise.app"
  backup=''
  if [ -e "$target" ]; then
    mkdir -p "$HOME/.config/lyricise/backups"
    backup=$(mktemp -d "$HOME/.config/lyricise/backups/app.XXXXXX")
    mv "$target" "$backup/Lyricise.app"
  fi
  # The completed bundle is on the same filesystem, so installation is a rename.
  # cleanup restores the old bundle if this fails or is interrupted.
  mv "$staging/Lyricise.app" "$target"
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
