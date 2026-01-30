import Foundation
import SwiftData

actor UnifiedPool {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    struct PoolEntry: Sendable {
        let id: String
        let sourceType: SourceType
        let albumID: String
    }

    func buildPool() async throws -> [PoolEntry] {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        var pool: [PoolEntry] = []

        if settings.photosEnabled {
            let photosRaw = SourceType.applePhotos.rawValue
            let descriptor = FetchDescriptor<Album>(
                predicate: #Predicate { $0.isSelected && $0.sourceTypeRaw == photosRaw }
            )
            let albums = try context.fetch(descriptor)
            for album in albums {
                let assetIDs = await PhotoKitConnector.shared.fetchAssetIDs(albumID: album.id)
                pool.append(contentsOf: assetIDs.map {
                    PoolEntry(id: $0, sourceType: .applePhotos, albumID: album.id)
                })
            }
        }

        if settings.lightroomEnabled {
            let lrRaw = SourceType.lightroomCloud.rawValue
            let descriptor = FetchDescriptor<Album>(
                predicate: #Predicate { $0.isSelected && $0.sourceTypeRaw == lrRaw }
            )
            let albums = try context.fetch(descriptor)
            for album in albums {
                do {
                    let assetIDs = try await LightroomConnector.shared.fetchAssetIDs(albumID: album.id)
                    pool.append(contentsOf: assetIDs.map {
                        PoolEntry(id: $0, sourceType: .lightroomCloud, albumID: album.id)
                    })
                    // Update asset count
                    album.assetCount = assetIDs.count
                } catch {
                    // Skip album on error, use cached data if available
                    for asset in album.assets {
                        pool.append(PoolEntry(id: asset.id, sourceType: .lightroomCloud, albumID: album.id))
                    }
                }
            }
        }

        return pool
    }

    func syncPhotosAlbums() async {
        let context = ModelContext(modelContainer)
        let infos = await PhotoKitConnector.shared.fetchAlbums()
        let fetchedIDs = Set(infos.map(\.id))

        let photosRaw = SourceType.applePhotos.rawValue
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.sourceTypeRaw == photosRaw }
        )
        let existingAlbums = (try? context.fetch(descriptor)) ?? []

        for album in existingAlbums where !fetchedIDs.contains(album.id) {
            context.delete(album)
        }

        for info in infos {
            if let existing = existingAlbums.first(where: { $0.id == info.id }) {
                existing.name = info.name
                existing.assetCount = info.assetCount
            } else {
                let album = Album(id: info.id, name: info.name, sourceType: .applePhotos, assetCount: info.assetCount)
                context.insert(album)
            }
        }

        try? context.save()
    }

    func syncLightroomAlbums() async {
        let context = ModelContext(modelContainer)

        do {
            let infos = try await LightroomConnector.shared.fetchAlbums()
            let fetchedIDs = Set(infos.map(\.id))

            let lrRaw = SourceType.lightroomCloud.rawValue
            let descriptor = FetchDescriptor<Album>(
                predicate: #Predicate { $0.sourceTypeRaw == lrRaw }
            )
            let existingAlbums = (try? context.fetch(descriptor)) ?? []

            for album in existingAlbums where !fetchedIDs.contains(album.id) {
                context.delete(album)
            }

            for info in infos {
                if let existing = existingAlbums.first(where: { $0.id == info.id }) {
                    existing.name = info.name
                } else {
                    let album = Album(id: info.id, name: info.name, sourceType: .lightroomCloud)
                    context.insert(album)
                }
            }

            try? context.save()
        } catch {
            // Network error — keep cached data
        }
    }
}
