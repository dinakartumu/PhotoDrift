import AppKit
import SwiftData
import ServiceManagement
import Photos

final class SettingsWindowController: NSWindowController {
    convenience init(modelContainer: ModelContainer, shuffleEngine: ShuffleEngine) {
        let vc = SettingsTabViewController(modelContainer: modelContainer, shuffleEngine: shuffleEngine)
        let window = NSWindow(contentViewController: vc)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(GeneralSettingsViewController.preferredContentSize)
        window.center()
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .preference
        }
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        (contentViewController as? SettingsTabViewController)?.refreshAll()
        window?.center()
    }
}

final class SettingsTabViewController: NSTabViewController {
    private let generalViewController: GeneralSettingsViewController
    private let sourceViewController: SourceSettingsViewController
    private let albumsViewController: AlbumsSettingsViewController

    init(modelContainer: ModelContainer, shuffleEngine: ShuffleEngine) {
        generalViewController = GeneralSettingsViewController(modelContainer: modelContainer)
        sourceViewController = SourceSettingsViewController(modelContainer: modelContainer)
        albumsViewController = AlbumsSettingsViewController(
            modelContainer: modelContainer,
            shuffleEngine: shuffleEngine
        )
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        setupTabs()

        sourceViewController.onAlbumsUpdated = { [weak self] in
            self?.albumsViewController.reloadAlbums()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        syncWindowTitle()
        applyWindowSize(for: tabView.selectedTabViewItem?.viewController, animated: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyWindowSize(for: tabView.selectedTabViewItem?.viewController, animated: false)
    }

    func refreshAll() {
        // Ensure tab views are created before touching any controls.
        _ = view
        _ = generalViewController.view
        _ = sourceViewController.view
        _ = albumsViewController.view

        generalViewController.refreshState()
        sourceViewController.refreshConnectionStatus()
        albumsViewController.reloadAlbums()
        syncWindowTitle()
        applyWindowSize(for: tabView.selectedTabViewItem?.viewController, animated: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        syncWindowTitle()
        applyWindowSize(for: tabViewItem?.viewController)
    }

    private func setupTabs() {
        addTab(
            label: "General",
            systemImageName: "gearshape",
            fallbackImageName: NSImage.preferencesGeneralName,
            viewController: generalViewController
        )
        addTab(
            label: "Sources",
            systemImageName: "link",
            fallbackImageName: NSImage.networkName,
            viewController: sourceViewController
        )
        addTab(
            label: "Albums",
            systemImageName: "photo.on.rectangle.angled",
            fallbackImageName: NSImage.multipleDocumentsName,
            viewController: albumsViewController
        )
    }

    private func syncWindowTitle() {
        let current = tabView.selectedTabViewItem?.label ?? "Settings"
        title = current
        view.window?.title = current
    }

    private func applyWindowSize(for viewController: NSViewController?, animated: Bool = true) {
        guard let window = view.window else { return }
        let size: NSSize
        switch viewController {
        case is GeneralSettingsViewController:
            size = GeneralSettingsViewController.preferredContentSize
        case is SourceSettingsViewController:
            size = SourceSettingsViewController.preferredContentSize
        case is AlbumsSettingsViewController:
            size = AlbumsSettingsViewController.preferredContentSize
        default:
            size = GeneralSettingsViewController.preferredContentSize
        }
        let currentSize = window.contentRect(forFrameRect: window.frame).size
        guard currentSize != size else { return }

        guard animated, window.isVisible else {
            window.setContentSize(size)
            return
        }

        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - targetFrame.height
        frame.size = targetFrame.size
        window.setFrame(frame, display: true, animate: true)
    }

    private func addTab(
        label: String,
        systemImageName: String,
        fallbackImageName: NSImage.Name,
        viewController: NSViewController
    ) {
        viewController.title = label
        let item = NSTabViewItem(viewController: viewController)
        item.label = label
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: label)
        } else {
            item.image = NSImage(named: fallbackImageName)
        }
        addTabViewItem(item)
    }
}

final class GeneralSettingsViewController: NSViewController {
    static let preferredContentSize = NSSize(width: 500, height: 370)
    private let context: ModelContext
    private var settings: AppSettings!

