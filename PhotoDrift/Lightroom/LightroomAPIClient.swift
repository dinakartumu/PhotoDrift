import Foundation

actor LightroomAPIClient {
    static let shared = LightroomAPIClient()

    private let baseURL = AdobeConfig.lightroomBaseURL
    private let session = URLSession.shared
    private var retryCount = 0
    private let maxRetries = 2

    func getCatalogID() async throws -> String {
        let data = try await authenticatedRequest(path: "catalog")
        let catalog = try decode(LRCatalogResponse.self, from: data, context: "catalog")
        return catalog.id
    }

    func getAlbums(catalogID: String) async throws -> [LRAlbumsResponse.LRAlbumResource] {
        var allAlbums: [LRAlbumsResponse.LRAlbumResource] = []
        var nextPath: String? = "catalogs/\(catalogID)/albums"
        while let path = nextPath {
            let data = try await authenticatedRequest(path: path)
            let response = try decode(LRAlbumsResponse.self, from: data, context: "albums")
            if let resources = response.resources, !resources.isEmpty {
                allAlbums.append(contentsOf: resources)
            }
            nextPath = response.links?.next?.href
        }

        return allAlbums
    }

    func getAlbumAssets(catalogID: String, albumID: String) async throws -> [LRAlbumAssetsResponse.LRAssetResource] {
        var allAssets: [LRAlbumAssetsResponse.LRAssetResource] = []
        var nextPath: String? = "catalogs/\(catalogID)/albums/\(albumID)/assets?limit=500"
        while let path = nextPath {
            let data = try await authenticatedRequest(path: path)
            let response = try decode(LRAlbumAssetsResponse.self, from: data, context: "album-assets")
            if let resources = response.resources, !resources.isEmpty {
                allAssets.append(contentsOf: resources)
            }
            nextPath = response.links?.next?.href
        }

        return allAssets
    }

    func getRenditionURL(catalogID: String, assetID: String, size: String = "2048") -> URL {
        baseURL.appendingPathComponent("catalogs/\(catalogID)/assets/\(assetID)/renditions/\(size)")
    }

    func downloadRendition(catalogID: String, assetID: String, size: String = "2048") async throws -> Data {
        let url = getRenditionURL(catalogID: catalogID, assetID: assetID, size: size)
        let token = try await AdobeAuthManager.shared.getValidToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AdobeConfig.clientID, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                let newToken = try await AdobeAuthManager.shared.refreshAccessToken()
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: request)
                guard let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 else {
                    throw LightroomError.downloadFailed
                }
                return retryData
            }
            guard httpResponse.statusCode == 200 else {
                throw LightroomError.downloadFailed
            }
        }

        return data
    }

    private func authenticatedRequest(path: String) async throws -> Data {
        let url = URL(string: path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(path)
        let token = try await AdobeAuthManager.shared.getValidToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AdobeConfig.clientID, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                // Token expired — refresh and retry once
                let newToken = try await AdobeAuthManager.shared.refreshAccessToken()
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: request)
                guard let retryHTTP = retryResponse as? HTTPURLResponse, 200..<300 ~= retryHTTP.statusCode else {
                    let retryCode = (retryResponse as? HTTPURLResponse)?.statusCode ?? -1
                    throw LightroomError.apiError(retryCode)
                }
                return retryData
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                logHTTPFailure(response: httpResponse, data: data, context: path)
                throw LightroomError.apiError(httpResponse.statusCode)
            }
        }

        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            let cleaned = stripJsonJunkPrefix(from: data)
            return try JSONDecoder().decode(T.self, from: cleaned)
        } catch {
            logDecodeFailure(data: data, context: context, error: error)
            throw error
        }
    }

    private func logDecodeFailure(data: Data, context: String, error: Error) {
        let snippet = String(decoding: data, as: UTF8.self)
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[LightroomAPIClient] decodeFailed context=\(context) error=\(error)")
        if !trimmed.isEmpty {
            let limited = trimmed.prefix(400)
            print("[LightroomAPIClient] responseSnippet=\(limited)")
        }
    }

    private func logHTTPFailure(response: HTTPURLResponse, data: Data, context: String) {
        let snippet = String(decoding: data, as: UTF8.self)
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[LightroomAPIClient] httpFailed context=\(context) status=\(response.statusCode)")
        if !trimmed.isEmpty {
            let limited = trimmed.prefix(400)
            print("[LightroomAPIClient] responseSnippet=\(limited)")
        }
    }

    private func stripJsonJunkPrefix(from data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "while (1) {}"
        guard trimmed.hasPrefix(prefix) else { return data }
        // Remove the prefix and any following newline characters.
        let remainder = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(remainder.utf8)
    }
}

enum LightroomError: Error, LocalizedError {
    case apiError(Int)
    case downloadFailed
    case noCatalog

    var errorDescription: String? {
        switch self {
        case .apiError(let code): "Lightroom API error (HTTP \(code))"
        case .downloadFailed: "Failed to download rendition"
        case .noCatalog: "No Lightroom catalog found"
        }
    }
}
