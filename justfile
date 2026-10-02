# Build a local ad-hoc-signed macOS app.
default: build

build:
    ./scripts/build.sh

# Run Swift, Spotify companion, and launcher protocol tests.
test:
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
    node --test companion/lyricise.test.cjs
    python3 scripts/test-launcher.py "$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --show-bin-path)/LyriciseLauncher"

# Install both the app and its Spotify companion, then launch.
install:
    ./scripts/install.sh

# Reapply the companion after a Spotify update.
companion:
    ./scripts/install-companion.py

open:
    open build/Lyricise.app
