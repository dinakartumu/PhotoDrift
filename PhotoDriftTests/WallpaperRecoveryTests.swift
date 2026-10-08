import AppKit
import Foundation
import Testing
import SwiftData
@testable import PhotoDrift

struct WallpaperStoreTests {
    private func makeStore() -> WallpaperStore {
        WallpaperStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("WallpaperStoreTests-\(UUID().uuidString)"))
    }

    @Test func publishedWallpapersSurviveLaterShufflesAndCacheCleanup() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let cache = ImageCacheManager(cacheDirectory: store.directory.appendingPathComponent("downloads"), maxBytes: 1)
        let first = try store.publish(data: Data("first".utf8), isPNG: true, scaling: .fillScreen)
        let second = try store.publish(data: Data("second".utf8), isPNG: false, scaling: .center)
        _ = try await cache.store(data: Data(repeating: 1, count: 20), forKey: "prefetch.jpg")
        try await cache.evictIfNeeded()
        await cache.removeStaleEntries(validKeys: [])
        try await cache.clear()
        #expect(try Data(contentsOf: store.url(for: first)) == Data("first".utf8))
        #expect(try Data(contentsOf: store.url(for: second)) == Data("second".utf8))
        #expect(WallpaperStore(directory: store.directory).restore() == second)
    }

    @Test func identicalPublishedImagesAreDeduplicated() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let data = Data("photo".utf8)
        let first = try store.publish(data: data, isPNG: false, scaling: .center)
        let second = try store.publish(data: data, isPNG: false, scaling: .fillScreen)
        #expect(store.url(for: first) == store.url(for: second))
        #expect(store.restore()?.scaling == .fillScreen)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).count == 2)
    }

    @Test func missingOrCorruptSavedWallpaperDoesNotRestore() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.restore() == nil)
        let wallpaper = try store.publish(data: Data("photo".utf8), isPNG: true, scaling: .fillScreen)
        try FileManager.default.removeItem(at: store.url(for: wallpaper))
        #expect(store.restore() == nil)
        try Data("invalid json".utf8).write(to: store.directory.appendingPathComponent("current.json"))
        #expect(store.restore() == nil)
    }

    @Test func publishedDirectoryIsOutsideDisposableAndPurgeableCaches() {
        #expect(WallpaperStore.defaultDirectory != ImageCacheManager.defaultCacheDirectory)
        #expect(WallpaperStore.defaultDirectory.path.contains("/Application Support/"))
    }
}

@MainActor
struct WallpaperRecoveryTests {
    @MainActor private final class Harness {
        let cache: ImageCacheManager
        let store: WallpaperStore
        var coordinator: WallpaperCoordinator!
        var urls: [URL] = []
        var automation: [Bool] = []
        var delays: [Duration] = []
        var allDesktops = true
        var displays: Set<CGDirectDisplayID> = [1]
        var canInitialize = true
        var targets: [Set<CGDirectDisplayID>?] = []
        var failuresRemaining = 0
        var warning: WallpaperService.Warning?
        var errors: [String?] = []

        init() throws {
            store = WallpaperStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("WallpaperRecoveryTests-\(UUID().uuidString)"))
            cache = ImageCacheManager(cacheDirectory: store.directory.appendingPathComponent("downloads"))
            _ = try store.publish(data: Data("current".utf8), isPNG: true, scaling: .fillScreen)
            coordinator = WallpaperCoordinator(
                store: store,
                appliesToAllDesktops: { [unowned self] in self.allDesktops },
                displayIDs: { [unowned self] in self.displays },
                canInitializeDisplay: { [unowned self] _ in self.canInitialize },
                apply: { [unowned self] url, _, automate, targets in
                    self.targets.append(targets)
                    self.urls.append(url)
                    self.automation.append(automate)
                    if self.failuresRemaining > 0 {
                        self.failuresRemaining -= 1
                        throw CocoaError(.fileReadUnknown)
                    }
                    return self.warning
                },
                sleep: { [unowned self] delay in self.delays.append(delay) }
            )
            coordinator.onRefreshError = { [unowned self] in self.errors.append($0) }
        }

