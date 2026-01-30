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
    private var recentHistory: [String] = []
    private let maxHistorySize = 20
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

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNext()
        startObservers()
        postStateChange()
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
        let scaling = AppSettings.current(in: context).wallpaperScaling

        let pool: [UnifiedPool.PoolEntry]
        do {
            pool = try await unifiedPool.buildPool()
        } catch {
            statusMessage = "Error loading albums: \(error.localizedDescription)"
            postStateChange()
            return
        }

        guard !pool.isEmpty else {
            statusMessage = "No photos available"
            postStateChange()
            return
        }

        let candidates = pool.filter { !recentHistory.contains($0.id) }
        let available = candidates.isEmpty ? pool : candidates

        guard let pick = available.randomElement() else { return }

        statusMessage = "Fetching photo..."
        postStateChange()

        do {
            // Check cache first
            let key = "\(pick.id.hashValue).jpg"
            if let cached = await ImageCacheManager.shared.retrieve(forKey: key) {
                try WallpaperService.setWallpaper(from: cached, scaling: scaling)
                addToHistory(pick.id)
                lastShuffleDate = Date()
                currentSource = pick.sourceType == .applePhotos ? "Photos" : "Lightroom"
                statusMessage = nil
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
            try WallpaperService.setWallpaper(from: url, scaling: scaling)

            addToHistory(pick.id)
            lastShuffleDate = Date()
            statusMessage = nil

            postStateChange()
            prefetchInBackground(pool: pool)
        } catch let error as AdobeAuthError where error == .noRefreshToken {
            statusMessage = "Lightroom: please sign in again"
            postStateChange()
        } catch is URLError {
            // Network offline — try Photos-only fallback
            let photosOnly = pool.filter { $0.sourceType == .applePhotos }
            if let fallback = photosOnly.randomElement() {
                do {
                    let data = try await PhotoKitConnector.shared.requestImage(assetID: fallback.id)
                    let key = "\(fallback.id.hashValue).jpg"
                    let url = try await ImageCacheManager.shared.store(data: data, forKey: key)
                    try WallpaperService.setWallpaper(from: url, scaling: scaling)
                    addToHistory(fallback.id)
                    lastShuffleDate = Date()
                    currentSource = "Photos (offline)"
                    statusMessage = nil
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

    private func postStateChange() {
        NotificationCenter.default.post(name: .shuffleEngineStateChanged, object: self)
    }

    private func addToHistory(_ id: String) {
        recentHistory.append(id)
        if recentHistory.count > maxHistorySize {
            recentHistory.removeFirst()
        }
    }

    private func prefetchInBackground(pool: [UnifiedPool.PoolEntry]) {
        Task.detached { [weak self] in
            guard let self else { return }
            let candidates = pool.filter { !self.recentHistory.contains($0.id) }
                .shuffled()
                .prefix(3)

            for candidate in candidates {
                let key = "\(candidate.id.hashValue).jpg"
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
