import Testing
import AppKit
@testable import PhotoDrift

struct WallpaperScalingOptionTests {
    @Test func fillScreenOptions() {
        let opts = WallpaperService.desktopImageOptions(for: .fillScreen)
        let scaling = opts[.imageScaling] as? UInt
        let clipping = opts[.allowClipping] as? Bool
        #expect(scaling == NSImageScaling.scaleProportionallyUpOrDown.rawValue)
        #expect(clipping == true)
        #expect(opts.count == 2)
    }

    @Test func fitToScreenOptions() {
        let opts = WallpaperService.desktopImageOptions(for: .fitToScreen)
        let scaling = opts[.imageScaling] as? UInt
        let clipping = opts[.allowClipping] as? Bool
        #expect(scaling == NSImageScaling.scaleProportionallyUpOrDown.rawValue)
        #expect(clipping == false)
        #expect(opts.count == 2)
    }

    @Test func stretchToFillOptions() {
        let opts = WallpaperService.desktopImageOptions(for: .stretchToFill)
        let scaling = opts[.imageScaling] as? UInt
        let clipping = opts[.allowClipping] as? Bool
        #expect(scaling == NSImageScaling.scaleAxesIndependently.rawValue)
        #expect(clipping == true)
        #expect(opts.count == 2)
    }

    @Test func centerOptions() {
        let opts = WallpaperService.desktopImageOptions(for: .center)
        let scaling = opts[.imageScaling] as? UInt
        let clipping = opts[.allowClipping] as? Bool
        #expect(scaling == NSImageScaling.scaleNone.rawValue)
        #expect(clipping == false)
        #expect(opts.count == 2)
    }

    @Test func tileOptions() {
        let opts = WallpaperService.desktopImageOptions(for: .tile)
        let scaling = opts[.imageScaling] as? UInt
        let clipping = opts[.allowClipping] as? Bool
        #expect(scaling == NSImageScaling.scaleNone.rawValue)
        #expect(clipping == false)
        #expect(opts.count == 2)
    }

    @Test func allCasesProduceExactlyTwoKeys() {
        for scaling in WallpaperScaling.allCases {
            let opts = WallpaperService.desktopImageOptions(for: scaling)
            #expect(opts.count == 2)
        }
    }

    @Test func appleScriptEscapesPathCharacters() {
        let input = #"/Users/test/Wallpapers/He said "hi"\set.jpg"#
        let escaped = WallpaperService.escapeForAppleScript(input)
        #expect(escaped == #"/Users/test/Wallpapers/He said \"hi\"\\set.jpg"#)
    }

    @Test func allDesktopsAppleScriptUsesPosixFilePath() {
        let url = URL(fileURLWithPath: "/Users/test/Pictures/wallpaper 1.jpg")
        let source = WallpaperService.allDesktopsAppleScript(for: url)
        #expect(source.contains(#"tell application id "com.apple.systemevents""#))
        #expect(source.contains(#"repeat with desk in desktops"#))
        #expect(source.contains(#"set picture of desk to POSIX file "/Users/test/Pictures/wallpaper 1.jpg""#))
    }
}
