#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release
APP="$PWD/build/Lyricise.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN=$(swift build -c release --show-bin-path)
cp "$BIN/Lyricise" "$APP/Contents/MacOS/Lyricise"
cp "$BIN/LyriciseLauncher" "$APP/Contents/MacOS/LyriciseLauncher"
# SwiftPM resources must ship with the app, not depend on the build directory.
for resource in "$BIN"/*.bundle; do
    [ -d "$resource" ] || continue
    ditto "$resource" "$APP/Contents/Resources/$(basename "$resource")"
done
codesign --force --sign - "$APP/Contents/MacOS/LyriciseLauncher"
swift scripts/render-icon.swift "$PWD/build"
iconutil -c icns "$PWD/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png Resources/Logo.svg "$APP/Contents/Resources/"
cp companion/lyricise.js "$APP/Contents/Resources/lyricise.js"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Lyricise</string>
<key>CFBundleIdentifier</key><string>cam.jsn.lyricise</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Lyricise</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>cam.jsn.lyricise.launch</string><key>CFBundleURLSchemes</key><array><string>lyricise</string></array></dict></array>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
