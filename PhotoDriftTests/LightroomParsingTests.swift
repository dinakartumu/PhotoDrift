import Testing
import Foundation
@testable import PhotoDrift

struct LightroomParsingTests {
    // MARK: - stripJsonJunkPrefix

    @Test func stripJsonJunkPrefixRemovesWhile1Prefix() {
        let prefixed = "while (1) {}\n{\"id\": \"abc123\"}"
        let data = Data(prefixed.utf8)
        let cleaned = LightroomAPIClient.stripJsonJunkPrefix(from: data)
        let result = String(data: cleaned, encoding: .utf8)
        #expect(result == "{\"id\": \"abc123\"}")
    }

    @Test func stripJsonJunkPrefixReturnsUnchangedIfNoPrefix() {
        let json = "{\"id\": \"abc123\"}"
        let data = Data(json.utf8)
        let cleaned = LightroomAPIClient.stripJsonJunkPrefix(from: data)
        #expect(cleaned == data)
    }

    @Test func stripJsonJunkPrefixHandlesWhitespace() {
        let prefixed = "  while (1) {}  \n  {\"id\": \"test\"}"
        let data = Data(prefixed.utf8)
        let cleaned = LightroomAPIClient.stripJsonJunkPrefix(from: data)
        let result = String(data: cleaned, encoding: .utf8)
        #expect(result == "{\"id\": \"test\"}")
    }

    // MARK: - LRCatalogResponse decoding

    @Test func catalogResponseDecodes() throws {
        let json = """
        {"id": "catalog-12345"}
        """
        let data = Data(json.utf8)
        let catalog = try JSONDecoder().decode(LRCatalogResponse.self, from: data)
        #expect(catalog.id == "catalog-12345")
    }

    // MARK: - LRAlbumsResponse decoding

    @Test func albumsResponseDecodesWithPaginationLinks() throws {
        let json = """
        {
            "resources": [
                {
                    "id": "album-1",
                    "subtype": "collection",
                    "payload": {"name": "Vacation Photos"}
                },
                {
                    "id": "album-2",
                    "subtype": "collection",
                    "payload": {"name": "Nature"}
                }
            ],
            "links": {
                "next": {
                    "href": "albums?offset=100"
                }
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(LRAlbumsResponse.self, from: data)
        #expect(response.resources?.count == 2)
        #expect(response.resources?[0].id == "album-1")
        #expect(response.resources?[0].payload?.name == "Vacation Photos")
        #expect(response.links?.next?.href == "albums?offset=100")
    }

    @Test func albumsResponseDecodesWithNoNextLink() throws {
        let json = """
        {
            "resources": [
                {
                    "id": "album-1",
                    "subtype": "collection",
                    "payload": {"name": "Last Page Album"}
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(LRAlbumsResponse.self, from: data)
        #expect(response.resources?.count == 1)
        #expect(response.links == nil)
    }

    // MARK: - LRAlbumAssetsResponse decoding

    @Test func albumAssetsResponseDecodesAssetResources() throws {
        let json = """
        {
            "resources": [
                {
                    "asset": {
                        "id": "asset-abc",
                        "payload": {
                            "develop": {
                                "croppedWidth": 3000,
                                "croppedHeight": 2000
                            }
                        }
                    }
                },
                {
                    "asset": {
                        "id": "asset-def",
                        "payload": null
                    }
                }
            ],
            "links": {
                "next": {
                    "href": "albums/a1/assets?offset=500&limit=500"
                }
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(LRAlbumAssetsResponse.self, from: data)
        #expect(response.resources?.count == 2)
        #expect(response.resources?[0].asset.id == "asset-abc")
        #expect(response.resources?[0].asset.payload?.develop?.croppedWidth == 3000)
        #expect(response.resources?[0].asset.payload?.develop?.croppedHeight == 2000)
        #expect(response.resources?[1].asset.id == "asset-def")
        #expect(response.resources?[1].asset.payload == nil)
        #expect(response.links?.next?.href == "albums/a1/assets?offset=500&limit=500")
    }

    @Test func albumAssetsResponseDecodesEmptyResources() throws {
        let json = """
        {
            "resources": []
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(LRAlbumAssetsResponse.self, from: data)
        #expect(response.resources?.isEmpty == true)
        #expect(response.links == nil)
    }
}
