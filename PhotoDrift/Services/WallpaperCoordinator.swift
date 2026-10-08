import AppKit

/// Owns the last published wallpaper and recovery after WindowServer transitions.
@MainActor
final class WallpaperCoordinator {
    typealias Apply = (URL, WallpaperScaling, Bool) throws -> WallpaperService.Warning?
    typealias Sleep = (Duration) async throws -> Void

    private let store: WallpaperStore
    private let apply: Apply
    private let sleep: Sleep
    private let appliesToAllDesktops: () -> Bool
    private let legacyWallpaper: () -> (data: Data, isPNG: Bool, scaling: WallpaperScaling)?
    private var current: WallpaperStore.Wallpaper?
    private(set) var refreshTask: Task<Void, Never>?
    var onRefreshError: ((String?) -> Void)?

    init(
        store: WallpaperStore = WallpaperStore(),
        appliesToAllDesktops: @escaping () -> Bool = { WallpaperTargetPreferences.applyToAllDesktops },
        legacyWallpaper: @escaping () -> (data: Data, isPNG: Bool, scaling: WallpaperScaling)? = { WallpaperService.existingPhotoDriftWallpaper() },
        apply: @escaping Apply = { try WallpaperService.setWallpaper(from: $0, scaling: $1, applyToAllDesktops: $2) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.appliesToAllDesktops = appliesToAllDesktops
        self.legacyWallpaper = legacyWallpaper
        self.apply = apply
        self.sleep = sleep
        current = store.restore()
    }

    deinit { refreshTask?.cancel() }

    @discardableResult
    func publish(data: Data, isPNG: Bool, scaling: WallpaperScaling, applyToAllDesktops: Bool) throws -> WallpaperService.Warning? {
        current = try store.publish(data: data, isPNG: isPNG, scaling: scaling)
        cancelRefresh()
        guard let current else { return nil }
        // Even a successful API call can precede the end of a Mission Control transition.
        defer { scheduleRetries(requiresAllDesktops: false) }
        return try apply(store.url(for: current), current.scaling, applyToAllDesktops)
    }

    func activeSpaceChanged() {
        refresh(requiresAllDesktops: true)
    }

    func screensChanged() {
        // A newly attached display needs the current image even in current-desktop mode.
        refresh(requiresAllDesktops: false)
    }

    func restoreAfterLaunchOrWake() {
        // Upgrade from versions that kept the current URL only in memory. Import a
        // readable PhotoDrift desktop image before album synchronization can delay us.
        if current == nil, let legacy = legacyWallpaper() {
            do {
                current = try store.publish(data: legacy.data, isPNG: legacy.isPNG, scaling: legacy.scaling)
            } catch {
                onRefreshError?("Wallpaper refresh failed: \(error.localizedDescription)")
            }
        }
        refresh(requiresAllDesktops: true)
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh(requiresAllDesktops: Bool) {
        cancelRefresh()
        guard current != nil, !requiresAllDesktops || appliesToAllDesktops() else { return }
        reapplyCurrent()
        scheduleRetries(requiresAllDesktops: requiresAllDesktops)
    }

    private func scheduleRetries(requiresAllDesktops: Bool) {
        cancelRefresh()
        refreshTask = Task { [weak self, sleep] in
            // Offsets of 250 ms, 1 s, and 2 s cover display attachment and Space animation.
            // A new event replaces this sequence; no final event is discarded.
            for delay in [Duration.milliseconds(250), .milliseconds(750), .seconds(1)] {
                do {
                    try Task.checkCancellation()
                    try await sleep(delay)
                    try Task.checkCancellation()
                } catch { return }
                guard let self, !requiresAllDesktops || self.appliesToAllDesktops() else { return }
                self.reapplyCurrent()
            }
        }
    }

    private func reapplyCurrent() {
        guard let current else { return }
        do {
            // Uses the existing local file; transition recovery never downloads, renders,
            // or invokes the synchronous all-desktops AppleScript.
            _ = try apply(store.url(for: current), current.scaling, false)
            onRefreshError?(nil)
        } catch {
            onRefreshError?("Wallpaper refresh failed: \(error.localizedDescription)")
        }
    }
}
