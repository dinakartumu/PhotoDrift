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

enum LiveGradientMotionEffect: String, CaseIterable {
    case simpleEllipse
    case mediumLoops
    case denseKnots
    case gridLattice

    var displayName: String {
        switch self {
        case .simpleEllipse: "Simple shape (ellipse): smooth, calm drift"
        case .mediumLoops: "Medium loops: figure-8 / flowing crossover motion"
        case .denseKnots: "Dense knots: more turbulent, complex color weaving"
        case .gridLattice: "Grid-like knot: repetitive lattice-like shimmer"
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

    @Transient
    var liveGradientMotionEffect: LiveGradientMotionEffect {
        get { WallpaperLiveGradientMotionPreferences.effect }
        set { WallpaperLiveGradientMotionPreferences.effect = newValue }
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

enum WallpaperLiveGradientMotionPreferences {
    static let defaultsKey = "PhotoDrift.liveGradientMotionEffect"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [defaultsKey: LiveGradientMotionEffect.mediumLoops.rawValue])
    }

    static var effect: LiveGradientMotionEffect {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            return LiveGradientMotionEffect(rawValue: raw ?? "") ?? .mediumLoops
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
