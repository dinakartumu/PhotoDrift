import AppKit

enum WallpaperService {
    static func setWallpaper(from url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}