    private let intervals: [(label: String, minutes: Int)] = [
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
    ]

    private var radioButtons: [NSButton] = []
    private var launchAtLoginCheckbox: NSButton!
    private var scalingPopup: NSPopUpButton!
    private var applyAllDesktopsCheckbox: NSButton!
    private var liveDesktopLayerCheckbox: NSButton!
    private var motionEffectPopup: NSPopUpButton!

    init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        settings = AppSettings.current(in: context)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false

        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch at Login",
            target: self,
            action: #selector(launchAtLoginToggled(_:))
        )

        let radioStack = NSStackView()
        radioStack.orientation = .vertical
        radioStack.alignment = .leading
        radioStack.spacing = 6
        for interval in intervals {
            let radio = NSButton(
                radioButtonWithTitle: interval.label,
                target: self,
                action: #selector(intervalChanged(_:))
            )
            radio.tag = interval.minutes
            radioButtons.append(radio)
            radioStack.addArrangedSubview(radio)
        }

        scalingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        scalingPopup.target = self
        scalingPopup.action = #selector(scalingChanged(_:))
        scalingPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scalingPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scalingPopup.translatesAutoresizingMaskIntoConstraints = false
        scalingPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        for scaling in WallpaperScaling.allCases {
            scalingPopup.addItem(withTitle: scaling.displayName)
            scalingPopup.lastItem?.representedObject = scaling.rawValue
        }
        applyAllDesktopsCheckbox = NSButton(
            checkboxWithTitle: "Update all desktops (all Spaces)",
            target: self,
            action: #selector(applyAllDesktopsToggled(_:))
        )
        liveDesktopLayerCheckbox = NSButton(
            checkboxWithTitle: "Use live desktop layer (experimental)",
            target: self,
            action: #selector(liveDesktopLayerToggled(_:))
        )
        motionEffectPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        motionEffectPopup.target = self
        motionEffectPopup.action = #selector(motionEffectChanged(_:))
        motionEffectPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        motionEffectPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        motionEffectPopup.translatesAutoresizingMaskIntoConstraints = false
        motionEffectPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        for effect in LiveGradientMotionEffect.allCases {
            motionEffectPopup.addItem(withTitle: effect.displayName)
            motionEffectPopup.lastItem?.representedObject = effect.rawValue
        }
        let startupGrid = makeFormGrid(rows: [("Startup:", launchAtLoginCheckbox)])
        let shuffleGrid = makeFormGrid(rows: [("Shuffle Interval:", radioStack)])
        let wallpaperGrid = makeFormGrid(
            rows: [
                ("Scaling:", scalingPopup),
                ("Target:", applyAllDesktopsCheckbox),
                ("Rendering:", liveDesktopLayerCheckbox),
                ("Animation effect:", motionEffectPopup),
            ],
            fillControlColumn: true
        )

