import Foundation
import CryptoKit

actor ImageCacheManager {

    static func cacheKey(for id: String) -> String {
        let hash = SHA256.hash(data: Data(id.utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
    static let shared = ImageCacheManager()

    private static let directoryName = "PhotoDriftDownloads"

    /// Cached images live in Application Support, not Caches.
    ///
    /// macOS reclaims disk space by purging sandboxed apps' container `Caches` directories,
    /// and it terminates the owning app first to do it — the app dies with no crash report,
    /// only an `OS_REASON_RUNNINGBOARD` / `CacheDeleteAppContainerCaches` exit reason. A 500 MB
    /// image cache made PhotoDrift the biggest target on the system. `evictIfNeeded()` bounds
    /// downloads instead. Published wallpapers live separately in WallpaperStore.
    /// The old PhotoDriftImages directory is deliberately left intact: inactive Spaces
    /// and disconnected displays may still refer to images published by older versions.
    static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var previousCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PhotoDriftImages", isDirectory: true)
    }

    /// Where images used to be cached, before the move off the system-purgeable location.
    static var legacyCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PhotoDriftImages", isDirectory: true)
    }

    private let maxBytes: UInt64
    private let cacheDirectory: URL

    private init() {
        cacheDirectory = Self.defaultCacheDirectory
        maxBytes = 500 * 1024 * 1024 // 500 MB
        Self.prepareDirectory(at: cacheDirectory)
        Self.migratePreviousDownloads(to: cacheDirectory)
    }

    init(cacheDirectory: URL, maxBytes: UInt64 = 500 * 1024 * 1024) {
        self.cacheDirectory = cacheDirectory
        self.maxBytes = maxBytes
        Self.prepareDirectory(at: cacheDirectory)
    }

    private static func prepareDirectory(at url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    static func migratePreviousDownloads(
        to directory: URL,
        previousDirectory: URL = previousCacheDirectory,
        legacyDirectory: URL = legacyCacheDirectory
    ) {
        // Prefer the most recent Application Support cache when both contain a key.
        migrateIfNeeded(from: previousDirectory, to: directory)
        migrateIfNeeded(from: legacyDirectory, to: directory)
    }

    /// Copy images left in the old location without invalidating wallpaper references.
    /// Files already present at the destination win — they're at least as fresh as
    /// whatever the previous build left behind.
    static func migrateIfNeeded(from legacyDirectory: URL, to directory: URL) {
        let fm = FileManager.default
        // Keep the receipt outside the evictable directory, including after Clear Cache.
        let sourceKey = cacheKey(for: legacyDirectory.standardizedFileURL.path)
        let receipt = directory.deletingLastPathComponent()
            .appendingPathComponent(".\(directory.lastPathComponent)-migration-\(sourceKey).done")
        guard !fm.fileExists(atPath: receipt.path), legacyDirectory.standardizedFileURL != directory.standardizedFileURL,
              let contents = try? fm.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil)
        else { return }

        var completed = true
        for url in contents where url.pathExtension.lowercased() == "jpg" {
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                do { try fm.copyItem(at: url, to: destination) }
                catch { completed = false }
            }
        }
        if completed { try? Data().write(to: receipt, options: .atomic) }
    }

    func store(data: Data, forKey key: String) throws -> URL {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try data.write(to: fileURL, options: .atomic)
        try evictIfNeeded(preserving: fileURL)
        return fileURL
    }

    /// Read while isolated to the cache actor so eviction cannot remove a returned URL
    /// before its caller opens it. A vanished file is simply a cache miss.
    func data(forKey key: String) -> Data? {
        try? Data(contentsOf: cacheDirectory.appendingPathComponent(key))
    }

    func retrieve(forKey key: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    func evictIfNeeded(preserving protectedURL: URL? = nil) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])

        var totalSize: UInt64 = 0
        var files: [(url: URL, date: Date, size: UInt64)] = []

        for url in contents {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = UInt64(values.fileSize ?? 0)
            let date = values.contentModificationDate ?? .distantPast
            totalSize += size
            files.append((url, date, size))
        }

        guard totalSize > maxBytes else { return }

        files.sort { $0.date < $1.date }
        for file in files {
            guard totalSize > maxBytes else { break }
            // Directory enumeration produces absolute URLs; the stored URL may retain a
            // base URL. Compare names within this one directory, not URL representations.
            guard file.url.lastPathComponent != protectedURL?.lastPathComponent else { continue }
            try fm.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    func remove(forKey key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func removeStaleEntries(validKeys: Set<String>) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            if !validKeys.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
    }

    func clear() throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for url in contents {
            try fm.removeItem(at: url)
        }
    }
}
