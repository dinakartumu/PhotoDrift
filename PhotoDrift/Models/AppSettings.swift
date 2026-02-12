import Foundation
import SwiftData

enum WallpaperScaling: String, CaseIterable {
    case fillScreen
    case fitToScreen
    case stretchToFill
    case center
    case tile

    var displayName: String {
        switch self {
        case .fillScreen: "Fill Screen"
        case .fitToScreen: "Fit to Screen"
        case .stretchToFill: "Stretch to Fill"
        case .center: "Center"
        case .tile: "Tile"
        }
    }
}

@Model
final class AppSettings {
    var shuffleIntervalMinutes: Int
    var photosEnabled: Bool
    var lightroomEnabled: Bool
    var adobeAccessToken: String?
    var adobeRefreshToken: String?
    var adobeTokenExpiry: Date?
    var wallpaperScalingRaw: String = WallpaperScaling.fitToScreen.rawValue

    @Transient
    var wallpaperScaling: WallpaperScaling {
        get { WallpaperScaling(rawValue: wallpaperScalingRaw) ?? .fitToScreen }
        set { wallpaperScalingRaw = newValue.rawValue }
    }

    @Transient
    var applyToAllDesktops: Bool {
        get { WallpaperTargetPreferences.applyToAllDesktops }
        set { WallpaperTargetPreferences.applyToAllDesktops = newValue }
    }

    @Transient
    var useLiveDesktopLayer: Bool {
        get { WallpaperLiveLayerPreferences.isEnabled }
        set { WallpaperLiveLayerPreferences.isEnabled = newValue }
    }

    init(
        shuffleIntervalMinutes: Int = 30,
        photosEnabled: Bool = true,
        lightroomEnabled: Bool = false,
        wallpaperScaling: WallpaperScaling = .fitToScreen
    ) {
        self.shuffleIntervalMinutes = shuffleIntervalMinutes
        self.photosEnabled = photosEnabled
        self.lightroomEnabled = lightroomEnabled
        self.wallpaperScalingRaw = wallpaperScaling.rawValue
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

enum WallpaperTargetPreferences {
    static let defaultsKey = "PhotoDrift.applyToAllDesktops"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [defaultsKey: true])
    }

    static var applyToAllDesktops: Bool {
        get {
            UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }
}

enum WallpaperLiveLayerPreferences {
    static let defaultsKey = "PhotoDrift.useLiveDesktopLayer"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [defaultsKey: false])
    }

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }
}
