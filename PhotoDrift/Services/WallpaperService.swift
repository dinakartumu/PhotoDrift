import AppKit

enum WallpaperService {
    static func desktopImageOptions(for scaling: WallpaperScaling) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        switch scaling {
        case .fillScreen:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ]
        case .fitToScreen:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: false,
            ]
        case .stretchToFill:
            return [
                .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                .allowClipping: true,
            ]
        case .center:
            return [
                .imageScaling: NSImageScaling.scaleNone.rawValue,
                .allowClipping: false,
            ]
        case .tile:
            return [
                .imageScaling: NSImageScaling.scaleNone.rawValue,
                .allowClipping: false,
            ]
        }
    }

    static func setWallpaper(from url: URL, scaling: WallpaperScaling = .fitToScreen) throws {
        let options = desktopImageOptions(for: scaling)
        for screen in NSScreen.screens {
            var opts = options
            opts[.fillColor] = NSColor.black
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: opts)
        }
    }
}
