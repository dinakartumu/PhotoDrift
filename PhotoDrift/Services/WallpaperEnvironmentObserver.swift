import AppKit

/// The two notifications belong to different centers; keep that wiring in one place.
@MainActor
final class WallpaperEnvironmentObserver {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(
        coordinator: WallpaperCoordinator,
        applicationCenter: NotificationCenter = .default,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        let screenToken = applicationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak coordinator] _ in
            MainActor.assumeIsolated { coordinator?.screensChanged() }
        }
        let spaceToken = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak coordinator] _ in
            MainActor.assumeIsolated { coordinator?.activeSpaceChanged() }
        }
        tokens = [(applicationCenter, screenToken), (workspaceCenter, spaceToken)]
    }

    func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }
}
