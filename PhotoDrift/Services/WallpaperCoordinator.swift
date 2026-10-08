import AppKit

/// Owns the last published wallpaper and recovery after WindowServer transitions.
@MainActor
final class WallpaperCoordinator {
    typealias Apply = (URL, WallpaperScaling, Bool, Set<CGDirectDisplayID>?) throws -> WallpaperService.Warning?
    typealias Sleep = (Duration) async throws -> Void

    private let store: WallpaperStore
    private let apply: Apply
    private let sleep: Sleep
    private let appliesToAllDesktops: () -> Bool
    private var pendingApplication: (() -> Void)?
    private let canInitializeDisplay: (CGDirectDisplayID) -> Bool
    private let displayIDs: () -> Set<CGDirectDisplayID>
    private var knownDisplayIDs: Set<CGDirectDisplayID>
    var shouldRecover: () -> Bool = { true }
    private let legacyWallpaper: () -> (data: Data, isPNG: Bool, scaling: WallpaperScaling)?
    private var current: WallpaperStore.Wallpaper?
    private(set) var refreshTask: Task<Void, Never>?
    var onRefreshError: ((String?) -> Void)?

    struct ApplicationError: LocalizedError {
        let underlying: Error
        var errorDescription: String? { "Wallpaper refresh failed: \(underlying.localizedDescription)" }
    }

    init(
        store: WallpaperStore = WallpaperStore(),
        appliesToAllDesktops: @escaping () -> Bool = { WallpaperTargetPreferences.applyToAllDesktops },
        legacyWallpaper: @escaping () -> (data: Data, isPNG: Bool, scaling: WallpaperScaling)? = { WallpaperService.existingPhotoDriftWallpaper() },
        displayIDs: @escaping () -> Set<CGDirectDisplayID> = { WallpaperService.connectedDisplayIDs },
        canInitializeDisplay: @escaping (CGDirectDisplayID) -> Bool = { WallpaperService.canInitializeDisplay($0) },
        apply: @escaping Apply = { try WallpaperService.setWallpaper(from: $0, scaling: $1, applyToAllDesktops: $2, displayIDs: $3) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.appliesToAllDesktops = appliesToAllDesktops
        self.legacyWallpaper = legacyWallpaper
        self.apply = apply
        self.sleep = sleep
        self.canInitializeDisplay = canInitializeDisplay
        self.displayIDs = displayIDs
        knownDisplayIDs = displayIDs()
        current = store.restore()
    }

    deinit { refreshTask?.cancel() }

    @discardableResult
    func publish(data: Data, isPNG: Bool, scaling: WallpaperScaling, applyToAllDesktops: Bool, onApplied: (() -> Void)? = nil) throws -> WallpaperService.Warning? {
        current = try store.publish(data: data, isPNG: isPNG, scaling: scaling)
        pendingApplication = onApplied
        cancelRefresh()
        guard let current else { return nil }
        // Even a successful API call can precede the end of a Mission Control transition.
        // A delayed call cannot be bound to a Space with public APIs. In current-desktop
        // mode, apply once so a fast Space switch can never receive a stale retry.
        defer { if applyToAllDesktops { scheduleRetries(requiresAllDesktops: true) } }
        do {
            let warning = try apply(store.url(for: current), current.scaling, applyToAllDesktops, nil)
            completePendingApplication()
            onRefreshError?(nil)
            return warning
        } catch {
            if !applyToAllDesktops { pendingApplication = nil }
            throw ApplicationError(underlying: error)
        }
    }

    func activeSpaceChanged() {
        refresh(requiresAllDesktops: true)
    }

    func screensChanged() {
        let connected = displayIDs()
        let added = connected.subtracting(knownDisplayIDs)
        knownDisplayIDs = connected
        if appliesToAllDesktops() {
            refresh(requiresAllDesktops: true)
        } else {
            cancelRefresh()
            let targets = Set(added.filter(canInitializeDisplay))
            guard shouldRecover(), !targets.isEmpty else { return }
            // Preserve existing desktops and custom images on reconnected displays.
            reapplyCurrent(displayIDs: targets)
        }
    }

    func restoreAfterLaunchOrWake() {
        guard shouldRecover() else { cancelRefresh(); return }
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

    func cancelRefresh(discardPendingApplication: Bool = false) {
        if discardPendingApplication { pendingApplication = nil }
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh(requiresAllDesktops: Bool) {
        cancelRefresh()
        guard shouldRecover(), current != nil, !requiresAllDesktops || appliesToAllDesktops() else { return }
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
                guard let self, self.shouldRecover(), !requiresAllDesktops || self.appliesToAllDesktops() else { return }
                self.reapplyCurrent()
            }
        }
    }

    private func completePendingApplication() {
        let completion = pendingApplication
        pendingApplication = nil
        completion?()
    }

    private func reapplyCurrent(displayIDs: Set<CGDirectDisplayID>? = nil) {
        guard let current else { return }
        do {
            // Uses the existing local file; transition recovery never downloads, renders,
            // or invokes the synchronous all-desktops AppleScript.
            _ = try apply(store.url(for: current), current.scaling, false, displayIDs)
            if displayIDs == nil { completePendingApplication() }
            onRefreshError?(nil)
        } catch {
            onRefreshError?("Wallpaper refresh failed: \(error.localizedDescription)")
        }
    }
}
