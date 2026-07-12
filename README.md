# Calibre for iOS

Native iOS client for Calibre, including its SideStore distribution source.

## SideStore

Add this source URL in SideStore:

```
https://raw.githubusercontent.com/eytanerez/calibre-iOS-sidestore/main/source.json
```

Release IPAs are unsigned build artifacts intended for SideStore to re-sign with the installing user's Apple ID.

## Build and package

Requirements: Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
./Scripts/build-ipa.sh
```

The script performs an unsigned generic-device Release build and creates `build/Calibre.ipa` with the standard `Payload/Calibre.app` layout.
