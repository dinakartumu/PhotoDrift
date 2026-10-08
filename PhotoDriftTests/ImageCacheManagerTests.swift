import Testing
import Foundation
@testable import PhotoDrift

struct ImageCacheManagerTests {
    private func makeTempCache(maxBytes: UInt64 = 500 * 1024 * 1024) -> (ImageCacheManager, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDriftTests-\(UUID().uuidString)", isDirectory: true)
        let manager = ImageCacheManager(cacheDirectory: dir, maxBytes: maxBytes)
        return (manager, dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - cacheKey tests

    @Test func cacheKeyIsDeterministic() {
        let key1 = ImageCacheManager.cacheKey(for: "test-id-123")
        let key2 = ImageCacheManager.cacheKey(for: "test-id-123")
        #expect(key1 == key2)
    }

    @Test func differentIDsProduceDifferentKeys() {
        let key1 = ImageCacheManager.cacheKey(for: "id-alpha")
        let key2 = ImageCacheManager.cacheKey(for: "id-beta")
        #expect(key1 != key2)
    }

    @Test func keyFormatIs32HexCharsWithJpgExtension() {
        let key = ImageCacheManager.cacheKey(for: "some-asset-id")
        #expect(key.hasSuffix(".jpg"))
        let name = String(key.dropLast(4)) // remove .jpg
        #expect(name.count == 32)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for char in name.unicodeScalars {
            #expect(hexChars.contains(char))
        }
    }

    // MARK: - Store / Retrieve

    @Test func storeAndRetrieveRoundtrip() async throws {
        let (manager, dir) = makeTempCache()
        defer { cleanup(dir) }

        let data = Data("hello world".utf8)
        let key = "testkey.jpg"
        let url = try await manager.store(data: data, forKey: key)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let retrieved = await manager.retrieve(forKey: key)
        #expect(retrieved != nil)
        #expect(retrieved == url)
    }

    @Test func retrieveForMissingKeyReturnsNil() async {
        let (manager, dir) = makeTempCache()
        defer { cleanup(dir) }

        let result = await manager.retrieve(forKey: "nonexistent.jpg")
        #expect(result == nil)
    }

    // MARK: - removeStaleEntries

    @Test func removeStaleEntriesKeepsValidDeletesOthers() async throws {
        let (manager, dir) = makeTempCache()
        defer { cleanup(dir) }

        let validKey = "valid.jpg"
        let staleKey = "stale.jpg"
        _ = try await manager.store(data: Data("valid".utf8), forKey: validKey)
        _ = try await manager.store(data: Data("stale".utf8), forKey: staleKey)

        await manager.removeStaleEntries(validKeys: Set([validKey]))

        let validExists = await manager.retrieve(forKey: validKey)
        let staleExists = await manager.retrieve(forKey: staleKey)
        #expect(validExists != nil)
        #expect(staleExists == nil)
    }

    // MARK: - remove

    @Test func removeDeletesFile() async throws {
        let (manager, dir) = makeTempCache()
        defer { cleanup(dir) }

        let key = "toremove.jpg"
        _ = try await manager.store(data: Data("data".utf8), forKey: key)
        let before = await manager.retrieve(forKey: key)
        #expect(before != nil)

        await manager.remove(forKey: key)
        let after = await manager.retrieve(forKey: key)
        #expect(after == nil)
    }

    // MARK: - Cache location

    @Test func defaultCacheDirectoryIsNotPurgeableByTheSystem() {
        // macOS's cache_delete daemon reclaims ~/Library/Caches under disk pressure and
        // terminates the owning app to do it. The image cache must live outside it.
        let path = ImageCacheManager.defaultCacheDirectory.path
        #expect(!path.contains("/Library/Caches/"))
        #expect(path.contains("/Application Support/"))
    }

    @Test func legacyCacheDirectoryPointsAtTheOldCachesLocation() {
        let path = ImageCacheManager.legacyCacheDirectory.path
        #expect(path.contains("/Library/Caches/"))
    }

    @Test func disposableDownloadsDoNotReusePreviouslyPublishedDirectory() {
        #expect(ImageCacheManager.defaultCacheDirectory.lastPathComponent == "PhotoDriftDownloads")
        #expect(ImageCacheManager.defaultCacheDirectory != WallpaperStore.defaultDirectory)
    }

    @Test func newlyStoredFileSurvivesEvenWhenItExceedsCacheBudget() async throws {
        let (manager, dir) = makeTempCache(maxBytes: 10)
        defer { cleanup(dir) }
        let data = Data(repeating: 0x41, count: 60)
        let url = try await manager.store(data: data, forKey: "large.jpg")
        #expect(try Data(contentsOf: url) == data)
    }

    // MARK: - Migration off the purgeable cache location

    private func makeMigrationPair() -> (legacy: URL, current: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDriftMigration-\(UUID().uuidString)", isDirectory: true)
        return (
            root.appendingPathComponent("legacy", isDirectory: true),
            root.appendingPathComponent("current", isDirectory: true)
        )
    }

    private func write(_ contents: String, named name: String, in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }

    @Test func migrationCopiesLegacyFilesIntoTheNewDirectory() throws {
        let (legacy, current) = makeMigrationPair()
        defer { cleanup(legacy.deletingLastPathComponent()) }

        try write("cached image", named: "a.jpg", in: legacy)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)

        ImageCacheManager.migrateIfNeeded(from: legacy, to: current)

        let moved = current.appendingPathComponent("a.jpg")
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(try String(contentsOf: moved, encoding: .utf8) == "cached image")
    }

