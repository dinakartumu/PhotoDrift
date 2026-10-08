import AppKit
import Foundation
import Testing
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
        let store: WallpaperStore
        var coordinator: WallpaperCoordinator!
        var urls: [URL] = []
        var automation: [Bool] = []
        var delays: [Duration] = []
        var allDesktops = true
        var failuresRemaining = 0
        var errors: [String?] = []

        init() throws {
            store = WallpaperStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("WallpaperRecoveryTests-\(UUID().uuidString)"))
            _ = try store.publish(data: Data("current".utf8), isPNG: true, scaling: .fillScreen)
            coordinator = WallpaperCoordinator(
                store: store,
                appliesToAllDesktops: { [unowned self] in self.allDesktops },
                apply: { [unowned self] url, _, automate in
                    self.urls.append(url)
                    self.automation.append(automate)
                    if self.failuresRemaining > 0 {
                        self.failuresRemaining -= 1
                        throw CocoaError(.fileReadUnknown)
                    }
                    return nil
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
            apply: { url, _, _ in applied.append(url); return nil },
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
        #expect(throws: CocoaError.self) {
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
        h.coordinator.screensChanged()
        await h.coordinator.refreshTask?.value
        #expect(h.urls.count == 5) // Monitor attachment still gets the current wallpaper.
    }

    @Test func disablingAllDesktopsStopsPendingSpaceRetries() async throws {
        let h = try Harness()
        defer { h.cleanup() }
        h.coordinator.activeSpaceChanged()
        h.allDesktops = false
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
