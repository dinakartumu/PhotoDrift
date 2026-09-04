# PhotoDrift

A macOS menu bar app that automatically shuffles your desktop wallpaper using photos from Apple Photos and Adobe Lightroom.

## Features

- **Menu bar app** -- lives in your menu bar, no dock icon
- **Apple Photos integration** -- browse and select albums from your Photos library
- **Adobe Lightroom integration** -- connect your Lightroom cloud account and pull from Lightroom albums
- **Automatic shuffling** -- set an interval (15 min to 4 hours) and wallpapers change automatically
- **Wallpaper scaling** -- Fill, Fit, Stretch, Center, or Tile display modes
- **Multi-album support** -- select multiple albums from both sources to build a combined pool
- **Smart caching** -- images are cached locally and prefetched in the background
- **Offline fallback** -- falls back to Photos library when network is unavailable
- **Automatic updates** -- checks GitHub once a day and offers new versions in place via Sparkle

## Requirements

- macOS 14.0 or later
- Xcode 16.0+ and Swift 5.9+ (to build from source)

## Install

Download the latest notarized build from [Releases](https://github.com/dinakartumu/PhotoDrift/releases), drag `PhotoDrift.app` to `/Applications`, and launch it. The icon appears in your menu bar.

On first launch PhotoDrift asks for Photos access. Lightroom is optional and configured in Settings.

From 1.2 on, PhotoDrift checks for updates once a day and offers to install them; "Check for Updates..." in the menu does it on demand. The check fetches [`appcast.xml`](appcast.xml) from this repository and downloads the DMG from Releases. No system profile or identifier is sent. Updates are signed with an EdDSA key in addition to the Developer ID signature, so a tampered DMG is refused.

## Building

```sh
git clone https://github.com/dinakartumu/PhotoDrift.git
cd PhotoDrift
open PhotoDrift.xcodeproj
```

Then build and run (Cmd+R). To run the tests:

```sh
xcodebuild test -project PhotoDrift.xcodeproj -scheme PhotoDrift -destination 'platform=macOS'
```

To package a signed, notarized release, see [`Tools/release.sh`](Tools/release.sh). It also regenerates `appcast.xml`; signing the entry needs the Sparkle EdDSA private key in your login Keychain (`generate_keys` from the Sparkle package prints the matching public key, which must equal `SUPublicEDKey` in `Info.plist`).

## Lightroom Setup

Lightroom access uses the Adobe Lightroom API. The bundled client ID points at a public OAuth client — there is no client secret, and PKCE parameters are generated per authorization request rather than being baked into the binary.

To point the app at your own Adobe app instead:

1. Create an app at [Adobe Developer Console](https://developer.adobe.com/console/)
2. Add the Lightroom API and enable the OAuth Web/Native credential
3. Update `clientID`, `redirectURI`, and `callbackScheme` in `PhotoDrift/Lightroom/AdobeConfig.swift`
4. Register the matching URL scheme under `CFBundleURLTypes` in `PhotoDrift/Info.plist`

OAuth tokens are stored in the macOS Keychain, not in the app's database.

## Architecture

Built with native AppKit (no SwiftUI) for a lightweight menu bar experience.

- **SwiftData** for persistence (albums, assets, settings)
- **PhotoKit** for Apple Photos access
- **Adobe Lightroom API** for cloud photo access
- **Combine** for reactive event handling
- **Sparkle 2** for updates, the project's one package dependency

Cached images live in Application Support rather than Caches: macOS reclaims disk space by purging sandboxed apps' container caches and terminates the owning app to do it, and these files back the wallpaper currently on screen.

The app icon is generated rather than hand-drawn — see [`Tools/GenerateAppIcon.swift`](Tools/GenerateAppIcon.swift).

## License

MIT — see [LICENSE](LICENSE).
