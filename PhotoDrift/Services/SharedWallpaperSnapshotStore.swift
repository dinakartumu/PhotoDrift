import CoreGraphics
import Foundation

struct SharedWallpaperSnapshotMetadata: Codable {
    struct RGBA: Codable {
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
    }

    let updatedAt: Date
    let topColor: RGBA
    let bottomColor: RGBA
}

final class SharedWallpaperSnapshotStore {
    static let shared = SharedWallpaperSnapshotStore()

    private enum Constants {
        static let directoryName = "PhotoDriftSharedWallpaper"
        static let imageFileName = "latest-image.bin"
        static let metadataFileName = "latest-metadata.json"
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(imageData: Data, palette: GradientPalette) throws {
        let directory = try ensureDirectory()
        let imageURL = directory.appendingPathComponent(Constants.imageFileName)
        let metadataURL = directory.appendingPathComponent(Constants.metadataFileName)

        try imageData.write(to: imageURL, options: .atomic)

        let metadata = SharedWallpaperSnapshotMetadata(
            updatedAt: Date(),
            topColor: rgba(from: palette.topColor),
            bottomColor: rgba(from: palette.bottomColor)
        )
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    func loadLatestSnapshot() -> (imageData: Data, palette: GradientPalette)? {
        let directory: URL
        do {
            directory = try ensureDirectory()
        } catch {
            return nil
        }

        let imageURL = directory.appendingPathComponent(Constants.imageFileName)
        let metadataURL = directory.appendingPathComponent(Constants.metadataFileName)

        guard let imageData = try? Data(contentsOf: imageURL),
              let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? decoder.decode(SharedWallpaperSnapshotMetadata.self, from: metadataData) else {
            return nil
        }

        return (
            imageData: imageData,
            palette: GradientPalette(
                topColor: cgColor(from: metadata.topColor),
                bottomColor: cgColor(from: metadata.bottomColor)
            )
        )
    }

    private func ensureDirectory() throws -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = caches.appendingPathComponent(Constants.directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func rgba(from color: CGColor) -> SharedWallpaperSnapshotMetadata.RGBA {
        if let converted = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
           let components = converted.components,
           components.count >= 4 {
            return .init(r: components[0], g: components[1], b: components[2], a: components[3])
        }
        if let components = color.components, components.count == 2 {
            return .init(r: components[0], g: components[0], b: components[0], a: components[1])
        }
        return .init(r: 0, g: 0, b: 0, a: 1)
    }

    private func cgColor(from rgba: SharedWallpaperSnapshotMetadata.RGBA) -> CGColor {
        CGColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}
