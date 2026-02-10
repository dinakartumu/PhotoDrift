import AppKit
import SwiftData
import Photos

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var shuffleEngine: ShuffleEngine!
    private var modelContainer: ModelContainer!
    private var settingsWC: SettingsWindowController?
    private var lightroomSignedIn = false

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
        observeWake()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(engineStateChanged),
            name: .shuffleEngineStateChanged,
            object: shuffleEngine
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lightroomAuthChanged),
            name: .lightroomAuthStateChanged,
            object: nil
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

    @objc private func lightroomAuthChanged() {
        Task {
            let signedIn = await AdobeAuthManager.shared.isSignedIn
            await MainActor.run {
                lightroomSignedIn = signedIn
                shuffleEngine.handleLightroomAuthStateChanged(signedIn: signedIn)
            }
        }
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
        if let status = shuffleEngine.statusMessage,
           !(status == "Lightroom: please sign in again" && lightroomSignedIn) {
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())

        // 5. Album summary
        let (_, hasEnabledSelectedAlbums, _, summary) = albumSummary()
        let albumItem = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
        albumItem.isEnabled = false
        menu.addItem(albumItem)

        menu.addItem(.separator())

        // 6. Shuffle Now
        let shuffleItem = NSMenuItem(title: "Shuffle Now", action: #selector(shuffleNow), keyEquivalent: "")
        shuffleItem.target = self
        shuffleItem.isEnabled = hasEnabledSelectedAlbums
        menu.addItem(shuffleItem)

        // 7. Pause / Resume
        if shuffleEngine.isRunning {
            let pauseItem = NSMenuItem(title: "Pause", action: #selector(pauseEngine), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)
        } else if hasEnabledSelectedAlbums {
            let resumeItem = NSMenuItem(title: "Resume", action: #selector(resumeEngine), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
        }

        menu.addItem(.separator())

        // 8. Display submenu
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displaySubmenu = NSMenu()
        buildDisplaySubmenu(displaySubmenu)
        displayItem.submenu = displaySubmenu
        menu.addItem(displayItem)

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
            settingsWC = SettingsWindowController(
                modelContainer: modelContainer,
                shuffleEngine: shuffleEngine
            )
        }
        settingsWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func connectApplePhotos() {
        Task {
            let status = await PhotoKitConnector.shared.requestAuthorization()

            if status == .denied || status == .restricted {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Photos Access Required"
                    alert.informativeText = "PhotoDrift needs access to your Photos library. Please enable it in System Settings > Privacy & Security > Photos."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open System Settings")
                    alert.addButton(withTitle: "Cancel")
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                    }
                }
                return
            }

            guard status == .authorized || status == .limited else { return }

            let infos = await PhotoKitConnector.shared.fetchAlbums()
            await MainActor.run {
                let context = ModelContext(modelContainer)
                let settings = AppSettings.current(in: context)
                settings.photosEnabled = true

                let descriptor = FetchDescriptor<Album>(
                    predicate: #Predicate { $0.sourceTypeRaw == "applePhotos" }
                )
                let existing = (try? context.fetch(descriptor)) ?? []
                let fetchedIDs = Set(infos.map(\.id))

                for album in existing where !fetchedIDs.contains(album.id) {
                    context.delete(album)
                }
                for info in infos {
                    if let match = existing.first(where: { $0.id == info.id }) {
                        match.name = info.name
                        match.assetCount = info.assetCount
                    } else {
                        let album = Album(id: info.id, name: info.name, sourceType: .applePhotos, assetCount: info.assetCount)
                        context.insert(album)
                    }
                }

                try? context.save()
            }
        }
    }

    // MARK: - Display Submenu

    private func buildDisplaySubmenu(_ menu: NSMenu) {
        let context = ModelContext(modelContainer)
        let current = AppSettings.current(in: context).wallpaperScaling

        for scaling in WallpaperScaling.allCases {
            let item = NSMenuItem(title: scaling.displayName, action: #selector(scalingSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scaling.rawValue
            item.state = scaling == current ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func scalingSelected(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let scaling = WallpaperScaling(rawValue: rawValue) else { return }
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        settings.wallpaperScaling = scaling
        try? context.save()
    }

    // MARK: - Album Submenus

    private func buildAlbumSubmenus(_ menu: NSMenu) {
        // Apple Photos submenu
        let photosItem = NSMenuItem(title: "Apple Photos", action: nil, keyEquivalent: "")
        let photosSubmenu = NSMenu()
        buildPhotosAlbumSubmenu(photosSubmenu)
        photosItem.submenu = photosSubmenu
        menu.addItem(photosItem)

        // Lightroom submenu
        let lrItem = NSMenuItem(title: "Lightroom", action: nil, keyEquivalent: "")
        let lrSubmenu = NSMenu()
        buildLightroomAlbumSubmenu(lrSubmenu)
        lrItem.submenu = lrSubmenu
        menu.addItem(lrItem)
    }

    private func buildPhotosAlbumSubmenu(_ menu: NSMenu) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<Album>(
                predicate: #Predicate { $0.sourceTypeRaw == "applePhotos" },
                sortBy: [SortDescriptor(\Album.name)]
            )
            guard let albums = try? context.fetch(descriptor), !albums.isEmpty else {
                let empty = NSMenuItem(title: "No albums found", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
                return
            }
            let allSelected = albums.allSatisfy(\.isSelected)
            let noneSelected = !albums.contains(where: \.isSelected)
            let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAllAlbums(_:)), keyEquivalent: "")
            selectAll.target = self
            selectAll.representedObject = SourceType.applePhotos.rawValue
            selectAll.isEnabled = !allSelected
            menu.addItem(selectAll)
            let deselectAll = NSMenuItem(title: "Deselect All", action: #selector(deselectAllAlbums(_:)), keyEquivalent: "")
            deselectAll.target = self
            deselectAll.representedObject = SourceType.applePhotos.rawValue
            deselectAll.isEnabled = !noneSelected
            menu.addItem(deselectAll)
            menu.addItem(.separator())
            for album in albums {
                menu.addItem(makeAlbumCheckboxItem(title: album.name, albumID: album.id, isSelected: album.isSelected))
            }
        default:
            let connect = NSMenuItem(title: "Connect Apple Photos…", action: #selector(connectApplePhotos), keyEquivalent: "")
            connect.target = self
            menu.addItem(connect)
        }
    }

    private func buildLightroomAlbumSubmenu(_ menu: NSMenu) {
        guard lightroomSignedIn else {
            let item = NSMenuItem(title: "Sign In in Settings", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.sourceTypeRaw == "lightroomCloud" },
            sortBy: [SortDescriptor(\Album.name)]
        )
        guard let albums = try? context.fetch(descriptor), !albums.isEmpty else {
            let empty = NSMenuItem(title: "No albums found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let allSelected = albums.allSatisfy(\.isSelected)
        let noneSelected = !albums.contains(where: \.isSelected)
        let selectAll = NSMenuItem(title: "Select All", action: #selector(selectAllAlbums(_:)), keyEquivalent: "")
        selectAll.target = self
        selectAll.representedObject = SourceType.lightroomCloud.rawValue
        selectAll.isEnabled = !allSelected
        menu.addItem(selectAll)
        let deselectAll = NSMenuItem(title: "Deselect All", action: #selector(deselectAllAlbums(_:)), keyEquivalent: "")
        deselectAll.target = self
        deselectAll.representedObject = SourceType.lightroomCloud.rawValue
        deselectAll.isEnabled = !noneSelected
        menu.addItem(deselectAll)
        menu.addItem(.separator())
        for album in albums {
            menu.addItem(makeAlbumCheckboxItem(title: album.name, albumID: album.id, isSelected: album.isSelected))
        }
    }

    private func makeAlbumCheckboxItem(title: String, albumID: String, isSelected: Bool) -> NSMenuItem {
        let item = NSMenuItem()
        let view = CheckmarkMenuItemView(title: title, albumID: albumID, isChecked: isSelected)
        view.onToggle = { [weak self] albumID, isSelected in
            self?.handleAlbumToggle(albumID: albumID, isSelected: isSelected)
        }
        item.view = view
        return item
    }

    private func handleAlbumToggle(albumID: String, isSelected: Bool) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.id == albumID }
        )
        guard let album = try? context.fetch(descriptor).first else { return }
        album.isSelected = isSelected
        if !isSelected {
            let assetIDs = album.assets.map(\.id)
            for asset in album.assets {
                context.delete(asset)
            }
            Task {
                for id in assetIDs {
                    await ImageCacheManager.shared.remove(forKey: ImageCacheManager.cacheKey(for: id))
                }
            }
        }
        try? context.save()
        if isSelected {
            Task {
                await self.shuffleEngine.syncAssets(forAlbumID: albumID)
            }
        }
    }

    @objc private func selectAllAlbums(_ sender: NSMenuItem) {
        guard let sourceRaw = sender.representedObject as? String else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.sourceTypeRaw == sourceRaw && !$0.isSelected }
        )
        guard let albums = try? context.fetch(descriptor), !albums.isEmpty else { return }
        let albumIDs = albums.map(\.id)
        for album in albums {
            album.isSelected = true
        }
        try? context.save()
        Task {
            for id in albumIDs {
                await self.shuffleEngine.syncAssets(forAlbumID: id)
            }
        }
    }

    @objc private func deselectAllAlbums(_ sender: NSMenuItem) {
        guard let sourceRaw = sender.representedObject as? String else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.sourceTypeRaw == sourceRaw && $0.isSelected }
        )
        guard let albums = try? context.fetch(descriptor), !albums.isEmpty else { return }
        var assetIDs: [String] = []
        for album in albums {
            album.isSelected = false
            for asset in album.assets {
                assetIDs.append(asset.id)
                context.delete(asset)
            }
        }
        try? context.save()
        Task {
            for id in assetIDs {
                await ImageCacheManager.shared.remove(forKey: ImageCacheManager.cacheKey(for: id))
            }
        }
    }

    @objc private func albumToggled(_ sender: NSMenuItem) {
        guard let albumID = sender.representedObject as? String else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.id == albumID }
        )
        guard let album = try? context.fetch(descriptor).first else { return }
        album.isSelected.toggle()
        let nowSelected = album.isSelected

        if !nowSelected {
            for asset in album.assets {
                context.delete(asset)
            }
        }

        try? context.save()
        sender.state = nowSelected ? .on : .off

        if nowSelected {
            Task {
                await self.shuffleEngine.syncAssets(forAlbumID: albumID)
            }
        }
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
                let context = ModelContext(modelContainer)
                let scaling = AppSettings.current(in: context).wallpaperScaling
                try WallpaperService.setWallpaper(from: url, scaling: scaling)
            } catch {
                // Debug only
            }
        }
    }
    #endif

    // MARK: - Helpers

    private func albumSummary() -> (
        hasSelectedAlbums: Bool,
        hasEnabledSelectedAlbums: Bool,
        hasSyncedAssets: Bool,
        summary: String
    ) {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isSelected == true }
        )
        guard let albums = try? context.fetch(descriptor), !albums.isEmpty else {
            return (false, false, false, "No albums selected")
        }

        let enabledAlbums = albums.filter { album in
            switch album.sourceType {
            case .applePhotos: settings.photosEnabled
            case .lightroomCloud: settings.lightroomEnabled
            }
        }

        if enabledAlbums.isEmpty {
            return (true, false, false, "Selected albums are disabled in Sources")
        }

        let photosCount = albums.filter { $0.sourceType == .applePhotos }.count
        let lrCount = albums.filter { $0.sourceType == .lightroomCloud }.count
        let syncedAssetCount = enabledAlbums.reduce(0) { $0 + $1.assets.count }
        let parts = [
            photosCount > 0 ? "\(photosCount) Photos albums" : nil,
            lrCount > 0 ? "\(lrCount) Lightroom albums" : nil,
        ].compactMap { $0 }
        let summary = "\(parts.joined(separator: ", ")) • \(syncedAssetCount) synced photos"
        return (true, true, syncedAssetCount > 0, summary)
    }

    private func loadSavedTokens() {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        let accessToken = settings.adobeAccessToken
        let refreshToken = settings.adobeRefreshToken
        let tokenExpiry = settings.adobeTokenExpiry
        lightroomSignedIn = refreshToken != nil || (accessToken != nil && tokenExpiry.map { Date() < $0 } == true)
        Task {
            await AdobeAuthManager.shared.configure(modelContainer: modelContainer)
            await AdobeAuthManager.shared.loadTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenExpiry: tokenExpiry
            )
            let signedIn = await AdobeAuthManager.shared.isSignedIn
            await MainActor.run {
                self.lightroomSignedIn = signedIn
            }
            autoStartIfNeeded()
        }
    }

    private func autoStartIfNeeded() {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isSelected == true }
        )
        if let albums = try? context.fetch(descriptor), !albums.isEmpty {
            let enabledAlbumIDs = albums.compactMap { album -> String? in
                switch album.sourceType {
                case .applePhotos:
                    return settings.photosEnabled ? album.id : nil
                case .lightroomCloud:
                    return settings.lightroomEnabled ? album.id : nil
                }
            }
            guard !enabledAlbumIDs.isEmpty else { return }

            shuffleEngine.start()
            Task {
                for albumID in enabledAlbumIDs {
                    await self.shuffleEngine.syncAssets(forAlbumID: albumID)
                }
                await self.shuffleEngine.shuffleNow()
            }
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

// MARK: - Checkmark Menu Item View

private class CheckmarkMenuItemView: NSView {
    let albumID: String
    private(set) var isChecked: Bool
    var onToggle: ((String, Bool) -> Void)?
    private let checkLabel: NSTextField
    private let titleLabel: NSTextField
    private var trackingArea: NSTrackingArea?

    init(title: String, albumID: String, isChecked: Bool) {
        self.albumID = albumID
        self.isChecked = isChecked

        let font = NSFont.menuFont(ofSize: 0)
        checkLabel = NSTextField(labelWithString: "✓")
        checkLabel.font = font
        checkLabel.isHidden = !isChecked

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = font

        super.init(frame: .zero)
        wantsLayer = true

        addSubview(checkLabel)
        addSubview(titleLabel)

        let height: CGFloat = 22
        checkLabel.sizeToFit()
        titleLabel.sizeToFit()
        checkLabel.frame.origin = NSPoint(x: 6, y: (height - checkLabel.frame.height) / 2)
        titleLabel.frame.origin = NSPoint(x: 24, y: (height - titleLabel.frame.height) / 2)
        frame = NSRect(x: 0, y: 0, width: titleLabel.frame.maxX + 14, height: height)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        titleLabel.textColor = .white
        checkLabel.textColor = .white
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        titleLabel.textColor = .labelColor
        checkLabel.textColor = .labelColor
    }

    override func mouseUp(with event: NSEvent) {
        isChecked.toggle()
        checkLabel.isHidden = !isChecked
        onToggle?(albumID, isChecked)
    }
}
