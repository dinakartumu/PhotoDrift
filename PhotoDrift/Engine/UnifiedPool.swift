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

    @discardableResult
    func syncAssets(forAlbumID albumID: String) async -> String? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.id == albumID }
        )
        guard let album = try? context.fetch(descriptor).first else {
            return "Album not found"
        }

        let fetchedIDs: [String]
        switch album.sourceType {
        case .applePhotos:
            fetchedIDs = await PhotoKitConnector.shared.fetchAssetIDs(albumID: albumID)
        case .lightroomCloud:
            do {
                fetchedIDs = try await LightroomConnector.shared.fetchAssetIDs(albumID: albumID)
            } catch {
                return "Lightroom sync failed for '\(album.name)': \(error.localizedDescription)"
            }
        }

        let existingByID = Dictionary(uniqueKeysWithValues: album.assets.map { ($0.id, $0) })
        let fetchedSet = Set(fetchedIDs)
        let existingSet = Set(existingByID.keys)

        // Delete removed assets
        for id in existingSet.subtracting(fetchedSet) {
            if let asset = existingByID[id] {
                context.delete(asset)
            }
        }

        // Insert new assets
        for id in fetchedSet.subtracting(existingSet) {
            let asset = Asset(id: id, sourceType: album.sourceType, album: album)
            context.insert(asset)
        }

        album.assetCount = fetchedIDs.count
        do {
            try context.save()
        } catch {
            return "Failed to save synced assets for '\(album.name)'"
        }
        return nil
    }

    func syncSelectedAlbums() async -> [String] {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isSelected }
        )
        let selectedAlbums = (try? context.fetch(descriptor)) ?? []
        var failures: [String] = []

        for album in selectedAlbums {
            let sourceEnabled = album.sourceType == .applePhotos ? settings.photosEnabled : settings.lightroomEnabled
            guard sourceEnabled else { continue }
            if let failure = await syncAssets(forAlbumID: album.id) {
                failures.append(failure)
            }
        }
        return failures
    }

    func clearAssetsIfAlbumDeselected(forAlbumID albumID: String) async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.id == albumID }
        )
        guard let album = try? context.fetch(descriptor).first else { return }
        guard !album.isSelected else { return }

        let assets = Array(album.assets)
        guard !assets.isEmpty else { return }

        let assetIDs = assets.map(\.id)
        for asset in assets {
            context.delete(asset)
        }
        album.assetCount = 0
        try? context.save()

        for assetID in assetIDs {
            await ImageCacheManager.shared.remove(forKey: ImageCacheManager.cacheKey(for: assetID))
        }
    }

    func buildPool() async throws -> [PoolEntry] {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        var pool: [PoolEntry] = []

        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isSelected }
        )
        let albums = try context.fetch(descriptor)
        for album in albums {
            let sourceEnabled = album.sourceType == .applePhotos ? settings.photosEnabled : settings.lightroomEnabled
            guard sourceEnabled else { continue }
            for asset in album.assets {
                pool.append(PoolEntry(id: asset.id, sourceType: album.sourceType, albumID: album.id))
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

        // Sync assets for selected albums
        let selectedAlbums = existingAlbums.filter { $0.isSelected && fetchedIDs.contains($0.id) }
        for album in selectedAlbums {
            await syncAssets(forAlbumID: album.id)
        }
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

            // Sync assets for selected albums
            let selectedAlbums = existingAlbums.filter { $0.isSelected && fetchedIDs.contains($0.id) }
            for album in selectedAlbums {
                await syncAssets(forAlbumID: album.id)
            }
        } catch {
            // Network error — keep cached data
        }
    }
}
