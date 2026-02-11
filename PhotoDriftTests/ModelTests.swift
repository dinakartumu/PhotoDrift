import Testing
import SwiftData
@testable import PhotoDrift

func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([Album.self, Asset.self, AppSettings.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

struct SourceTypeTests {
    @Test func rawValueRoundtrip() {
        let photos = SourceType.applePhotos
        let lr = SourceType.lightroomCloud
        #expect(SourceType(rawValue: photos.rawValue) == .applePhotos)
        #expect(SourceType(rawValue: lr.rawValue) == .lightroomCloud)
    }

    @Test func rawValues() {
        #expect(SourceType.applePhotos.rawValue == "applePhotos")
        #expect(SourceType.lightroomCloud.rawValue == "lightroomCloud")
    }

    @Test func invalidRawValueReturnsNil() {
        #expect(SourceType(rawValue: "invalid") == nil)
    }
}

struct WallpaperScalingTests_Model {
    @Test func rawValues() {
        #expect(WallpaperScaling.fillScreen.rawValue == "fillScreen")
        #expect(WallpaperScaling.fitToScreen.rawValue == "fitToScreen")
        #expect(WallpaperScaling.stretchToFill.rawValue == "stretchToFill")
        #expect(WallpaperScaling.center.rawValue == "center")
        #expect(WallpaperScaling.tile.rawValue == "tile")
    }

    @Test func caseIterableCount() {
        #expect(WallpaperScaling.allCases.count == 5)
    }

    @Test func displayNameForAllCases() {
        let expected: [WallpaperScaling: String] = [
            .fillScreen: "Fill Screen",
            .fitToScreen: "Fit to Screen",
            .stretchToFill: "Stretch to Fill",
            .center: "Center",
            .tile: "Tile",
        ]
        for (scaling, name) in expected {
            #expect(scaling.displayName == name)
        }
    }
}

struct AppSettingsTests {
    @Test func defaults() throws {
        let settings = AppSettings()
        #expect(settings.shuffleIntervalMinutes == 30)
        #expect(settings.photosEnabled == true)
        #expect(settings.lightroomEnabled == false)
        #expect(settings.wallpaperScaling == .fitToScreen)
    }

    @Test func wallpaperScalingTransientGetSet() throws {
        let settings = AppSettings()
        settings.wallpaperScaling = .fillScreen
        #expect(settings.wallpaperScalingRaw == "fillScreen")
        #expect(settings.wallpaperScaling == .fillScreen)

        settings.wallpaperScaling = .center
        #expect(settings.wallpaperScalingRaw == "center")
        #expect(settings.wallpaperScaling == .center)
    }

    @Test func currentCreatesNewIfNoneExists() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let settings = AppSettings.current(in: context)
        #expect(settings.shuffleIntervalMinutes == 30)
        #expect(settings.photosEnabled == true)
    }

    @Test func currentReturnsExistingIfPresent() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let first = AppSettings.current(in: context)
        first.shuffleIntervalMinutes = 60
        try context.save()

        let second = AppSettings.current(in: context)
        #expect(second.shuffleIntervalMinutes == 60)
    }
}

struct AlbumTests {
    @Test func initStoresSourceTypeRaw() {
        let album = Album(id: "a1", name: "Test", sourceType: .lightroomCloud)
        #expect(album.sourceTypeRaw == "lightroomCloud")
        #expect(album.sourceType == .lightroomCloud)
    }

    @Test func sourceTypeTransientRoundtrip() {
        let album = Album(id: "a1", name: "Test", sourceType: .applePhotos)
        #expect(album.sourceType == .applePhotos)
        album.sourceType = .lightroomCloud
        #expect(album.sourceTypeRaw == "lightroomCloud")
        #expect(album.sourceType == .lightroomCloud)
    }

    @Test func cascadeDeleteRemovesAssets() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        let album = Album(id: "album1", name: "Test Album", sourceType: .applePhotos, isSelected: true)
        context.insert(album)

        let asset1 = Asset(id: "asset1", sourceType: .applePhotos, album: album)
        let asset2 = Asset(id: "asset2", sourceType: .applePhotos, album: album)
        context.insert(asset1)
        context.insert(asset2)
        try context.save()

        let assetsBefore = try context.fetch(FetchDescriptor<Asset>())
        #expect(assetsBefore.count == 2)

        context.delete(album)
        try context.save()

        let assetsAfter = try context.fetch(FetchDescriptor<Asset>())
        #expect(assetsAfter.count == 0)
    }
}

struct AssetTests {
    @Test func initWithDefaults() {
        let asset = Asset(id: "a1", sourceType: .applePhotos)
        #expect(asset.width == 0)
        #expect(asset.height == 0)
        #expect(asset.cachedFilePath == nil)
        #expect(asset.lastUsedDate == nil)
        #expect(asset.album == nil)
    }

    @Test func initWithCustomValues() {
        let asset = Asset(id: "a1", sourceType: .lightroomCloud, width: 1920, height: 1080)
        #expect(asset.width == 1920)
        #expect(asset.height == 1080)
        #expect(asset.sourceType == .lightroomCloud)
    }
}