    @Test func migrationPreservesFilesReferencedByOlderDesktops() throws {
        let (legacy, current) = makeMigrationPair()
        defer { cleanup(legacy.deletingLastPathComponent()) }

        try write("x", named: "a.jpg", in: legacy)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)

        ImageCacheManager.migrateIfNeeded(from: legacy, to: current)

        #expect(try String(contentsOf: legacy.appendingPathComponent("a.jpg"), encoding: .utf8) == "x")
    }

    @Test func migrationKeepsExistingFileWhenBothLocationsHaveTheSameKey() throws {
        let (legacy, current) = makeMigrationPair()
        defer { cleanup(legacy.deletingLastPathComponent()) }

        try write("stale", named: "a.jpg", in: legacy)
        try write("fresh", named: "a.jpg", in: current)

        ImageCacheManager.migrateIfNeeded(from: legacy, to: current)

        let kept = current.appendingPathComponent("a.jpg")
        #expect(try String(contentsOf: kept, encoding: .utf8) == "fresh")
        #expect(try String(contentsOf: legacy.appendingPathComponent("a.jpg"), encoding: .utf8) == "stale")
    }

    @Test func migrationIsANoOpWhenLegacyDirectoryIsAbsent() throws {
        let (legacy, current) = makeMigrationPair()
        defer { cleanup(legacy.deletingLastPathComponent()) }

        try write("fresh", named: "a.jpg", in: current)

        ImageCacheManager.migrateIfNeeded(from: legacy, to: current)

        #expect(try String(contentsOf: current.appendingPathComponent("a.jpg"), encoding: .utf8) == "fresh")
    }

    @Test func migrationDoesNotDeleteFilesWhenSourceAndDestinationMatch() throws {
        let (_, current) = makeMigrationPair()
        defer { cleanup(current.deletingLastPathComponent()) }

        try write("fresh", named: "a.jpg", in: current)

        ImageCacheManager.migrateIfNeeded(from: current, to: current)

        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("a.jpg").path))
    }

    // MARK: - LRU Eviction

    @Test func evictionDeletesOldestFilesWhenOverSizeLimit() async throws {
        // 100 byte limit
        let (manager, dir) = makeTempCache(maxBytes: 100)
        defer { cleanup(dir) }

        // Store files that together exceed 100 bytes
        let bigData = Data(repeating: 0x41, count: 60)
        _ = try await manager.store(data: bigData, forKey: "first.jpg")

        // Small delay so modification dates differ
        try await Task.sleep(for: .milliseconds(50))

        _ = try await manager.store(data: bigData, forKey: "second.jpg")

        // Total is 120 bytes, limit is 100 — oldest ("first.jpg") should be evicted
        let firstExists = await manager.retrieve(forKey: "first.jpg")
        let secondExists = await manager.retrieve(forKey: "second.jpg")
        #expect(firstExists == nil)
        #expect(secondExists != nil)
    }
}

struct DownloadCacheUpgradeTests {
    @Test func upgradeImportsBothCacheGenerationsOnlyOnceAndPreservesOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadUpgrade-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support/PhotoDriftImages")
        let legacy = root.appendingPathComponent("Caches/PhotoDriftImages")
        let downloads = root.appendingPathComponent("Application Support/PhotoDriftDownloads")
        for directory in [support, legacy, downloads] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("v1.3".utf8).write(to: support.appendingPathComponent("shared.jpg"))
        try Data("older".utf8).write(to: legacy.appendingPathComponent("shared.jpg"))
        try Data("offline photo".utf8).write(to: legacy.appendingPathComponent("legacy.jpg"))
        try Data("desktop".utf8).write(to: support.appendingPathComponent("gradient.png"))
        ImageCacheManager.migratePreviousDownloads(to: downloads, previousDirectory: support, legacyDirectory: legacy)
        let cache = ImageCacheManager(cacheDirectory: downloads)
        let restored = try #require(await cache.retrieve(forKey: "shared.jpg"))
        #expect(try String(contentsOf: restored, encoding: .utf8) == "v1.3")
        #expect(await cache.retrieve(forKey: "legacy.jpg") != nil)
        #expect(await cache.retrieve(forKey: "gradient.png") == nil)
        try await cache.clear()
        ImageCacheManager.migratePreviousDownloads(to: downloads, previousDirectory: support, legacyDirectory: legacy)
        #expect(await cache.retrieve(forKey: "shared.jpg") == nil)
        #expect(await cache.retrieve(forKey: "legacy.jpg") == nil)
        #expect(try String(contentsOf: support.appendingPathComponent("shared.jpg"), encoding: .utf8) == "v1.3")
        #expect(try String(contentsOf: legacy.appendingPathComponent("shared.jpg"), encoding: .utf8) == "older")
    }
}
