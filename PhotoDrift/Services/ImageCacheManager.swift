import Foundation

actor ImageCacheManager {
    static let shared = ImageCacheManager()

    private let maxBytes: UInt64 = 500 * 1024 * 1024 // 500 MB
    private let cacheDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("PhotoDriftImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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

    func clear() throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for url in contents {
            try fm.removeItem(at: url)
        }
    }
}
