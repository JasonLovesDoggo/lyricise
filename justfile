# Build a local ad-hoc-signed macOS app.
default: build

build:
    ./scripts/build.sh

# Run Swift and Spotify companion tests.
test:
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
    node --test companion/lyricise.test.cjs

# Install both the app and its Spotify companion, then launch.
install:
    ./scripts/install.sh

# Reapply the companion after a Spotify update.
companion:
    ./scripts/install-companion.py

open:
    open build/Lyricise.app
