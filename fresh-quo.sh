#!/bin/bash
# Quo as someone installing it for the first time sees it, beside the Quo you
# use, and without touching it.
#
#   ./fresh-quo.sh          wipe "Quo Fresh", build it from this checkout, open it
#   ./fresh-quo.sh again    open it as it was left, no wipe, no build
#   ./fresh-quo.sh wipe     wipe it and stop
#
# "Quo Fresh" is Quo built under a name and bundle id of its own
# (com.edinabazi.quo.fresh), so it has its own folder in Application Support,
# its own settings and its own WebKit data (cookies, sign-ins, caches). It is
# not a test run: it takes exactly the defaults a newcomer gets, the welcome
# included. Wiping those is a fresh install; your own Quo's folder, settings,
# sessions and sign-ins (com.edinabazi.quo, "Quo") are never in reach.
#
# What it can't have: iCloud (its entitlement is for Quo's own bundle id, so
# sync offers a folder only), updates, and usage counts (no telemetry id).
set -euo pipefail
cd "$(dirname "$0")"

NAME="Quo Fresh"
ID="com.edinabazi.quo.fresh"
APP="build/$NAME.app"
LIB="$HOME/Library"

wipe() {
  # Quit a copy that's open, then remove everything it wrote.
  osascript -e "tell application id \"$ID\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$APP/Contents/MacOS" >/dev/null || break; sleep 0.5; done
  rm -rf "$LIB/Application Support/$NAME" \
         "$LIB/WebKit/$ID" \
         "$LIB/Caches/$ID" \
         "$LIB/HTTPStorages/$ID" "$LIB/HTTPStorages/$ID.binarycookies" \
         "$LIB/Saved Application State/$ID.savedState"
  defaults delete "$ID" >/dev/null 2>&1 || true
  echo "\"$NAME\" wiped: a first launch next time"
}

case "${1:-}" in
  again) ;;
  wipe) wipe; exit 0 ;;
  *)
    wipe
    SEARCH_NAME="$NAME" SEARCH_BUNDLE_ID="$ID" SEARCH_ICON="Icon/Quo.icon" ./build.sh
    ;;
esac

[ -d "$APP" ] || { echo "No $APP yet: run ./fresh-quo.sh to build it" >&2; exit 1; }
open -n "$APP"
