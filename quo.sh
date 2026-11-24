#!/bin/bash
# Quo: this fork of Search, built under its own name and bundle id, so it
# keeps its own data, settings and WebKit storage beside an installed Search.
#
#   ./quo.sh                  build build/Quo.app
#   ./quo.sh install          build it and put it in /Applications (quits Quo first)
#   ./quo.sh release [0.1.1]  build, notarise and publish the version in
#                             QUO_VERSION on GitHub, which every installed Quo
#                             then updates itself to
#
# Data lives in ~/Library/Application Support/Quo, the defaults under
# com.edinabazi.quo, cookies and site data in WebKit's container for that id.
# Saved passwords are shared with Search through the keychain: each one asks
# for the login password once, since the two are signed by different people.
set -euo pipefail
cd "$(dirname "$0")"
# Its icon: Icon/Quo.icon, made in Icon Composer, with its Dark, Clear and
# Tinted styles. On a Mac without Icon Composer, the older mark instead: a
# soft tile with a Q cut out (Icon/quo-mark.svg), drawn by Icon/icon.swift.
# iCloud sync, once Quo.provisionprofile (git-ignored) is beside this script:
# a Developer ID profile for com.edinabazi.quo with the iCloud container
# iCloud.com.edinabazi.quo and push. Without it, Quo builds as before, with
# folder sync only.
if [ -f Quo.provisionprofile ]; then
  export SEARCH_PROFILE=Quo.provisionprofile SEARCH_ENTITLEMENTS=Quo.entitlements
  # Passkeys (Touch ID, iCloud Keychain, a phone's QR code), the day Apple
  # grants Quo the browser entitlement for them: requested 22 Nov 2026
  # (request 95NPHJ9A9C). Signed in only once the profile carries it — an
  # app claiming a restricted entitlement its profile doesn't is an app
  # macOS won't open — so a profile made after the grant is all it takes.
  # The app turns passkeys on when it finds itself entitled (Prefs.swift).
  PASSKEY_KEY=com.apple.developer.web-browser.public-key-credential
  if security cms -D -i Quo.provisionprofile 2>/dev/null | grep -q "<key>$PASSKEY_KEY</key>"; then
    mkdir -p build
    cp Quo.entitlements build/quo.entitlements
    /usr/libexec/PlistBuddy -c "Add :$PASSKEY_KEY bool true" build/quo.entitlements >/dev/null
    export SEARCH_ENTITLEMENTS=build/quo.entitlements
    echo "passkeys: Quo.provisionprofile grants them, signed in"
  fi
fi
# Updates: Search's own updater, reading Quo's feed instead of Office
# Commun's. Each release is a GitHub release with Quo.zip, Quo.dmg and the
# feed (appcast.json, and the copy signed with the Developer ID); "latest"
# always points at the newest one, so the feed's address never changes.
REPO="razegrowth/Quo"
TEAM="8B6VFDJHA2"
export SEARCH_NAME=Quo SEARCH_BUNDLE_ID=com.edinabazi.quo SEARCH_ICON=Icon/Quo.icon \
  SEARCH_FEEDBACK="https://github.com/$REPO/issues/new" \
  SEARCH_FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.json" \
  SEARCH_FEED_TEAM="$TEAM" SEARCH_NOTARY_PROFILE=quo SEARCH_NOTES=QUO_NOTES.md \
  SEARCH_MARK=Icon/quo-mark.svg SEARCH_MARK_FRACTION=0.56
# How many people use Quo: TelemetryDeck, once a day (Telemetry.swift). The
# app id isn't a secret, it ships inside the app. Every build but a release
# sends as a test, which TelemetryDeck keeps out of the real numbers.
export SEARCH_TELEMETRY_APP=AA491615-7111-480E-8F62-9CF27ED5EB91 SEARCH_TELEMETRY_NAMESPACE=com.razegrowth
[ "${1:-}" = "release" ] || export SEARCH_TELEMETRY_TEST=1
# Quo's version, and what's new in it (QUO_NOTES.md, newest first, one
# paragraph each: the first is the line under the version in Settings).
export SEARCH_VERSION="$(tr -d '[:space:]' < QUO_VERSION)"

if [ "${1:-}" = "release" ]; then
  # The version named, if one is, is the one in QUO_VERSION: a release is
  # built from what's committed, version and notes with it.
  if [ -n "${2:-}" ] && [ "$2" != "$SEARCH_VERSION" ]; then
    echo "release: QUO_VERSION says $SEARCH_VERSION — set it to $2, add \"## $2\" to QUO_NOTES.md, commit and push" >&2
    exit 1
  fi
  TAG="v$SEARCH_VERSION"
  # What a release needs, checked before anything is built.
  [ -f Quo.provisionprofile ] || { echo "release: Quo.provisionprofile is missing — without it Quo ships without iCloud" >&2; exit 1; }
  xcrun notarytool history --keychain-profile quo >/dev/null 2>&1 \
    || { echo "release: no notarytool profile \"quo\" — run: xcrun notarytool store-credentials quo --apple-id <you> --team-id $TEAM" >&2; exit 1; }
  gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
    && { echo "release: $TAG is out already — ./quo.sh release <next version>" >&2; exit 1; }
  grep -q "^## $SEARCH_VERSION\( \|$\)" QUO_NOTES.md \
    || { echo "release: QUO_NOTES.md has no \"## $SEARCH_VERSION\" — say what's new in it first" >&2; exit 1; }
  [ -z "$(git status --porcelain)" ] || { echo "release: commit first — a release is built from what's committed" >&2; exit 1; }
  git fetch -q origin
  git merge-base --is-ancestor HEAD "origin/$(git rev-parse --abbrev-ref HEAD)" \
    || { echo "release: push first — the release's tag goes on this commit" >&2; exit 1; }
  SEARCH_DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG" ./build.sh release ship
  # The signed feed has to hold up before it goes out: a broken one stops
  # every Quo's updates without a word.
  CHECK="$(mktemp -d)"
  ditto -x -k build/appcast.json.zip "$CHECK"
  codesign --verify -R="anchor apple generic and identifier \"com.edinabazi.quo.appcast\" and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"$TEAM\"" "$CHECK/appcast.json" \
    || { rm -rf "$CHECK"; echo "release: the signed feed doesn't verify — not publishing" >&2; exit 1; }
  cmp -s "$CHECK/appcast.json" build/appcast.json || { rm -rf "$CHECK"; echo "release: the signed feed isn't build/appcast.json" >&2; exit 1; }
  rm -rf "$CHECK"
  # The version's own section of QUO_NOTES.md, which has to be there.
  NOTESFILE="$(mktemp)"
  awk -v v="$SEARCH_VERSION" '/^## / { if (have) exit; have = ($2 == v); next } have' QUO_NOTES.md \
    | sed -e '/./,$!d' > "$NOTESFILE"
  gh release create "$TAG" --repo "$REPO" --target "$(git rev-parse HEAD)" --latest \
    --title "Quo $SEARCH_VERSION" --notes-file "$NOTESFILE" \
    build/Quo.dmg build/Quo.zip build/appcast.json build/appcast.json.zip
  rm -f "$NOTESFILE"
  echo "released: Quo $SEARCH_VERSION — https://github.com/$REPO/releases/tag/$TAG"
  exit 0
fi

./build.sh release app
if [ "${1:-}" = "install" ]; then
  osascript -e 'tell application id "com.edinabazi.quo" to quit' 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Quo.app
  cp -R build/Quo.app /Applications/Quo.app
  echo "installed: /Applications/Quo.app"
fi
