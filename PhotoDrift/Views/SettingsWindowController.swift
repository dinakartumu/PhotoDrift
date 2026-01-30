import AppKit
import SwiftData
import ServiceManagement
import Photos

final class SettingsWindowController: NSWindowController {
    convenience init(modelContainer: ModelContainer) {
        let vc = SettingsViewController(modelContainer: modelContainer)
        let window = NSWindow(contentViewController: vc)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 470))
        window.center()
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        (contentViewController as? SettingsViewController)?.refreshConnectionStatus()
        window?.center()
    }
}

final class SettingsViewController: NSViewController {
    private let modelContainer: ModelContainer
    private var settings: AppSettings!

    private let intervals: [(label: String, minutes: Int)] = [
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
    ]

    private var radioButtons: [NSButton] = []
    private var photosCheckbox: NSButton!
    private var lightroomCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var shortcutRecorder: ShortcutRecorderView!

    // Photos connection controls
    private var photosStatusLabel: NSTextField!
    private var photosGrantButton: NSButton!

    // Lightroom connection controls
    private var lightroomStatusLabel: NSTextField!
    private var lightroomSignInButton: NSButton!
    private var lightroomSignOutButton: NSButton!

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let context = ModelContext(modelContainer)
        settings = AppSettings.current(in: context)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // --- Shuffle Interval ---
        root.addArrangedSubview(makeSectionLabel("Shuffle Interval"))

        let radioStack = NSStackView()
        radioStack.orientation = .vertical
        radioStack.alignment = .leading
        radioStack.spacing = 6