        root.addArrangedSubview(startupGrid)
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(shuffleGrid)
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(wallpaperGrid)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
            root.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
            root.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
        ])

        self.view = container
        refreshState()
    }

    func refreshState() {
        guard isViewLoaded else { return }
        let isLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginCheckbox?.state = isLoginEnabled ? .on : .off

        for radio in radioButtons {
            radio.state = (radio.tag == settings.shuffleIntervalMinutes) ? .on : .off
        }

        if let item = scalingPopup.itemArray.first(where: {
            ($0.representedObject as? String) == settings.wallpaperScaling.rawValue
        }) {
            scalingPopup.select(item)
        }

        applyAllDesktopsCheckbox.state = settings.applyToAllDesktops ? .on : .off
        liveDesktopLayerCheckbox.state = settings.useLiveDesktopLayer ? .on : .off
        motionEffectPopup.isEnabled = settings.useLiveDesktopLayer
        if let item = motionEffectPopup.itemArray.first(where: {
            ($0.representedObject as? String) == settings.liveGradientMotionEffect.rawValue
        }) {
            motionEffectPopup.select(item)
        }
    }

    @objc private func intervalChanged(_ sender: NSButton) {
        for radio in radioButtons {
            radio.state = (radio === sender) ? .on : .off
        }
        settings.shuffleIntervalMinutes = sender.tag
        save()
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enable = sender.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func scalingChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let scaling = WallpaperScaling(rawValue: rawValue) else { return }
        settings.wallpaperScaling = scaling
        save()
    }

    @objc private func applyAllDesktopsToggled(_ sender: NSButton) {
        settings.applyToAllDesktops = sender.state == .on
        save()
    }

    @objc private func liveDesktopLayerToggled(_ sender: NSButton) {
        settings.useLiveDesktopLayer = sender.state == .on
        motionEffectPopup.isEnabled = settings.useLiveDesktopLayer
        save()
    }

    @objc private func motionEffectChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let effect = LiveGradientMotionEffect(rawValue: rawValue) else { return }
        settings.liveGradientMotionEffect = effect
        if settings.useLiveDesktopLayer {
            LiveDesktopLayerService.shared.updateMotionEffect(effect)
        }
        save()
    }

    private func save() {
        try? context.save()
    }
}

final class SourceSettingsViewController: NSViewController {
    static let preferredContentSize = NSSize(width: 500, height: 300)
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private var settings: AppSettings!

    var onAlbumsUpdated: (() -> Void)?

    private var photosCheckbox: NSButton!
    private var lightroomCheckbox: NSButton!

    private var photosStatusLabel: NSTextField!
    private var photosGrantButton: NSButton!
    private var photosRefreshButton: NSButton!

    private var lightroomStatusLabel: NSTextField!
    private var lightroomSignInButton: NSButton!
    private var lightroomSignOutButton: NSButton!
    private var lightroomRefreshButton: NSButton!

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        settings = AppSettings.current(in: context)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false

        photosCheckbox = NSButton(
            checkboxWithTitle: "Use Apple Photos",
            target: self,
            action: #selector(photosToggled(_:))
        )

        let photosRow = NSStackView()
        photosRow.orientation = .horizontal
        photosRow.spacing = 8
        photosRow.alignment = .centerY

        photosStatusLabel = NSTextField(labelWithString: "")
        photosStatusLabel.textColor = .secondaryLabelColor
        photosRow.addArrangedSubview(photosStatusLabel)

