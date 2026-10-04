#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
if pgrep -x Lyricise >/dev/null; then
  pkill -x Lyricise
  for attempt in {1..30}; do
    if ! pgrep -x Lyricise >/dev/null; then break; fi
    sleep 0.1
  done
fi
mkdir -p "$HOME/Applications"
ditto build/Lyricise.app "$HOME/Applications/Lyricise.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Lyricise.app"
./scripts/install-companion.py --app "$HOME/Applications/Lyricise.app"
open "$HOME/Applications/Lyricise.app"
