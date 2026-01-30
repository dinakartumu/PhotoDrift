import Foundation
import SwiftData

@Model
final class Album {
    @Attribute(.unique) var id: String
    var name: String
    var sourceTypeRaw: String
    var isSelected: Bool
    var assetCount: Int

    @Relationship(deleteRule: .cascade, inverse: \Asset.album)
    var assets: [Asset]

    @Transient
    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .applePhotos }
        set { sourceTypeRaw = newValue.rawValue }
    }

    init(id: String, name: String, sourceType: SourceType, isSelected: Bool = false, assetCount: Int = 0) {
        self.id = id
        self.name = name
        self.sourceTypeRaw = sourceType.rawValue
        self.isSelected = isSelected
        self.assetCount = assetCount
        self.assets = []
    }
}