        photosGrantButton = NSButton(title: "Grant Access", target: self, action: #selector(grantPhotosAccess))
        photosGrantButton.bezelStyle = .rounded
        photosGrantButton.controlSize = .small
        photosRow.addArrangedSubview(photosGrantButton)

        photosRefreshButton = NSButton(title: "Refresh Albums", target: self, action: #selector(refreshPhotosAlbums))
        photosRefreshButton.bezelStyle = .rounded
        photosRefreshButton.controlSize = .small
        photosRow.addArrangedSubview(photosRefreshButton)
        let photosGroup = NSStackView()
        photosGroup.orientation = .vertical
        photosGroup.alignment = .leading
        photosGroup.spacing = 6
        photosGroup.addArrangedSubview(photosCheckbox)
        photosGroup.addArrangedSubview(photosRow)

        lightroomCheckbox = NSButton(
            checkboxWithTitle: "Use Adobe Lightroom",
            target: self,
            action: #selector(lightroomToggled(_:))
        )

        let lrRow = NSStackView()
        lrRow.orientation = .horizontal
        lrRow.spacing = 8
        lrRow.alignment = .centerY

        lightroomStatusLabel = NSTextField(labelWithString: "")
        lightroomStatusLabel.textColor = .secondaryLabelColor
        lrRow.addArrangedSubview(lightroomStatusLabel)

        lightroomSignInButton = NSButton(title: "Sign In", target: self, action: #selector(signInToLightroom))
        lightroomSignInButton.bezelStyle = .rounded
        lightroomSignInButton.controlSize = .small
        lrRow.addArrangedSubview(lightroomSignInButton)

        lightroomSignOutButton = NSButton(title: "Sign Out", target: self, action: #selector(signOutOfLightroom))
        lightroomSignOutButton.bezelStyle = .rounded
        lightroomSignOutButton.controlSize = .small
        lrRow.addArrangedSubview(lightroomSignOutButton)

        lightroomRefreshButton = NSButton(title: "Refresh Albums", target: self, action: #selector(refreshLightroomAlbums))
        lightroomRefreshButton.bezelStyle = .rounded
        lightroomRefreshButton.controlSize = .small
        lrRow.addArrangedSubview(lightroomRefreshButton)
        let lightroomGroup = NSStackView()
        lightroomGroup.orientation = .vertical
        lightroomGroup.alignment = .leading
        lightroomGroup.spacing = 6
        lightroomGroup.addArrangedSubview(lightroomCheckbox)
        lightroomGroup.addArrangedSubview(lrRow)

        let photosGrid = makeFormGrid(rows: [("Apple Photos:", photosGroup)])
        let lightroomGrid = makeFormGrid(rows: [("Adobe Lightroom:", lightroomGroup)])

        root.addArrangedSubview(photosGrid)
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(lightroomGrid)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let documentView = FlippedContentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        documentView.addSubview(root)

        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            root.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -32),
            root.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            documentView.bottomAnchor.constraint(greaterThanOrEqualTo: root.bottomAnchor, constant: 24),
        ])

        self.view = scrollView
        refreshConnectionStatus()
    }

    func refreshConnectionStatus() {
        guard isViewLoaded else { return }
        photosCheckbox.state = settings.photosEnabled ? .on : .off
        lightroomCheckbox.state = settings.lightroomEnabled ? .on : .off
        updatePhotosStatus()
        Task {
            let signedIn = await AdobeAuthManager.shared.isSignedIn
            await MainActor.run {
                self.applyLightroomUI(signedIn: signedIn)
            }
        }
    }

    @objc private func photosToggled(_ sender: NSButton) {
        settings.photosEnabled = sender.state == .on
        save()
        if settings.photosEnabled {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .authorized || status == .limited {
                syncPhotosAlbums()
            }
        }
    }

    @objc private func lightroomToggled(_ sender: NSButton) {
        settings.lightroomEnabled = sender.state == .on
        save()
        if settings.lightroomEnabled {
            Task {
                let signedIn = await AdobeAuthManager.shared.isSignedIn
                if signedIn {
                    await MainActor.run {
                        self.syncLightroomAlbums()
                    }
                }
            }
        }
    }

    @objc private func refreshPhotosAlbums() {
        syncPhotosAlbums()
    }

    @objc private func refreshLightroomAlbums() {
        syncLightroomAlbums()
    }

    @objc private func grantPhotosAccess() {
        photosGrantButton.isEnabled = false
        Task {
            let status = await PhotoKitConnector.shared.requestAuthorization()
            await MainActor.run {
                self.photosGrantButton.isEnabled = true
                self.updatePhotosStatus()
                if status == .authorized || status == .limited {
                    self.syncPhotosAlbums()
                } else if status == .denied || status == .restricted {
                    self.showPhotosDeniedAlert()
                }
            }
        }
    }

    @objc private func signInToLightroom() {
        guard let window = view.window else { return }
        lightroomSignInButton.isEnabled = false

        Task {
            do {
                _ = try await AdobeAuthManager.shared.signIn(from: window)
                await MainActor.run {
                    self.lightroomSignInButton.isEnabled = true
                    self.applyLightroomUI(signedIn: true)
                    NotificationCenter.default.post(name: .lightroomAuthStateChanged, object: nil)
                    self.syncLightroomAlbums()
                }
            } catch {
                await MainActor.run {
                    self.lightroomSignInButton.isEnabled = true
                    self.showErrorAlert(
                        title: "Lightroom Sign In Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    @objc private func signOutOfLightroom() {
        Task {
            await AdobeAuthManager.shared.signOut()
            await MainActor.run {
                let context = ModelContext(self.modelContainer)
                let currentSettings = AppSettings.current(in: context)
                currentSettings.adobeAccessToken = nil
                currentSettings.adobeRefreshToken = nil
                currentSettings.adobeTokenExpiry = nil
                currentSettings.lightroomEnabled = false

                let descriptor = FetchDescriptor<Album>(
                    predicate: #Predicate { $0.sourceTypeRaw == "lightroomCloud" }
                )
                if let albums = try? context.fetch(descriptor) {
                    for album in albums {
                        context.delete(album)
                    }
                }
                try? context.save()

                self.settings = currentSettings
                self.lightroomCheckbox.state = .off
                self.applyLightroomUI(signedIn: false)
                NotificationCenter.default.post(name: .lightroomAuthStateChanged, object: nil)
                self.onAlbumsUpdated?()
            }
        }
    }

    private func updatePhotosStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photosGrantButton.isHidden = true
        photosRefreshButton.isHidden = true

        switch status {
        case .authorized, .limited:
            photosStatusLabel.stringValue = "Connected"
            photosStatusLabel.textColor = .systemGreen
            photosRefreshButton.isHidden = false
        default:
            photosStatusLabel.stringValue = "Not connected"
            photosStatusLabel.textColor = .secondaryLabelColor
            photosGrantButton.isHidden = false
        }
    }

    private func applyLightroomUI(signedIn: Bool) {
        if signedIn {
            lightroomStatusLabel.stringValue = "Connected"
            lightroomStatusLabel.textColor = .systemGreen
            lightroomSignInButton.isHidden = true
            lightroomSignOutButton.isHidden = false
            lightroomRefreshButton.isHidden = false
        } else {
            lightroomStatusLabel.stringValue = "Not connected"
            lightroomStatusLabel.textColor = .secondaryLabelColor
            lightroomSignInButton.isHidden = false
            lightroomSignOutButton.isHidden = true
            lightroomRefreshButton.isHidden = true
        }
    }

    private func syncPhotosAlbums() {
        Task {
            let infos = await PhotoKitConnector.shared.fetchAlbums()
            await MainActor.run {
                let context = ModelContext(self.modelContainer)
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
                        let album = Album(
                            id: info.id,
                            name: info.name,
                            sourceType: .applePhotos,
                            assetCount: info.assetCount
                        )
                        context.insert(album)
                    }
                }

                try? context.save()
                let selectedDescriptor = FetchDescriptor<Album>(
                    predicate: #Predicate { $0.sourceTypeRaw == "applePhotos" && $0.isSelected }
                )
                let selectedAlbumIDs = ((try? context.fetch(selectedDescriptor)) ?? []).map(\.id)

                Task {
                    let pool = UnifiedPool(modelContainer: self.modelContainer)
                    for albumID in selectedAlbumIDs {
                        _ = await pool.syncAssets(forAlbumID: albumID)
                    }
                    await MainActor.run {
                        self.onAlbumsUpdated?()
                    }
                }
            }
        }
    }

    private func syncLightroomAlbums() {
        Task {
            do {
                let infos = try await LightroomConnector.shared.fetchAlbums()
                await MainActor.run {
                    let context = ModelContext(self.modelContainer)
                    let descriptor = FetchDescriptor<Album>(
                        predicate: #Predicate { $0.sourceTypeRaw == "lightroomCloud" }
                    )
                    let existing = (try? context.fetch(descriptor)) ?? []
                    let fetchedIDs = Set(infos.map(\.id))

                    for album in existing where !fetchedIDs.contains(album.id) {
                        context.delete(album)
                    }

                    for info in infos {
                        if let match = existing.first(where: { $0.id == info.id }) {
                            match.name = info.name
                        } else {
                            let album = Album(id: info.id, name: info.name, sourceType: .lightroomCloud)
                            context.insert(album)
                        }
                    }

                    try? context.save()
                    let selectedDescriptor = FetchDescriptor<Album>(
                        predicate: #Predicate { $0.sourceTypeRaw == "lightroomCloud" && $0.isSelected }
                    )
                    let selectedAlbumIDs = ((try? context.fetch(selectedDescriptor)) ?? []).map(\.id)

                    Task {
                        let pool = UnifiedPool(modelContainer: self.modelContainer)
                        for albumID in selectedAlbumIDs {
                            _ = await pool.syncAssets(forAlbumID: albumID)
                        }
                        await MainActor.run {
                            self.onAlbumsUpdated?()
                        }
                    }
                }
            } catch {
                // Keep existing data when refresh fails.
            }
        }
    }

    private func showPhotosDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Photos Access Required"
        alert.informativeText = "PhotoDrift needs access to your Photos library. Please enable it in System Settings > Privacy & Security > Photos."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!
                    )
                }
            }
        }
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func save() {
        try? context.save()
    }
}

