import AppKit

enum WallpaperService {
    static func setWallpaper(from url: URL, scaling: WallpaperScaling = .fitToScreen) throws {
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
        switch scaling {
        case .fillScreen:
            options = [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ]
        case .fitToScreen:
            options = [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: false,
            ]
        case .stretchToFill:
            options = [
                .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                .allowClipping: true,
            ]
        case .center:
            options = [
                .imageScaling: NSImageScaling.scaleNone.rawValue,
                .allowClipping: false,
            ]
        case .tile:
            options = [
                .imageScaling: NSImageScaling.scaleNone.rawValue,
                .allowClipping: false,
            ]
        }

        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }
}
