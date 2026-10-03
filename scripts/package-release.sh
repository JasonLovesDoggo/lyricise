#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -m)" = arm64 ] || { echo 'Build this release on Apple silicon.' >&2; exit 1; }
just build
package=$(mktemp -d "$PWD/build/release.XXXXXX")
trap 'rm -rf -- "$package"' EXIT
ditto build/Lyricise.app "$package/Lyricise.app"
cp scripts/install-companion.py "$package/"
codesign --verify --deep --strict "$package/Lyricise.app"
mkdir -p build/release
archive=Lyricise-macos-arm64.zip
ditto -c -k "$package" "build/release/$archive"
(cd build/release && shasum -a 256 "$archive" > "$archive.sha256")
cp scripts/bootstrap.sh build/release/install.sh
echo 'Release files are in build/release/'
