#!/bin/zsh
# Builds Quo for iPhone for the simulator, unsigned and without iCloud (it
# reads a stand-in folder instead). For a phone, open Quo.xcodeproj in Xcode.
cd "$(dirname "$0")"
xcodegen generate -q
xcodebuild -project Quo.xcodeproj -scheme Quo -destination "platform=iOS Simulator,name=${QUO_SIM:-iPhone 18 Pro Max}" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO QUO_CLOUDKIT=NO build "$@"