final class AlbumsSettingsViewController: NSViewController {
    static let preferredContentSize = NSSize(width: 500, height: 560)
    private let modelContainer: ModelContainer
    private let shuffleEngine: ShuffleEngine

    private var sourceTabs: NSSegmentedControl!
    private var photosSectionContainer: NSView!
    private var lightroomSectionContainer: NSView!
    private var photosListStack: NSStackView!
    private var lightroomListStack: NSStackView!
    private var photosSelectAllButton: NSButton!
    private var photosDeselectAllButton: NSButton!
    private var lightroomSelectAllButton: NSButton!
    private var lightroomDeselectAllButton: NSButton!

    init(modelContainer: ModelContainer, shuffleEngine: ShuffleEngine) {
        self.modelContainer = modelContainer
        self.shuffleEngine = shuffleEngine
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let documentView = FlippedContentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.detachesHiddenViews = true
        content.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(content)

        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: documentView.topAnchor),
            documentView.bottomAnchor.constraint(greaterThanOrEqualTo: content.bottomAnchor),
        ])

        sourceTabs = NSSegmentedControl(
            labels: ["Apple Photos", "Adobe Lightroom"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(sourceTabChanged(_:))
        )
        sourceTabs.selectedSegment = 0
        sourceTabs.setContentHuggingPriority(.required, for: .vertical)
        sourceTabs.setContentCompressionResistancePriority(.required, for: .vertical)

        let tabsRow = NSStackView()
        tabsRow.orientation = .horizontal
        tabsRow.alignment = .centerY
        tabsRow.spacing = 8
        tabsRow.setContentHuggingPriority(.required, for: .vertical)
        tabsRow.setContentCompressionResistancePriority(.required, for: .vertical)

        let leftSpacer = NSView()
        leftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        leftSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tabsRow.addArrangedSubview(leftSpacer)

        tabsRow.addArrangedSubview(sourceTabs)

        let rightSpacer = NSView()
        rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tabsRow.addArrangedSubview(rightSpacer)
        leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor).isActive = true

        content.addArrangedSubview(tabsRow)

        content.addArrangedSubview(makeSeparator())

        let photosSection = makeAlbumsSection(
            title: "Apple Photos",
            selectAllAction: #selector(selectAllPhotosAlbums),
            deselectAllAction: #selector(deselectAllPhotosAlbums)
        )
        photosSectionContainer = photosSection.container
        photosListStack = photosSection.listStack
        photosSelectAllButton = photosSection.selectAllButton
        photosDeselectAllButton = photosSection.deselectAllButton
        content.addArrangedSubview(photosSection.container)

        let lightroomSection = makeAlbumsSection(
            title: "Adobe Lightroom",
            selectAllAction: #selector(selectAllLightroomAlbums),
            deselectAllAction: #selector(deselectAllLightroomAlbums)
        )
        lightroomSectionContainer = lightroomSection.container
        lightroomListStack = lightroomSection.listStack
        lightroomSelectAllButton = lightroomSection.selectAllButton
        lightroomDeselectAllButton = lightroomSection.deselectAllButton
        content.addArrangedSubview(lightroomSection.container)

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        content.addArrangedSubview(bottomSpacer)

        self.view = scrollView
        reloadAlbums()
    }

    func reloadAlbums() {
        guard isViewLoaded else { return }
        let photosAlbums = fetchAlbums(source: .applePhotos)
        let lightroomAlbums = fetchAlbums(source: .lightroomCloud)

        renderAlbums(photosAlbums, in: photosListStack)
        renderAlbums(lightroomAlbums, in: lightroomListStack)

        photosSelectAllButton.isEnabled = photosAlbums.contains(where: { !$0.isSelected })
        photosDeselectAllButton.isEnabled = photosAlbums.contains(where: \.isSelected)
        lightroomSelectAllButton.isEnabled = lightroomAlbums.contains(where: { !$0.isSelected })
        lightroomDeselectAllButton.isEnabled = lightroomAlbums.contains(where: \.isSelected)
        updateSourceSectionVisibility()
    }

    @objc private func sourceTabChanged(_ sender: NSSegmentedControl) {
        updateSourceSectionVisibility()
    }

    @objc private func selectAllPhotosAlbums() {
        selectAllAlbums(for: .applePhotos)
    }

    @objc private func deselectAllPhotosAlbums() {
        deselectAllAlbums(for: .applePhotos)
    }

    @objc private func selectAllLightroomAlbums() {
        selectAllAlbums(for: .lightroomCloud)
    }

    @objc private func deselectAllLightroomAlbums() {
        deselectAllAlbums(for: .lightroomCloud)
    }

    @objc private func albumSelectionChanged(_ sender: NSButton) {
        guard let albumID = sender.identifier?.rawValue else { return }
        let shouldSelect = sender.state == .on
        updateSelectionButtonsFromVisibleCheckboxes()

        Task {
            let changed = await self.shuffleEngine.setAlbumSelection(forAlbumID: albumID, isSelected: shouldSelect)
            guard changed else { return }
            if shouldSelect {
                await self.shuffleEngine.syncAssets(forAlbumID: albumID)
            } else {
                await self.shuffleEngine.clearAssetsIfAlbumDeselected(forAlbumID: albumID)
            }
        }
    }

    private func selectAllAlbums(for source: SourceType) {
        setVisibleSelection(for: source, isSelected: true)
        updateSelectionButtonsFromVisibleCheckboxes()

        Task {
            let albumIDs = await self.shuffleEngine.setAlbumsSelection(for: source, isSelected: true)
            guard !albumIDs.isEmpty else { return }
            for albumID in albumIDs {
                await self.shuffleEngine.syncAssets(forAlbumID: albumID)
            }
            await MainActor.run {
                self.reloadAlbums()
            }
        }
    }

    private func deselectAllAlbums(for source: SourceType) {
        setVisibleSelection(for: source, isSelected: false)
        updateSelectionButtonsFromVisibleCheckboxes()

        Task {
            let albumIDs = await self.shuffleEngine.setAlbumsSelection(for: source, isSelected: false)
            guard !albumIDs.isEmpty else { return }
            for albumID in albumIDs {
                await self.shuffleEngine.clearAssetsIfAlbumDeselected(forAlbumID: albumID)
            }
            await MainActor.run {
                self.reloadAlbums()
            }
        }
    }

    private func fetchAlbums(source: SourceType) -> [Album] {
        let context = ModelContext(modelContainer)
        let sourceRaw = source.rawValue
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.sourceTypeRaw == sourceRaw },
            sortBy: [SortDescriptor(\Album.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func updateSourceSectionVisibility() {
        let showPhotos = sourceTabs.selectedSegment != 1
        photosSectionContainer.isHidden = !showPhotos
        lightroomSectionContainer.isHidden = showPhotos
    }

    private func updateSelectionButtonsFromVisibleCheckboxes() {
        let photoCheckboxes = photosListStack.arrangedSubviews.compactMap { $0 as? NSButton }
        photosSelectAllButton.isEnabled = photoCheckboxes.contains(where: { $0.state == .off })
        photosDeselectAllButton.isEnabled = photoCheckboxes.contains(where: { $0.state == .on })

        let lightroomCheckboxes = lightroomListStack.arrangedSubviews.compactMap { $0 as? NSButton }
        lightroomSelectAllButton.isEnabled = lightroomCheckboxes.contains(where: { $0.state == .off })
        lightroomDeselectAllButton.isEnabled = lightroomCheckboxes.contains(where: { $0.state == .on })
    }

    private func setVisibleSelection(for source: SourceType, isSelected: Bool) {
        let stack: NSStackView
        switch source {
        case .applePhotos:
            stack = photosListStack
        case .lightroomCloud:
            stack = lightroomListStack
        }
        for checkbox in stack.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            checkbox.state = isSelected ? .on : .off
        }
    }

    private func renderAlbums(_ albums: [Album], in stack: NSStackView) {
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        guard !albums.isEmpty else {
            let empty = NSTextField(labelWithString: "No albums found")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
            return
        }

        for album in albums {
            let checkbox = NSButton(
                checkboxWithTitle: displayAlbumTitle(album.name),
                target: self,
                action: #selector(albumSelectionChanged(_:))
            )
            checkbox.state = album.isSelected ? .on : .off
            checkbox.identifier = NSUserInterfaceItemIdentifier(album.id)
            stack.addArrangedSubview(checkbox)
        }
    }

    private func displayAlbumTitle(_ rawName: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.hasSuffix(")"),
              let openParen = name.lastIndex(of: "("),
              openParen > name.startIndex else {
            return name
        }

        let closeParen = name.index(before: name.endIndex)
        let countText = name[name.index(after: openParen)..<closeParen]
        guard !countText.isEmpty,
              countText.allSatisfy(\.isNumber) else {
            return name
        }

        let prefix = name[..<openParen]
        guard prefix.hasSuffix(" ") else { return name }
        return String(prefix.dropLast())
    }

    private func makeAlbumsSection(
        title: String,
        selectAllAction: Selector,
        deselectAllAction: Selector
    ) -> (container: NSView, listStack: NSStackView, selectAllButton: NSButton, deselectAllButton: NSButton) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let titleLabel = makeSectionLabel(title)
        row.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(spacer)
        row.setHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let selectAllButton = NSButton(title: "Select All", target: self, action: selectAllAction)
        selectAllButton.controlSize = .small
        selectAllButton.bezelStyle = .rounded
        row.addArrangedSubview(selectAllButton)

        let deselectAllButton = NSButton(title: "Deselect All", target: self, action: deselectAllAction)
        deselectAllButton.controlSize = .small
        deselectAllButton.bezelStyle = .rounded
        row.addArrangedSubview(deselectAllButton)

        container.addArrangedSubview(row)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 6
        container.addArrangedSubview(listStack)

        return (container, listStack, selectAllButton, deselectAllButton)
    }
}

