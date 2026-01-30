import Foundation
import SwiftData

@Model
final class AppSettings {
    var shuffleIntervalMinutes: Int
    var photosEnabled: Bool
    var lightroomEnabled: Bool
    var adobeAccessToken: String?
    var adobeRefreshToken: String?
    var adobeTokenExpiry: Date?

    init(
        shuffleIntervalMinutes: Int = 30,
        photosEnabled: Bool = true,
        lightroomEnabled: Bool = false
    ) {
        self.shuffleIntervalMinutes = shuffleIntervalMinutes
        self.photosEnabled = photosEnabled
        self.lightroomEnabled = lightroomEnabled
    }

    static func current(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
