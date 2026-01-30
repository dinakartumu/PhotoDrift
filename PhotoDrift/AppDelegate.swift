import AppKit
import SwiftData

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var shuffleEngine: ShuffleEngine!
    private var modelContainer: ModelContainer!
    private var settingsWC: SettingsWindowController?
    private var albumPickerWC: AlbumPickerWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let schema = Schema([Album.self, Asset.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        shuffleEngine = ShuffleEngine(modelContainer: modelContainer)
        loadSavedTokens()
        autoStartIfNeeded()
        observeWake()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(engineStateChanged),
            name: .shuffleEngineStateChanged,
            object: shuffleEngine
        )
    }

    // MARK: - OAuth Callback

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == AdobeConfig.callbackScheme else { continue }
            Task {
                await AdobeAuthManager.shared.handleCallback(url: url)
            }
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "PhotoDrift")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func engineStateChanged() {
        // Status item icon could be updated here if needed
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Header
        let header = NSMenuItem(title: "PhotoDrift", action: nil, keyEquivalent: "")
        header.isEnabled = false
        if shuffleEngine.isRunning {
            let dot = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
                NSColor.systemGreen.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            header.image = dot
        }
        menu.addItem(header)

        // 2. Source
        if let source = shuffleEngine.currentSource {
            let sourceItem = NSMenuItem(title: "Source: \(source)", action: nil, keyEquivalent: "")
            sourceItem.isEnabled = false
            menu.addItem(sourceItem)
        }

        // 3. Next shuffle time
        if let next = shuffleEngine.nextShuffleDate, shuffleEngine.isRunning {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: next, relativeTo: Date())
            let nextItem = NSMenuItem(title: "Next: \(relative)", action: nil, keyEquivalent: "")
            nextItem.isEnabled = false
            menu.addItem(nextItem)
        }

        // 4. Status message
        if let status = shuffleEngine.statusMessage {
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())

        // 5. Album summary
        let (hasAlbums, summary) = albumSummary()
        let albumItem = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
        albumItem.isEnabled = false
        menu.addItem(albumItem)

        menu.addItem(.separator())

        // 6. Shuffle Now
        let shuffleItem = NSMenuItem(title: "Shuffle Now", action: #selector(shuffleNow), keyEquivalent: "")
        shuffleItem.target = self
        shuffleItem.isEnabled = hasAlbums
        menu.addItem(shuffleItem)

        // 7. Pause / Resume
        if shuffleEngine.isRunning {
            let pauseItem = NSMenuItem(title: "Pause", action: #selector(pauseEngine), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)
        } else if hasAlbums {
            let resumeItem = NSMenuItem(title: "Resume", action: #selector(resumeEngine), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
        }

        menu.addItem(.separator())

        // 8. Choose Albums
        let albumsItem = NSMenuItem(title: "Choose Albums...", action: #selector(showAlbumPicker), keyEquivalent: "")
        albumsItem.target = self
        menu.addItem(albumsItem)

        // 9. Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        #if DEBUG
        menu.addItem(.separator())
        let testItem = NSMenuItem(title: "Set Test Wallpaper", action: #selector(setTestWallpaper), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)
        #endif

        menu.addItem(.separator())

        // 10. Quit
        let quitItem = NSMenuItem(title: "Quit PhotoDrift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

    @objc private func shuffleNow() {
        Task { await shuffleEngine.shuffleNow() }
    }

    @objc private func pauseEngine() {
        shuffleEngine.stop()
    }

    @objc private func resumeEngine() {
        shuffleEngine.start()
    }

    @objc private func showSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController(modelContainer: modelContainer)
        }
        settingsWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAlbumPicker() {
        if albumPickerWC == nil {
            albumPickerWC = AlbumPickerWindowController(modelContainer: modelContainer)
        }
        albumPickerWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG
    @objc private func setTestWallpaper() {
        Task {
            do {
                let size = ScreenUtility.targetSize
                let image = NSImage(size: NSSize(width: size.width, height: size.height))
                image.lockFocus()
                NSColor.systemTeal.setFill()
                NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
                let text = "PhotoDrift Test" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 72, weight: .bold),
                    .foregroundColor: NSColor.white,
                ]
                let textSize = text.size(withAttributes: attrs)
                text.draw(
                    at: NSPoint(
                        x: (image.size.width - textSize.width) / 2,
                        y: (image.size.height - textSize.height) / 2
                    ),
                    withAttributes: attrs
                )
                image.unlockFocus()

                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                else { return }

                let url = try await ImageCacheManager.shared.store(data: jpegData, forKey: "test_wallpaper.jpg")
                try WallpaperService.setWallpaper(from: url)
            } catch {
                // Debug only
            }
        }
    }
    #endif

    // MARK: - Helpers

    private func albumSummary() -> (hasAlbums: Bool, summary: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isSelected == true }
        )
        guard let albums = try? context.fetch(descriptor), !albums.isEmpty else {
            return (false, "No albums selected")
        }
        let photosCount = albums.filter { $0.sourceType == .applePhotos }.count
        let lrCount = albums.filter { $0.sourceType == .lightroomCloud }.count
        let parts = [
            photosCount > 0 ? "\(photosCount) Photos" : nil,
            lrCount > 0 ? "\(lrCount) Lightroom" : nil,
        ].compactMap { $0 }
        return (true, parts.joined(separator: ", "))
    }

    private func loadSavedTokens() {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        Task {
            await AdobeAuthManager.shared.configure(modelContainer: modelContainer)
            await AdobeAuthManager.shared.loadTokens(from: settings)
        }
    }

    private func autoStartIfNeeded() {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isSelected == true }
        )
        if let albums = try? context.fetch(descriptor), !albums.isEmpty {
            shuffleEngine.start()
        }
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.shuffleEngine.handleWake()
        }
    }
}
