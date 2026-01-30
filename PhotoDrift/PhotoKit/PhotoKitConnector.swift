import Photos
import AppKit

struct AlbumInfo: Sendable {
    let id: String
    let name: String
    let assetCount: Int
    let sourceType: SourceType
}

actor PhotoKitConnector {
    static let shared = PhotoKitConnector()

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchAlbums() -> [AlbumInfo] {
        var albums: [AlbumInfo] = []

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            albums.append(AlbumInfo(
                id: collection.localIdentifier,
                name: collection.localizedTitle ?? "Untitled",
                assetCount: count,
                sourceType: .applePhotos
            ))
        }

        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
            guard count > 0 else { return }
            albums.append(AlbumInfo(
                id: collection.localIdentifier,
                name: collection.localizedTitle ?? "Untitled",
                assetCount: count,
                sourceType: .applePhotos
            ))
        }

        return albums
    }

    func fetchAssetIDs(albumID: String) -> [String] {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
        guard let collection = collections.firstObject else { return [] }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)

        var ids: [String] = []
        assets.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    func requestImage(assetID: String) async throws -> Data {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else {
            throw PhotoKitError.assetNotFound
        }

        let targetSize = ScreenUtility.targetSize
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = image,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                else {
                    continuation.resume(throwing: PhotoKitError.imageConversionFailed)
                    return
                }

                continuation.resume(returning: jpegData)
            }
        }
    }
}

enum PhotoKitError: Error, LocalizedError {
    case assetNotFound
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Photo asset not found"
        case .imageConversionFailed: "Failed to convert image"
        }
    }
}
