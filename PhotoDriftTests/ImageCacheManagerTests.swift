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

    // MARK: - Gradient filename derivation

    @Test func gradientFilenamesAreUniquePerAssetID() {
        let key1 = ImageCacheManager.cacheKey(for: "asset-001")
        let key2 = ImageCacheManager.cacheKey(for: "asset-002")
        let name1 = "gradient_\(key1).png"
        let name2 = "gradient_\(key2).png"
        #expect(name1 != name2)
    }

    @Test func gradientFilenameIsStableForSameAssetID() {
        let key = ImageCacheManager.cacheKey(for: "asset-repeat")
        let name1 = "gradient_\(key).png"
        let name2 = "gradient_\(key).png"
        #expect(name1 == name2)
    }

    @Test func gradientFilenameContainsNoProblemCharacters() {
        // Asset IDs from Photos (e.g. "B84E8479-475C-4727-A4A4-B77AA9980897/L0/001")
        // and Lightroom (e.g. "abc123def456") should produce safe filenames
        let ids = [
            "B84E8479-475C-4727-A4A4-B77AA9980897/L0/001",
            "abc123def456",
            "asset with spaces",
            "特殊文字",
        ]
        let safeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
        for id in ids {
            let key = ImageCacheManager.cacheKey(for: id)
            let name = "gradient_\(key).png"
            for scalar in name.unicodeScalars {
                #expect(safeChars.contains(scalar), "Unsafe character '\(scalar)' in gradient filename for id: \(id)")
            }
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
