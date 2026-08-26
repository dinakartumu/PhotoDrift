import Foundation

nonisolated struct LRCatalog: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id
    }
}

nonisolated struct LRCatalogResponse: Decodable {
    let id: String
}

nonisolated struct LRAlbumsResponse: Decodable {
    let resources: [LRAlbumResource]?
    let links: LRLinks?

    struct LRAlbumResource: Decodable {
        let id: String
        let subtype: String?
        let payload: Payload?

        struct Payload: Decodable {
            let name: String?
        }
    }
}

nonisolated struct LRAlbumAssetsResponse: Decodable {
    let resources: [LRAssetResource]?
    let links: LRLinks?

    struct LRAssetResource: Decodable {
        let asset: AssetInfo

        struct AssetInfo: Decodable {
            let id: String
            let payload: Payload?

            struct Payload: Decodable {
                let develop: Develop?

                struct Develop: Decodable {
                    let croppedWidth: Int?
                    let croppedHeight: Int?
                }
            }
        }
    }
}

nonisolated struct LRLinks: Decodable {
    let next: LRLink?
}

nonisolated struct LRLink: Decodable {
    let href: String?
}
