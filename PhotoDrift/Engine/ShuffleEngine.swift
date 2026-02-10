import Foundation
import Combine
import SwiftData
import AppKit
import Photos

extension Notification.Name {
    static let shuffleEngineStateChanged = Notification.Name("shuffleEngineStateChanged")
    static let lightroomAuthStateChanged = Notification.Name("lightroomAuthStateChanged")
}

final class ShuffleEngine {
    private(set) var isRunning = false
    private(set) var lastShuffleDate: Date?
    private(set) var nextShuffleDate: Date?
    private(set) var currentSource: String?
    private(set) var statusMessage: String?

    private var timerCancellable: AnyCancellable?
    private var observerCancellable: AnyCancellable?
    private var lightroomPollCancellable: AnyCancellable?
    private var selection = ShuffleSelection()
    private let modelContainer: ModelContainer
    private let unifiedPool: UnifiedPool
    private let photoObserver = PhotoLibraryObserver()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.unifiedPool = UnifiedPool(modelContainer: modelContainer)
    }

    var intervalMinutes: Int {
        let context = ModelContext(modelContainer)
        return AppSettings.current(in: context).shuffleIntervalMinutes
    }

    func syncAssets(forAlbumID albumID: String) async {
        await unifiedPool.syncAssets(forAlbumID: albumID)
    }

    func clearAssetsIfAlbumDeselected(forAlbumID albumID: String) async {
        await unifiedPool.clearAssetsIfAlbumDeselected(forAlbumID: albumID)
    }

    @discardableResult
    func setAlbumSelection(forAlbumID albumID: String, isSelected: Bool) async -> Bool {
        await unifiedPool.setAlbumSelection(forAlbumID: albumID, isSelected: isSelected)
    }

    func setAlbumsSelection(for source: SourceType, isSelected: Bool) async -> [String] {
        await unifiedPool.setAlbumsSelection(for: source, isSelected: isSelected)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNext()
        startObservers()
        cleanStaleCacheEntries()
        postStateChange()
    }

    private func cleanStaleCacheEntries() {
        Task {
            do {
                let pool = try await unifiedPool.buildPool()
                let validKeys = Set(pool.map { ImageCacheManager.cacheKey(for: $0.id) })
                await ImageCacheManager.shared.removeStaleEntries(validKeys: validKeys)
            } catch {
                // Non-critical — stale entries will be evicted by LRU
            }
        }
    }

    func stop() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        nextShuffleDate = nil
        stopObservers()
        postStateChange()
    }

    func shuffleNow() async {
        await performShuffle()
        if isRunning {
            scheduleNext()
        }
    }

    private func startObservers() {
        let photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photosStatus == .authorized || photosStatus == .limited {
            photoObserver.startObserving()
            observerCancellable = photoObserver.debouncedChanges
                .sink { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.unifiedPool.syncPhotosAlbums()
                    }
                }
        }

        // Poll Lightroom every 15 minutes
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        if settings.lightroomEnabled {
            lightroomPollCancellable = Timer.publish(every: 900, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task {
                        await self.unifiedPool.syncLightroomAlbums()
                    }
                }
        }
    }

    private func stopObservers() {
        photoObserver.stopObserving()
        observerCancellable?.cancel()
        observerCancellable = nil
        lightroomPollCancellable?.cancel()
        lightroomPollCancellable = nil
    }

    private func scheduleNext() {
        timerCancellable?.cancel()
        let interval = TimeInterval(intervalMinutes * 60)
        nextShuffleDate = Date().addingTimeInterval(interval)

        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.performShuffle()
                    self.scheduleNext()
                }
            }
    }

    @MainActor
    private func performShuffle() async {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        let scaling = settings.wallpaperScaling
        let applyToAllDesktops = settings.applyToAllDesktops

        var pool: [UnifiedPool.PoolEntry]
        do {
            pool = try await unifiedPool.buildPool()
        } catch {
            statusMessage = "Error loading albums: \(error.localizedDescription)"
            postStateChange()
            return
        }

        if pool.isEmpty {
            statusMessage = "Syncing selected albums..."
            postStateChange()

            let syncFailures = await unifiedPool.syncSelectedAlbums()

            do {
                pool = try await unifiedPool.buildPool()
            } catch {
                statusMessage = "Error loading albums: \(error.localizedDescription)"
                postStateChange()
                return
            }

            if !syncFailures.isEmpty && pool.isEmpty {
                statusMessage = syncFailures[0]
                postStateChange()
                return
            }
        }

        guard !pool.isEmpty else {
            let selectedDescriptor = FetchDescriptor<Album>(
                predicate: #Predicate { $0.isSelected == true }
            )
            let selectedAlbums = (try? context.fetch(selectedDescriptor)) ?? []
            let enabledSelectedAlbums = selectedAlbums.filter { album in
                switch album.sourceType {
                case .applePhotos: settings.photosEnabled
                case .lightroomCloud: settings.lightroomEnabled
                }
            }
            if enabledSelectedAlbums.isEmpty, !selectedAlbums.isEmpty {
                statusMessage = "Selected albums are disabled in Sources"
            } else {
                statusMessage = !enabledSelectedAlbums.isEmpty ? "No synced photos yet" : "No photos available"
            }
            postStateChange()
            return
        }

        guard let pick = selection.select(from: pool) else { return }

        statusMessage = "Fetching photo..."
        postStateChange()

        do {
            // Check cache first
            let key = ImageCacheManager.cacheKey(for: pick.id)
            if let cached = await ImageCacheManager.shared.retrieve(forKey: key) {
                let cachedData = try Data(contentsOf: cached)
                let warning = try setWallpaper(
                    imageData: cachedData,
                    rawURL: cached,
                    assetID: pick.id,
                    scaling: scaling,
                    applyToAllDesktops: applyToAllDesktops
                )
                addToHistory(pick.id)
                lastShuffleDate = Date()
                currentSource = pick.sourceType == .applePhotos ? "Photos" : "Lightroom"
                statusMessage = wallpaperWarningMessage(from: warning)
                postStateChange()
                prefetchInBackground(pool: pool)
                return
            }

            let imageData: Data
            switch pick.sourceType {
            case .applePhotos:
                imageData = try await PhotoKitConnector.shared.requestImage(assetID: pick.id)
                currentSource = "Photos"
            case .lightroomCloud:
                imageData = try await LightroomConnector.shared.downloadImage(assetID: pick.id)
                currentSource = "Lightroom"
            }

            let url = try await ImageCacheManager.shared.store(data: imageData, forKey: key)
            let warning = try setWallpaper(
                imageData: imageData,
                rawURL: url,
                assetID: pick.id,
                scaling: scaling,
                applyToAllDesktops: applyToAllDesktops
            )

            addToHistory(pick.id)
            lastShuffleDate = Date()
            statusMessage = wallpaperWarningMessage(from: warning)

            postStateChange()
            prefetchInBackground(pool: pool)
        } catch let error as AdobeAuthError where error == .noRefreshToken {
            statusMessage = "Lightroom: please sign in again"
            NotificationCenter.default.post(name: .lightroomAuthStateChanged, object: nil)
            postStateChange()
        } catch is URLError {
            // Network offline — try Photos-only fallback
            let photosOnly = pool.filter { $0.sourceType == .applePhotos }
            if let fallback = photosOnly.randomElement() {
                do {
                    let data = try await PhotoKitConnector.shared.requestImage(assetID: fallback.id)
                    let key = ImageCacheManager.cacheKey(for: fallback.id)
                    let url = try await ImageCacheManager.shared.store(data: data, forKey: key)
                    let warning = try setWallpaper(
                        imageData: data,
                        rawURL: url,
                        assetID: fallback.id,
                        scaling: scaling,
                        applyToAllDesktops: applyToAllDesktops
                    )
                    addToHistory(fallback.id)
                    lastShuffleDate = Date()
                    currentSource = "Photos (offline)"
                    statusMessage = wallpaperWarningMessage(from: warning)
                } catch {
                    statusMessage = "Offline, no cached photos available"
                }
            } else {
                statusMessage = "Network offline"
            }
            postStateChange()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            postStateChange()
        }
    }

    private static let gradientDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("PhotoDriftImages", isDirectory: true)
    }()

    private func setWallpaper(
        imageData: Data,
        rawURL: URL,
        assetID: String,
        scaling: WallpaperScaling,
        applyToAllDesktops: Bool
    ) throws -> WallpaperService.Warning? {
        if scaling == .fitToScreen {
            let screenSize = ScreenUtility.targetSize
            if let composited = GradientRenderer.composite(imageData: imageData, screenSize: screenSize) {
                let key = ImageCacheManager.cacheKey(for: assetID)
                let name = "gradient_\(key).png"
                let url = Self.gradientDirectory.appendingPathComponent(name)
                try composited.write(to: url)
                return try WallpaperService.setWallpaper(
                    from: url,
                    scaling: .fillScreen,
                    applyToAllDesktops: applyToAllDesktops
                )
            }
        }
        return try WallpaperService.setWallpaper(
            from: rawURL,
            scaling: scaling,
            applyToAllDesktops: applyToAllDesktops
        )
    }

    private func wallpaperWarningMessage(from warning: WallpaperService.Warning?) -> String? {
        guard let warning else { return nil }
        if let description = warning.errorDescription,
           let suggestion = warning.recoverySuggestion {
            return "\(description) \(suggestion)"
        }
        return warning.errorDescription
    }

    private func postStateChange() {
        NotificationCenter.default.post(name: .shuffleEngineStateChanged, object: self)
    }

    private func addToHistory(_ id: String) {
        selection.addToHistory(id)
    }

    @MainActor
    func handleLightroomAuthStateChanged(signedIn: Bool) {
        guard signedIn, statusMessage == "Lightroom: please sign in again" else { return }
        statusMessage = nil
        postStateChange()
    }

    private func prefetchInBackground(pool: [UnifiedPool.PoolEntry]) {
        Task.detached { [weak self] in
            guard let self else { return }
            let candidates = pool.filter { !self.selection.recentHistory.contains($0.id) }
                .shuffled()
                .prefix(3)

            for candidate in candidates {
                let key = ImageCacheManager.cacheKey(for: candidate.id)
                let cached = await ImageCacheManager.shared.retrieve(forKey: key)
                if cached != nil { continue }

                do {
                    switch candidate.sourceType {
                    case .applePhotos:
                        let data = try await PhotoKitConnector.shared.requestImage(assetID: candidate.id)
                        _ = try await ImageCacheManager.shared.store(data: data, forKey: key)
                    case .lightroomCloud:
                        let data = try await LightroomConnector.shared.downloadImage(assetID: candidate.id)
                        _ = try await ImageCacheManager.shared.store(data: data, forKey: key)
                    }
                } catch {
                    // Prefetch failures are non-critical
                }
            }
        }
    }

    func handleWake() {
        guard isRunning else { return }
        if let next = nextShuffleDate, Date() > next {
            Task { await shuffleNow() }
        } else {
            scheduleNext()
        }
    }
}
