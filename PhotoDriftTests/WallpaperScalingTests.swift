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
        #expect(source.contains(#"tell application "System Events""#))
        #expect(source.contains(#"repeat with desk in desktops"#))
        #expect(source.contains(#"set picture of desk to POSIX file "/Users/test/Pictures/wallpaper 1.jpg""#))
    }

    @Test func recognizesADesktopAlreadyShowingTheWallpaper() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsShowing-\(UUID().uuidString)")
        let real = root.appendingPathComponent("real")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = real.appendingPathComponent("abc.jpg")
        try Data("photo".utf8).write(to: url)
        let fill = WallpaperService.desktopImageOptions(for: .fillScreen)
        #expect(WallpaperService.isShowing(url, scaling: .fillScreen, currentURL: url, currentOptions: fill))
        // The system may report a different spelling of the same file, e.g. /var vs /private/var.
        #expect(WallpaperService.isShowing(url, scaling: .fillScreen,
                                           currentURL: link.appendingPathComponent("abc.jpg"), currentOptions: fill))
        // Tile and center share options, so either one counts as already applied.
        #expect(WallpaperService.isShowing(url, scaling: .tile, currentURL: url,
                                           currentOptions: WallpaperService.desktopImageOptions(for: .center)))
        #expect(!WallpaperService.isShowing(url, scaling: .center, currentURL: url, currentOptions: fill))
        #expect(!WallpaperService.isShowing(url, scaling: .fillScreen,
                                            currentURL: URL(fileURLWithPath: "/tmp/PhotoDriftWallpapers/other.jpg"), currentOptions: fill))
        #expect(!WallpaperService.isShowing(url, scaling: .fillScreen, currentURL: nil, currentOptions: fill))
    }

    @Test func allDesktopsAppleScriptSetsEachDesktopOnce() {
        let source = WallpaperService.allDesktopsAppleScript(for: URL(fileURLWithPath: "/tmp/wallpaper.jpg"))
        #expect(source.components(separatedBy: "set picture of desk").count - 1 == 1)
    }
}

struct WallpaperImportTests {
    @Test func unrelatedWallpaperIsPreservedEvenWhenSandboxCannotReadIt() {
        #expect(WallpaperService.canInitializeWallpaper(at: nil))
        #expect(WallpaperService.canInitializeWallpaper(at: WallpaperStore.defaultDirectory.appendingPathComponent("missing.jpg")))
        #expect(!WallpaperService.canInitializeWallpaper(at: URL(fileURLWithPath: "/Users/another-user/Pictures/private.jpg")))
        #expect(!WallpaperService.canInitializeWallpaper(at: URL(fileURLWithPath: "/System/Library/Desktop Pictures/default.heic")))
        #expect(!WallpaperService.canInitializeWallpaper(at: URL(string: "wallpaper://custom")))
    }

    @Test func recognizesOnlyOwnedWallpaperDirectories() {
        for directory in [ImageCacheManager.previousCacheDirectory, ImageCacheManager.legacyCacheDirectory, WallpaperStore.defaultDirectory] {
            #expect(WallpaperService.ownsWallpaper(at: directory.appendingPathComponent("wallpaper.jpg")))
        }
        #expect(!WallpaperService.ownsWallpaper(at: URL(fileURLWithPath: "/Users/example/Pictures/custom.jpg")))
        #expect(!WallpaperService.ownsWallpaper(at: WallpaperStore.defaultDirectory.appendingPathComponent("../unrelated.jpg")))
        #expect(!WallpaperService.ownsWallpaper(at: ImageCacheManager.defaultCacheDirectory.appendingPathComponent("download.jpg")))
    }

    @Test func restoresScalingFromSystemOptions() {
        for scaling in [WallpaperScaling.fillScreen, .fitToScreen, .stretchToFill, .center] {
            #expect(WallpaperService.scaling(from: WallpaperService.desktopImageOptions(for: scaling)) == scaling)
        }
        #expect(WallpaperService.scaling(from: [:]) == .fitToScreen)
    }
}
