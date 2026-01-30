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

## Screenshots

_Coming soon_

## Requirements

- macOS 14.0+
- Xcode 15.0+ (to build)

## Building

1. Clone the repository
2. Open `PhotoDrift.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Lightroom Setup

To use Adobe Lightroom integration, you need to configure your own Adobe API credentials:

1. Create an app at [Adobe Developer Console](https://developer.adobe.com/console/)
2. Add the Lightroom API
3. Update the credentials in the Lightroom configuration

## Architecture

Built with native AppKit (no SwiftUI) for a lightweight menu bar experience.

- **SwiftData** for persistence (albums, assets, settings)
- **PhotoKit** for Apple Photos access
- **Adobe Lightroom API** for cloud photo access
- **Combine** for reactive event handling

## License

MIT