        func cleanup() {
            coordinator.cancelRefresh()
            try? FileManager.default.removeItem(at: store.directory)
        }
    }

    @Test func rapidSpaceChangesApplyImmediatelyAndRetryTheFinalEvent() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.coordinator.activeSpaceChanged()
        let superseded = h.coordinator.refreshTask
        h.coordinator.activeSpaceChanged()
        #expect(h.urls.count == 2) // The old 400 ms throttle lost the second event.
        await superseded?.value
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 5) // Two immediate calls, only the latest three retries.
        #expect(h.automation.allSatisfy { !$0 })
    }

    @Test func successfulEarlyApplyIsRepeatedAfterTransitionSettles() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.coordinator.activeSpaceChanged()
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 4)
        #expect(h.delays == [.milliseconds(250), .milliseconds(750), .seconds(1)])
    }

    @Test func transientFailureRetriesAndClearsTheRefreshError() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.failuresRemaining = 2
        h.coordinator.screensChanged()
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 4)
        #expect(h.errors.prefix(2).allSatisfy { $0 != nil })
        #expect(h.errors.suffix(2).allSatisfy { $0 == nil })
    }

    @Test func newerShuffleCancelsRetriesOfTheOldImage() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.coordinator.activeSpaceChanged()
        let obsoleteTask = h.coordinator.refreshTask
        let oldURL = try #require(h.urls.first)
        try h.coordinator.publish(data: Data("new".utf8), isPNG: false, scaling: .center, applyToAllDesktops: true)
        await obsoleteTask?.value
        await h.coordinator.refreshTask?.value
        let newURL = try #require(h.urls.last)
        #expect(newURL != oldURL)
        #expect(h.urls.dropFirst().allSatisfy { $0 == newURL })
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
    }

    @Test func launchAndWakeUsePersistedImageWithoutFirstShuffle() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.coordinator.restoreAfterLaunchOrWake()
        #expect(h.urls.count == 1)
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 4)
        #expect(h.automation.allSatisfy { !$0 })
    }

    @Test func upgradeImportsExistingWallpaperBeforeFirstShuffle() async throws {
        let store = WallpaperStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("WallpaperUpgradeTests-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let data = Data("legacy wallpaper".utf8)
        var applied: [URL] = []
        let coordinator = WallpaperCoordinator(
            store: store, appliesToAllDesktops: { true },
            legacyWallpaper: { (data, true, .fillScreen) },
            apply: { url, _, _, _ in applied.append(url); return nil },
            sleep: { _ in }
        )
        defer { coordinator.cancelRefresh() }
        coordinator.restoreAfterLaunchOrWake()
        #expect(applied.count == 1)
        let saved = try #require(store.restore())
        #expect(try Data(contentsOf: store.url(for: saved)) == data)
        await coordinator.refreshTask?.value
        #expect(applied.count == 4)
    }

    @Test func failedInitialApplyStillPersistsAndRetriesTheIntendedWallpaper() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.failuresRemaining = 1
        #expect(throws: WallpaperCoordinator.ApplicationError.self) {
            try h.coordinator.publish(data: Data("new".utf8), isPNG: false, scaling: .center, applyToAllDesktops: true)
        }
        let saved = try #require(h.store.restore())
        #expect(try Data(contentsOf: h.store.url(for: saved)) == Data("new".utf8))
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 4)
        #expect(h.urls.allSatisfy { $0 == h.store.url(for: saved) })
    }

    @Test func currentDesktopModeDoesNotOverwriteSwitchedSpaces() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.allDesktops = false
        try h.coordinator.publish(data: Data("new".utf8), isPNG: false, scaling: .center, applyToAllDesktops: false)
        let pending = h.coordinator.refreshTask
        h.coordinator.activeSpaceChanged()
        await pending?.value
        #expect(h.urls.count == 1)
        h.coordinator.restoreAfterLaunchOrWake()
        #expect(h.urls.count == 1)
        h.coordinator.screensChanged() // Resolution/arrangement changes preserve Space B.
        #expect(h.urls.count == 1)
        h.displays.insert(2)
        h.coordinator.screensChanged()
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 2)
        #expect(h.targets.last! == Set([2])) // Only the attached monitor, never Space B.
    }

    @Test func currentDesktopModePreservesCustomWallpaperOnReconnect() throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.allDesktops = false
        h.displays = []
        h.coordinator.screensChanged()
        h.canInitialize = false
        h.displays = [1]
        h.coordinator.screensChanged()
        #expect(h.urls.isEmpty)
    }

    @Test func disablingAllDesktopsStopsPendingSpaceRetries() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.coordinator.activeSpaceChanged()
        h.allDesktops = false
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 1)
    }

    private func makeEngine(_ h: Harness) throws -> (ShuffleEngine, ModelContainer, Album) {
        WallpaperTargetPreferences.registerDefaults()
        let container = try makeTestContainer()
        let context = container.mainContext
        let album = Album(id: UUID().uuidString, name: "Test", sourceType: .lightroomCloud, isSelected: true)
        context.insert(album)
        context.insert(AppSettings(photosEnabled: false, lightroomEnabled: true, wallpaperScaling: .center))
        context.insert(Asset(id: album.id, sourceType: .lightroomCloud, album: album))
        try context.save()
        return (ShuffleEngine(modelContainer: container, wallpaperCoordinator: h.coordinator, imageCache: h.cache), container, album)
    }

    @Test func initialPublicationErrorClearsAfterRecoveryInEngine() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let (engine, container, album) = try makeEngine(h)
        _ = container // Keep the in-memory database alive through the operation.
        let key = ImageCacheManager.cacheKey(for: album.id)
        _ = try await h.cache.store(data: Data("photo".utf8), forKey: key)
        @MainActor final class ObservedStatus { var sawFailure = false }
        let observed = ObservedStatus()
        let token = NotificationCenter.default.addObserver(forName: .shuffleEngineStateChanged, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated {
                if engine.statusMessage?.hasPrefix("Wallpaper refresh failed:") == true { observed.sawFailure = true }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        h.failuresRemaining = 1
        await engine.shuffleNow()
        #expect(observed.sawFailure)
        await h.coordinator.refreshTask?.value
        #expect(engine.statusMessage == nil)
        #expect(engine.lastShuffleDate != nil)
        #expect(engine.currentSource == "Lightroom")
        let appliedDate = engine.lastShuffleDate
        h.coordinator.activeSpaceChanged()
        await h.coordinator.refreshTask?.value
        #expect(engine.lastShuffleDate == appliedDate) // Bookkeeping runs exactly once.
        await h.cache.remove(forKey: key)
    }

    @Test func transientRefreshErrorDoesNotEraseAutomationWarning() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let (engine, container, album) = try makeEngine(h)
        _ = container
        let key = ImageCacheManager.cacheKey(for: album.id)
        _ = try await h.cache.store(data: Data("photo".utf8), forKey: key)
        h.warning = .allDesktopsPermissionDenied
        await engine.shuffleNow()
        let warning = try #require(engine.statusMessage)
        h.failuresRemaining = 1
        h.coordinator.activeSpaceChanged()
        #expect(engine.statusMessage != warning)
        await h.coordinator.refreshTask?.value
        #expect(engine.statusMessage == warning)
        await h.cache.remove(forKey: key)
    }

    @Test func displayedDownloadsAreConsumedSoEditedAssetsCanRefresh() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let (engine, container, album) = try makeEngine(h)
        _ = container
        let key = ImageCacheManager.cacheKey(for: album.id)
        _ = try await h.cache.store(data: Data("original".utf8), forKey: key)
        await engine.shuffleNow()
        let old = try #require(h.store.restore())
        #expect(await h.cache.retrieve(forKey: key) == nil)
        _ = try await h.cache.store(data: Data("edited".utf8), forKey: key)
        await engine.shuffleNow()
        let new = try #require(h.store.restore())
        #expect(try Data(contentsOf: h.store.url(for: new)) == Data("edited".utf8))
        #expect(try Data(contentsOf: h.store.url(for: old)) == Data("original".utf8))
        #expect(await h.cache.retrieve(forKey: key) == nil)
    }

    @Test func newShuffleMessageReplacesStaleRecoveryError() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let (engine, container, album) = try makeEngine(h)
        h.failuresRemaining = 1
        h.coordinator.activeSpaceChanged()
        #expect(engine.statusMessage?.hasPrefix("Wallpaper refresh failed:") == true)
        album.isSelected = false
        try container.mainContext.save()
        await engine.shuffleNow()
        #expect(engine.statusMessage == "No photos available")
    }

    @Test func overlappingShufflesDoNotConsumeTheSameDownloadTwice() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let (engine, container, album) = try makeEngine(h)
        _ = container
        let key = ImageCacheManager.cacheKey(for: album.id)
        _ = try await h.cache.store(data: Data("photo".utf8), forKey: key)
        async let first: Void = engine.shuffleNow()
        async let second: Void = engine.shuffleNow()
        _ = await (first, second)
        await h.coordinator.refreshTask?.value
        #expect(h.automation.filter { $0 }.count == 1)
        #expect(engine.statusMessage == nil)
    }

    @Test func failedSnapshotSavePreservesTheDownloadedPhoto() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let (engine, container, album) = try makeEngine(h)
        _ = container
        let key = ImageCacheManager.cacheKey(for: album.id)
        let data = Data("photo".utf8)
        _ = try await h.cache.store(data: data, forKey: key)
        let manifest = h.store.directory.appendingPathComponent("current.json")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        await engine.shuffleNow()
        #expect(await h.cache.data(forKey: key) == data)
        #expect(engine.lastShuffleDate == nil)
        #expect(engine.statusMessage?.hasPrefix("Error:") == true)
    }

    @Test func failedCurrentDesktopPublishCannotCompleteOnAnUnrelatedLaterEvent() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.allDesktops = false
        h.failuresRemaining = 1
        var completions = 0
        #expect(throws: WallpaperCoordinator.ApplicationError.self) {
            try h.coordinator.publish(data: Data("new".utf8), isPNG: false, scaling: .center, applyToAllDesktops: false, onApplied: { completions += 1 })
        }
        h.displays.insert(2)
        h.coordinator.screensChanged()
        h.allDesktops = true
        h.coordinator.restoreAfterLaunchOrWake()
        await h.coordinator.refreshTask?.value
        #expect(completions == 0)
    }

    @Test func pauseAndDeselectionDisableEnvironmentalRecovery() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let (engine, container, album) = try makeEngine(h)
        h.coordinator.activeSpaceChanged()
        #expect(h.urls.count == 1)
        album.isSelected = false
        try container.mainContext.save()
        h.coordinator.restoreAfterLaunchOrWake()
        h.coordinator.screensChanged()
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 1)
        album.isSelected = true
        try container.mainContext.save()
        engine.stop()
        h.coordinator.activeSpaceChanged()
        h.coordinator.restoreAfterLaunchOrWake()
        h.displays.insert(2)
        h.coordinator.screensChanged()
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 1)
    }

    @Test func displayAndSpaceNotificationsReachRecoveryOnTheirRespectiveCenters() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        let appCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = WallpaperEnvironmentObserver(
            coordinator: h.coordinator, applicationCenter: appCenter, workspaceCenter: workspaceCenter
        )
        defer { observer.stop() }
        appCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(h.urls.count == 1)
        workspaceCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        #expect(h.urls.count == 2)
        await h.coordinator.refreshTask?.value
        observer.stop()
        appCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        #expect(h.urls.count == 5)
    }
}