        for interval in intervals {
            let radio = NSButton(radioButtonWithTitle: interval.label, target: self, action: #selector(intervalChanged(_:)))
            radio.tag = interval.minutes
            if interval.minutes == settings.shuffleIntervalMinutes {
                radio.state = .on
            }
            radioButtons.append(radio)
            radioStack.addArrangedSubview(radio)
        }
        root.addArrangedSubview(radioStack)

        // --- Sources ---
        root.addArrangedSubview(makeSectionLabel("Sources"))

        // Apple Photos
        photosCheckbox = NSButton(checkboxWithTitle: "Apple Photos", target: self, action: #selector(photosToggled(_:)))
        photosCheckbox.state = settings.photosEnabled ? .on : .off
        root.addArrangedSubview(photosCheckbox)

        let photosRow = NSStackView()
        photosRow.orientation = .horizontal
        photosRow.spacing = 8

        photosStatusLabel = NSTextField(labelWithString: "")
        photosStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        photosRow.addArrangedSubview(photosStatusLabel)

        photosGrantButton = NSButton(title: "Grant Photos Access", target: self, action: #selector(grantPhotosAccess))
        photosGrantButton.bezelStyle = .rounded
        photosGrantButton.controlSize = .small
        photosGrantButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        photosGrantButton.isHidden = true
        photosRow.addArrangedSubview(photosGrantButton)

        root.addArrangedSubview(photosRow)

        // Adobe Lightroom
        lightroomCheckbox = NSButton(checkboxWithTitle: "Adobe Lightroom", target: self, action: #selector(lightroomToggled(_:)))
        lightroomCheckbox.state = settings.lightroomEnabled ? .on : .off
        root.addArrangedSubview(lightroomCheckbox)

        let lrRow = NSStackView()
        lrRow.orientation = .horizontal
        lrRow.spacing = 8

        lightroomStatusLabel = NSTextField(labelWithString: "")
        lightroomStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lrRow.addArrangedSubview(lightroomStatusLabel)

        lightroomSignInButton = NSButton(title: "Sign in to Adobe Lightroom", target: self, action: #selector(signInToLightroom))
        lightroomSignInButton.bezelStyle = .rounded
        lightroomSignInButton.controlSize = .small
        lightroomSignInButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lightroomSignInButton.isHidden = true
        lrRow.addArrangedSubview(lightroomSignInButton)

        lightroomSignOutButton = NSButton(title: "Sign Out", target: self, action: #selector(signOutOfLightroom))
        lightroomSignOutButton.bezelStyle = .rounded
        lightroomSignOutButton.controlSize = .small
        lightroomSignOutButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lightroomSignOutButton.isHidden = true
        lrRow.addArrangedSubview(lightroomSignOutButton)

        root.addArrangedSubview(lrRow)

        // --- General ---
        root.addArrangedSubview(makeSectionLabel("General"))

        let isLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(launchAtLoginToggled(_:)))
        launchAtLoginCheckbox.state = isLoginEnabled ? .on : .off
        root.addArrangedSubview(launchAtLoginCheckbox)

        // Shuffle Hotkey
        let hotkeyRow = NSStackView()
        hotkeyRow.orientation = .horizontal
        hotkeyRow.alignment = .centerY
        hotkeyRow.spacing = 8

        let hotkeyLabel = NSTextField(labelWithString: "Shuffle Hotkey:")
        hotkeyLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        hotkeyRow.addArrangedSubview(hotkeyLabel)

        shortcutRecorder = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        shortcutRecorder.configure(
            keyCode: settings.shuffleHotkeyKeyCode,
            carbonModifiers: UInt32(settings.shuffleHotkeyModifiers)
        )
        shortcutRecorder.onChange = { [weak self] keyCode, carbonModifiers in
            self?.hotkeyChanged(keyCode: keyCode, carbonModifiers: carbonModifiers)
        }
        shortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        shortcutRecorder.widthAnchor.constraint(equalToConstant: 180).isActive = true
        shortcutRecorder.heightAnchor.constraint(equalToConstant: 24).isActive = true
        hotkeyRow.addArrangedSubview(shortcutRecorder)

        root.addArrangedSubview(hotkeyRow)

        self.view = root

        refreshConnectionStatus()
    }

    func refreshConnectionStatus() {
        updatePhotosStatus()
        Task {
            let signedIn = await AdobeAuthManager.shared.isSignedIn
            await MainActor.run {
                applyLightroomUI(signedIn: signedIn)
            }
        }
    }

    private func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    // MARK: - Photos Status

    private func updatePhotosStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photosGrantButton.isHidden = true

        switch status {
        case .authorized, .limited:
            photosStatusLabel.stringValue = "\u{2713} Authorized"
            photosStatusLabel.textColor = .systemGreen
        default:
            photosStatusLabel.stringValue = ""
            photosGrantButton.isHidden = false
        }
    }

    // MARK: - Lightroom Status

    private func applyLightroomUI(signedIn: Bool) {
        if signedIn {
            lightroomStatusLabel.stringValue = "\u{2713} Connected"
            lightroomStatusLabel.textColor = .systemGreen
            lightroomSignInButton.isHidden = true
            lightroomSignOutButton.isHidden = false
        } else {
            lightroomStatusLabel.stringValue = ""
            lightroomSignInButton.isHidden = false
            lightroomSignOutButton.isHidden = true
        }
    }

    private func save() {
        let context = ModelContext(modelContainer)
        try? context.save()
    }

    // MARK: - Actions

    @objc private func intervalChanged(_ sender: NSButton) {
        for radio in radioButtons {
            radio.state = (radio === sender) ? .on : .off
        }
        settings.shuffleIntervalMinutes = sender.tag
        save()
    }

    @objc private func photosToggled(_ sender: NSButton) {
        settings.photosEnabled = sender.state == .on
        save()
    }

    @objc private func lightroomToggled(_ sender: NSButton) {
        settings.lightroomEnabled = sender.state == .on
        save()
    }

    private func hotkeyChanged(keyCode: Int, carbonModifiers: UInt32) {
        settings.shuffleHotkeyKeyCode = keyCode
        settings.shuffleHotkeyModifiers = Int(carbonModifiers)
        save()
        NotificationCenter.default.post(name: .shuffleHotkeyChanged, object: nil)
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

    @objc private func grantPhotosAccess() {
        photosGrantButton.isEnabled = false
        Task {
            let status = await PhotoKitConnector.shared.requestAuthorization()
            await MainActor.run {
                photosGrantButton.isEnabled = true
                updatePhotosStatus()
                if status == .authorized || status == .limited {
                    syncPhotosAlbums()
                } else if status == .denied || status == .restricted {
                    showPhotosDeniedAlert()
                }
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
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
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
                    lightroomSignInButton.isEnabled = true
                    applyLightroomUI(signedIn: true)
                    NotificationCenter.default.post(name: .lightroomAuthStateChanged, object: nil)
                    syncLightroomAlbums()
                }
            } catch {
                await MainActor.run {
                    lightroomSignInButton.isEnabled = true
                }
            }
        }
    }

    @objc private func signOutOfLightroom() {
        Task {
            await AdobeAuthManager.shared.signOut()
            await MainActor.run {
                let context = ModelContext(modelContainer)
                let currentSettings = AppSettings.current(in: context)
                currentSettings.adobeAccessToken = nil
                currentSettings.adobeRefreshToken = nil
                currentSettings.adobeTokenExpiry = nil
                currentSettings.lightroomEnabled = false

                let descriptor = FetchDescriptor<Album>(
                    predicate: #Predicate { $0.sourceTypeRaw == "lightroomCloud" }
                )
                if let albums = try? context.fetch(descriptor) {
                    for album in albums { context.delete(album) }
                }
                try? context.save()

                settings = currentSettings
                lightroomCheckbox.state = .off
                applyLightroomUI(signedIn: false)
                NotificationCenter.default.post(name: .lightroomAuthStateChanged, object: nil)
            }
        }
    }

    // MARK: - Album Sync

    private func syncPhotosAlbums() {
        Task {
            let infos = await PhotoKitConnector.shared.fetchAlbums()
            await MainActor.run {
                let context = ModelContext(modelContainer)
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

    private func syncLightroomAlbums() {
        Task {
            do {
                let infos = try await LightroomConnector.shared.fetchAlbums()
                await MainActor.run {
                    let context = ModelContext(modelContainer)
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
                }
            } catch {
                // Lightroom album sync failed silently
            }
        }
    }
}
