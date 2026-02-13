import AppKit
import ImageIO

@MainActor
final class LiveDesktopLayerService {
    enum ServiceError: LocalizedError {
        case invalidImageData

        var errorDescription: String? {
            switch self {
            case .invalidImageData:
                return "Unable to decode image data for live desktop layer."
            }
        }
    }

    static let shared = LiveDesktopLayerService()

    private struct ContentState {
        let image: CGImage
        let palette: GradientPalette
        let animateGradient: Bool
        var motionEffect: LiveGradientMotionEffect
    }

    private var windowsByDisplayID: [CGDirectDisplayID: NSWindow] = [:]
    private var viewsByDisplayID: [CGDirectDisplayID: LiveWallpaperRendererView] = [:]
    private var contentState: ContentState?
    private var screenObserver: NSObjectProtocol?

    private init() {}

    func present(
        imageData: Data,
        animateGradient: Bool,
        motionEffect: LiveGradientMotionEffect
    ) throws {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ServiceError.invalidImageData
        }

        let palette = PaletteExtractor.extract(from: imageData)
            ?? GradientPalette(
                topColor: CGColor(red: 0.16, green: 0.23, blue: 0.42, alpha: 1),
                bottomColor: CGColor(red: 0.08, green: 0.11, blue: 0.24, alpha: 1)
            )

        // Non-critical cache for future screensaver/live-session handoff.
        try? SharedWallpaperSnapshotStore.shared.save(imageData: imageData, palette: palette)

        contentState = ContentState(
            image: image,
            palette: palette,
            animateGradient: animateGradient,
            motionEffect: motionEffect
        )
        ensureScreenObserver()
        syncWindowsToCurrentScreens()
        applyCurrentState()
        orderWindowsVisible()
    }

    func hide() {
        for window in windowsByDisplayID.values {
            window.orderOut(nil)
        }
        windowsByDisplayID.removeAll()
        viewsByDisplayID.removeAll()
        contentState = nil
        removeScreenObserver()
    }

    func ensureVisible() {
        guard contentState != nil else { return }
        syncWindowsToCurrentScreens()
        applyCurrentState()
        orderWindowsVisible()
    }

    func updateMotionEffect(_ motionEffect: LiveGradientMotionEffect) {
        guard var contentState else { return }
        contentState.motionEffect = motionEffect
        self.contentState = contentState
        applyCurrentState()
    }

    private func ensureScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.ensureVisible()
        }
    }

    private func removeScreenObserver() {
        guard let screenObserver else { return }
        NotificationCenter.default.removeObserver(screenObserver)
        self.screenObserver = nil
    }

    private func syncWindowsToCurrentScreens() {
        let screens = NSScreen.screens
        let activeIDs = Set(screens.compactMap(\.pd_displayID))

        for (displayID, window) in windowsByDisplayID where !activeIDs.contains(displayID) {
            window.orderOut(nil)
            windowsByDisplayID.removeValue(forKey: displayID)
            viewsByDisplayID.removeValue(forKey: displayID)
        }

        for screen in screens {
            guard let displayID = screen.pd_displayID else { continue }

            if let existingWindow = windowsByDisplayID[displayID] {
                if existingWindow.frame != screen.frame {
                    existingWindow.setFrame(screen.frame, display: true)
                }
                continue
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

            let view = LiveWallpaperRendererView(frame: screen.frame)
            window.contentView = view
            window.orderBack(nil)

            windowsByDisplayID[displayID] = window
            viewsByDisplayID[displayID] = view
        }
    }

    private func applyCurrentState() {
        guard let contentState else { return }
        for view in viewsByDisplayID.values {
            view.render(
                image: contentState.image,
                palette: contentState.palette,
                animateGradient: contentState.animateGradient,
                motionEffect: contentState.motionEffect
            )
        }
    }

    private func orderWindowsVisible() {
        for window in windowsByDisplayID.values {
            window.orderFrontRegardless()
        }
    }
}

private extension NSScreen {
    var pd_displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
