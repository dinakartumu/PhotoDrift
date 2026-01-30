import Foundation

struct LRCatalog: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id
    }
}

struct LRCatalogResponse: Decodable {
    let id: String
}

struct LRAlbumsResponse: Decodable {
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

struct LRAlbumAssetsResponse: Decodable {
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

struct LRLinks: Decodable {
    let next: LRLink?
}

struct LRLink: Decodable {
    let href: String?
}
