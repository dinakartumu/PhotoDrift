import Foundation
import CryptoKit

/// Published images are documents owned by the desktop, not disposable downloads.
/// There is no public API to enumerate image references in inactive Spaces. Keep these
/// immutable, deduplicated snapshots until they can safely be retired by the user.
nonisolated struct WallpaperStore {
    struct Wallpaper: Codable, Equatable, Sendable {
        let filename: String
        let scaling: WallpaperScaling
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PhotoDriftWallpapers", isDirectory: true)
    }

    let directory: URL

    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    func url(for wallpaper: Wallpaper) -> URL {
        directory.appendingPathComponent(wallpaper.filename)
    }

    func publish(data: Data, isPNG: Bool, scaling: WallpaperScaling) throws -> Wallpaper {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let wallpaper = Wallpaper(filename: digest + (isPNG ? ".png" : ".jpg"), scaling: scaling)
        let destination = url(for: wallpaper)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: .atomic)
        }
        // Save the intended wallpaper before applying: a crash or a partially successful
        // multi-display update can then recover without waiting for album sync/downloads.
        try JSONEncoder().encode(wallpaper).write(to: manifestURL, options: .atomic)
        return wallpaper
    }

    func restore() -> Wallpaper? {
        guard let data = try? Data(contentsOf: manifestURL),
              let wallpaper = try? JSONDecoder().decode(Wallpaper.self, from: data),
              wallpaper.filename == (wallpaper.filename as NSString).lastPathComponent,
              FileManager.default.fileExists(atPath: url(for: wallpaper).path)
        else { return nil }
        return wallpaper
    }

    private var manifestURL: URL { directory.appendingPathComponent("current.json") }
}
