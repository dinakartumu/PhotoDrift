import Foundation

actor LightroomConnector {
    static let shared = LightroomConnector()

    private var catalogID: String?

    func ensureCatalog() async throws -> String {
        if let id = catalogID { return id }
        let id = try await LightroomAPIClient.shared.getCatalogID()
        catalogID = id
        return id
    }

    func fetchAlbums() async throws -> [AlbumInfo] {
        let catID = try await ensureCatalog()
        let lrAlbums = try await LightroomAPIClient.shared.getAlbums(catalogID: catID)

        return lrAlbums
            .filter { $0.subtype != "collection_set" }
            .map { album in
                AlbumInfo(
                    id: album.id,
                    name: album.payload?.name ?? "Untitled",
                    assetCount: 0,
                    sourceType: .lightroomCloud
                )
            }
    }

    func fetchAssetIDs(albumID: String) async throws -> [String] {
        let catID = try await ensureCatalog()
        let assets = try await LightroomAPIClient.shared.getAlbumAssets(catalogID: catID, albumID: albumID)
        return assets.map(\.asset.id)
    }

    func downloadImage(assetID: String) async throws -> Data {
        let catID = try await ensureCatalog()

        // Try largest available rendition, fall back to smaller sizes
        let targetSize = ScreenUtility.targetSize
        let sizes = targetSize.width > 4096
            ? ["fullsize", "2048", "1024"]
            : ["2048", "1024", "640"]

        for size in sizes {
            do {
                return try await LightroomAPIClient.shared.downloadRendition(
                    catalogID: catID,
                    assetID: assetID,
                    size: size
                )
            } catch LightroomError.renditionNotFound {
                continue
            }
        }
        throw LightroomError.downloadFailed
    }

    func resetCatalog() {
        catalogID = nil
    }
}
