import Testing
import SwiftData
@testable import PhotoDrift

struct UnifiedPoolTests {
    private func makePool() throws -> (UnifiedPool, ModelContainer, ModelContext) {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let pool = UnifiedPool(modelContainer: container)
        return (pool, container, context)
    }

    @Test func emptyDatabaseReturnsEmptyPool() async throws {
        let (pool, _, _) = try makePool()
        let entries = try await pool.buildPool()
        #expect(entries.isEmpty)
    }

    @Test func selectedAlbumWithAssetsPopulatesPool() async throws {
        let (pool, _, context) = try makePool()

        let album = Album(id: "a1", name: "Vacation", sourceType: .applePhotos, isSelected: true)
        context.insert(album)
        let asset1 = Asset(id: "p1", sourceType: .applePhotos, album: album)
        let asset2 = Asset(id: "p2", sourceType: .applePhotos, album: album)
        context.insert(asset1)
        context.insert(asset2)
        // Ensure default settings exist with photosEnabled=true
        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let entries = try await pool.buildPool()
        #expect(entries.count == 2)
        let ids = Set(entries.map(\.id))
        #expect(ids.contains("p1"))
        #expect(ids.contains("p2"))
    }

    @Test func unselectedAlbumReturnsEmptyPool() async throws {
        let (pool, _, context) = try makePool()

        let album = Album(id: "a1", name: "Hidden", sourceType: .applePhotos, isSelected: false)
        context.insert(album)
        let asset = Asset(id: "p1", sourceType: .applePhotos, album: album)
        context.insert(asset)
        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let entries = try await pool.buildPool()
        #expect(entries.isEmpty)
    }

    @Test func multipleAlbumsCombineAssets() async throws {
        let (pool, _, context) = try makePool()

        let album1 = Album(id: "a1", name: "Nature", sourceType: .applePhotos, isSelected: true)
        let album2 = Album(id: "a2", name: "City", sourceType: .applePhotos, isSelected: true)
        context.insert(album1)
        context.insert(album2)
        context.insert(Asset(id: "p1", sourceType: .applePhotos, album: album1))
        context.insert(Asset(id: "p2", sourceType: .applePhotos, album: album2))
        context.insert(Asset(id: "p3", sourceType: .applePhotos, album: album2))
        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let entries = try await pool.buildPool()
        #expect(entries.count == 3)
    }

    @Test func photosDisabledExcludesPhotosAlbums() async throws {
        let (pool, _, context) = try makePool()

        let album = Album(id: "a1", name: "Photos Album", sourceType: .applePhotos, isSelected: true)
        context.insert(album)
        context.insert(Asset(id: "p1", sourceType: .applePhotos, album: album))
        let settings = AppSettings(photosEnabled: false)
        context.insert(settings)
        try context.save()

        let entries = try await pool.buildPool()
        #expect(entries.isEmpty)
    }

    @Test func lightroomDisabledExcludesLightroomAlbums() async throws {
        let (pool, _, context) = try makePool()

        let album = Album(id: "lr1", name: "LR Album", sourceType: .lightroomCloud, isSelected: true)
        context.insert(album)
        context.insert(Asset(id: "lra1", sourceType: .lightroomCloud, album: album))
        let settings = AppSettings(lightroomEnabled: false)
        context.insert(settings)
        try context.save()

        let entries = try await pool.buildPool()
        #expect(entries.isEmpty)
    }

    @Test func entriesHaveCorrectSourceTypeAndAlbumID() async throws {
        let (pool, _, context) = try makePool()

        let album = Album(id: "a1", name: "Test", sourceType: .lightroomCloud, isSelected: true)
        context.insert(album)
        context.insert(Asset(id: "lra1", sourceType: .lightroomCloud, album: album))
        let settings = AppSettings(lightroomEnabled: true)
        context.insert(settings)
        try context.save()

        let entries = try await pool.buildPool()
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.sourceType == .lightroomCloud)
        #expect(entry.albumID == "a1")
        #expect(entry.id == "lra1")
    }
}
