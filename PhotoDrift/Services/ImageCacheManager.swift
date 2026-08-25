import Foundation
import CryptoKit

actor ImageCacheManager {

    static func cacheKey(for id: String) -> String {
        let hash = SHA256.hash(data: Data(id.utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
    static let shared = ImageCacheManager()

    private static let directoryName = "PhotoDriftImages"

    /// Cached images live in Application Support, not Caches.
    ///
    /// macOS reclaims disk space by purging sandboxed apps' container `Caches` directories,
    /// and it terminates the owning app first to do it — the app dies with no crash report,
    /// only an `OS_REASON_RUNNINGBOARD` / `CacheDeleteAppContainerCaches` exit reason. A 500 MB
    /// image cache made PhotoDrift the biggest target on the system. These files back the
    /// wallpaper currently on screen, so they aren't disposable; `evictIfNeeded()` bounds them
    /// instead.
    static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Where images used to be cached, before the move off the system-purgeable location.
    static var legacyCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private let maxBytes: UInt64
    private let cacheDirectory: URL

    private init() {
        cacheDirectory = Self.defaultCacheDirectory
        maxBytes = 500 * 1024 * 1024 // 500 MB
        Self.prepareDirectory(at: cacheDirectory)
        Self.migrateIfNeeded(from: Self.legacyCacheDirectory, to: cacheDirectory)
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

    /// One-time move of images left in the old, system-purgeable cache location.
    /// Files already present at the destination win — they're at least as fresh as
    /// whatever the previous build left behind.
    static func migrateIfNeeded(from legacyDirectory: URL, to directory: URL) {
        let fm = FileManager.default
        guard legacyDirectory.standardizedFileURL != directory.standardizedFileURL,
              let contents = try? fm.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil)
        else { return }

        for url in contents {
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: url)
            } else {
                try? fm.moveItem(at: url, to: destination)
            }
        }
        try? fm.removeItem(at: legacyDirectory)
    }

    func store(data: Data, forKey key: String) throws -> URL {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try data.write(to: fileURL)
        try evictIfNeeded()
        return fileURL
    }

    func retrieve(forKey key: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    func evictIfNeeded() throws {
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
