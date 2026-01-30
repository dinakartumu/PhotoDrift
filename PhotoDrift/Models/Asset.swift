import Foundation
import SwiftData

@Model
final class Asset {
    @Attribute(.unique) var id: String
    var sourceType: SourceType
    var cachedFilePath: String?
    var width: Int
    var height: Int
    var lastUsedDate: Date?

    var album: Album?

    init(id: String, sourceType: SourceType, width: Int = 0, height: Int = 0, album: Album? = nil) {
        self.id = id
        self.sourceType = sourceType
        self.width = width
        self.height = height
        self.album = album
    }
}
