# Quo for iPhone

A quiet iPhone browser in the spirit of Arc Search, without any of its AI, that keeps up with Quo on the Mac through your own iCloud. SwiftUI and WKWebView, iOS 18 and later, iPhone only.

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and isn't kept in git.

```bash
cd iOS && xcodegen generate && open Quo.xcodeproj
```

For the simulator, unsigned and without iCloud:

```bash
iOS/build.sh
```

The app is then in `iOS/build/Build/Products/Debug-iphonesimulator/Quo.app`.

## What's shared with the Mac

The iPhone target builds five of the Mac's own files from `Sources/Search`, so the two can't drift:

- `SyncMerge.swift`: the sync format and its merge, and how spaces, pins and bookmarks are made from it (`SyncItems.applySpaces`, `applyPins`, `applyBookmarks`).
- `SyncRecord.swift`: what a CloudKit record looks like, its zone, type, name and encrypted fields.
- `SyncTabs.swift`: open tabs as each device publishes them, and how the others' are read.
- `FilterList.swift`: the EasyList converter the blocker uses.
- `Engine.swift`: the search engines.

`Quo/Sync/MacTypes.swift` declares the few Mac types `SyncMerge.swift` is written against (`Space`, `PinDef`, `Bookmark` and the like), with the same stored fields and Codable shapes. If one of those changes on the Mac, change it there too; the build fails where the shape no longer fits.

## Sync

The iPhone is one more device in the same records: container `iCloud.com.edinabazi.quo`, private database, zone `Sync`, record type `SyncFile`, one record per device per scope, its content in CloudKit's encrypted fields. It reads every Mac's file in the Personal profile's scope, merges them as a Mac does, and writes its own, so a pin made on the iPhone reaches the Mac. It never writes the Mac's settings (`app` scope), only reads its search engine from them.

Open tabs are handed over, never merged: each device writes its own in the scope `tabs-profile-<id>` (the iPhone's is the Personal profile's), at most every twenty seconds and at once when it goes to the background, and reads the others'. The spaces sheet shows each Mac's tabs under the space they're open in; the Mac shows the iPhone's in ⌘T. Incognito tabs are never written. A Quo from before passes the scope over.

The build must use CloudKit's Production environment, as the Mac's Developer ID build does (`com.apple.developer.icloud-container-environment` in `Quo/Quo.entitlements`), or the two never see each other's records.

### The stand-in

A build without the iCloud entitlement (`QUO_CLOUDKIT=NO`, as `build.sh` makes) reads a folder instead: `Application Support/Quo/StandIn` in the app's container, or the folder `QUO_STANDIN` names. It takes the Mac's test records (`<name>.record`, each `{scope, data}`, a Mac's open tabs among them as `tabs-profile-<id>.<device>.record`) and a copy of the Mac's own cache, `~/Library/Application Support/Quo/sync-cloud.json`, and writes the iPhone's own record beside them. To see your Mac's spaces in the simulator:

```bash
C=$(xcrun simctl get_app_container booted com.edinabazi.quo.ios data)
mkdir -p "$C/Library/Application Support/Quo/StandIn"
cp ~/Library/Application\ Support/Quo/sync-cloud.json "$C/Library/Application Support/Quo/StandIn/"
```

## On a phone

1. In the Apple Developer portal (team 8B6VFDJHA2), Identifiers › +: an App ID `com.edinabazi.quo.ios` with **iCloud** (CloudKit, container `iCloud.com.edinabazi.quo`, the Mac's) and **Push Notifications**. Or let Xcode do it: open the project, choose the team under Signing & Capabilities, and build to the phone with automatic signing.
2. Build and run from Xcode. The first launch asks nothing of iCloud; it uses the Apple Account the phone is signed in to.
3. On the Mac, Quo's Settings › Sync must be on iCloud, with the same Apple Account.

Silent pushes from CloudKit's Production environment go to a production push token, so a development build may not hear the Mac's changes at once; it syncs on opening and every minute anyway. A TestFlight or App Store build hears them.

To try it on the phone before the App ID exists, build without iCloud: `QUO_CLOUDKIT=NO` and `CODE_SIGN_ENTITLEMENTS=` in the build settings. Everything but sync works.

## Being the default browser

iOS lists an app under Settings › Apps › Default Browser App only with Apple's `com.apple.developer.web-browser` entitlement, which Apple grants on request (the default browser entitlement form on developer.apple.com). Until then, Set Quo as Default Browser opens Quo's page in Settings.

## Debugging

`QUO_TRACE=1` logs each page's decide, start, commit and finish times as `QUOTRACE` lines, and why Reader found nothing.