private func makeSectionLabel(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    return label
}

private func makeFormGrid(
    rows: [(String, NSView)],
    labelWidth: CGFloat = 150,
    fillControlColumn: Bool = false
) -> NSGridView {
    let grid = NSGridView()
    grid.rowSpacing = 10
    grid.columnSpacing = 12

    for (index, row) in rows.enumerated() {
        let labelField = NSTextField(labelWithString: row.0)
        labelField.alignment = .right
        labelField.textColor = .secondaryLabelColor
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        grid.addRow(with: [labelField, row.1])
        grid.row(at: index).yPlacement = .top
    }

    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = fillControlColumn ? .fill : .leading
    return grid
}

private func makeSeparator() -> NSView {
    let separator = NSBox()
    separator.boxType = .separator
    return separator
}

private func makeLabeledRow(label: String, control: NSView) -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.spacing = 12
    row.alignment = .centerY

    let labelField = NSTextField(labelWithString: "\(label):")
    labelField.textColor = .secondaryLabelColor
    labelField.alignment = .right
    labelField.translatesAutoresizingMaskIntoConstraints = false
    labelField.widthAnchor.constraint(equalToConstant: 70).isActive = true

    row.addArrangedSubview(labelField)
    row.addArrangedSubview(control)
    return row
}

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}
