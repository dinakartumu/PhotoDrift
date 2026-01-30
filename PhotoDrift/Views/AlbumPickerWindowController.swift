import AppKit
import SwiftData
import Photos

// MARK: - Window Controller

final class AlbumPickerWindowController: NSWindowController {
    convenience init(modelContainer: ModelContainer) {
        let vc = AlbumPickerViewController(modelContainer: modelContainer)
        let window = NSWindow(contentViewController: vc)
        window.title = "Choose Albums"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 360, height: 420))
        window.center()
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
    }
}

// MARK: - Container ViewController

final class AlbumPickerViewController: NSViewController {
    private let modelContainer: ModelContainer
    private var segmentedControl: NSSegmentedControl!
    private var photosVC: PhotosAlbumListViewController!
    private var lightroomVC: LightroomAlbumListViewController!
    private var containerView: NSView!
    private var currentChild: NSViewController?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 420))

        segmentedControl = NSSegmentedControl(labels: ["Photos", "Lightroom"], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(segmentedControl)

        containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(containerView)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            segmentedControl.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            containerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        photosVC = PhotosAlbumListViewController(modelContainer: modelContainer)
        lightroomVC = LightroomAlbumListViewController(modelContainer: modelContainer)

        self.view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        showTab(0)
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        showTab(sender.selectedSegment)
    }

    private func showTab(_ index: Int) {
        if let current = currentChild {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        let child = index == 0 ? photosVC! : lightroomVC!
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(child.view)

        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        currentChild = child

        if index == 0 {
            photosVC.refresh()
        } else {
            lightroomVC.refresh()
        }
    }
}

// MARK: - Photos Album List

final class PhotosAlbumListViewController: NSViewController {
    private let modelContainer: ModelContainer
    private var stackView: NSStackView!
    private var scrollView: NSScrollView!
    private var messageLabel: NSTextField!
    private var actionButton: NSButton!
    private var spinner: NSProgressIndicator!

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()

        messageLabel = NSTextField(labelWithString: "")
        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.isHidden = true
        root.addSubview(messageLabel)

        actionButton = NSButton(title: "Grant Photos Access", target: self, action: #selector(requestAccess))
        actionButton.bezelStyle = .rounded
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.isHidden = true
        root.addSubview(actionButton)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        root.addSubview(spinner)

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView = NSScrollView()
        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            actionButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            actionButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

            spinner.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            spinner.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 8),
        ])

        self.view = root
    }

    func refresh() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updateForAuthStatus(status)
    }

    private func updateForAuthStatus(_ status: PHAuthorizationStatus) {
        scrollView.isHidden = true
        messageLabel.isHidden = true
        actionButton.isHidden = true
        spinner.isHidden = true

        switch status {
        case .authorized, .limited:
            scrollView.isHidden = false
            loadAlbums()
        case .denied, .restricted:
            messageLabel.stringValue = "Photos access denied. Open System Settings to grant access."
            messageLabel.textColor = .systemRed
            messageLabel.isHidden = false
        default:
            actionButton.isHidden = false
        }
    }

    @objc private func requestAccess() {
        actionButton.isEnabled = false
        Task {
            let status = await PhotoKitConnector.shared.requestAuthorization()
            await MainActor.run {
                updateForAuthStatus(status)
            }
        }
    }

    private func loadAlbums() {
        spinner.isHidden = false
        spinner.startAnimation(nil)
        scrollView.isHidden = true

        Task {
            let infos = await PhotoKitConnector.shared.fetchAlbums()
            await MainActor.run {
                syncAlbumsToDatabase(infos)
                rebuildCheckboxes()
                spinner.stopAnimation(nil)
                spinner.isHidden = true
                scrollView.isHidden = false
            }
        }
    }

    private func syncAlbumsToDatabase(_ infos: [AlbumInfo]) {
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

    private func rebuildCheckboxes() {
        for v in stackView.arrangedSubviews { v.removeFromSuperview() }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.sourceTypeRaw == "applePhotos" },
            sortBy: [SortDescriptor(\Album.name)]
        )
        guard let albums = try? context.fetch(descriptor) else { return }

        if albums.isEmpty {
            let label = NSTextField(labelWithString: "No albums found")
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(label)
            return
        }

        for album in albums {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 4

            let checkbox = NSButton(checkboxWithTitle: album.name, target: self, action: #selector(albumToggled(_:)))
            checkbox.state = album.isSelected ? .on : .off
            checkbox.identifier = NSUserInterfaceItemIdentifier(album.id)
            row.addArrangedSubview(checkbox)

            let count = NSTextField(labelWithString: "\(album.assetCount)")
            count.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            count.textColor = .secondaryLabelColor
            row.addArrangedSubview(count)

            stackView.addArrangedSubview(row)
        }
    }

    @objc private func albumToggled(_ sender: NSButton) {
        guard let albumID = sender.identifier?.rawValue else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.id == albumID }
        )
        guard let album = try? context.fetch(descriptor).first else { return }
        album.isSelected = sender.state == .on
        try? context.save()
    }
}

// MARK: - Lightroom Album List

final class LightroomAlbumListViewController: NSViewController {
    private let modelContainer: ModelContainer
    private var stackView: NSStackView!
    private var scrollView: NSScrollView!
    private var headerStack: NSStackView!
    private var signInButton: NSButton!
    private var signOutButton: NSButton!
    private var connectedLabel: NSTextField!
    private var errorLabel: NSTextField!
    private var spinner: NSProgressIndicator!

    private var isSignedIn = false

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()

        // Header area
        headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(headerStack)

        connectedLabel = NSTextField(labelWithString: "✓ Connected")
        connectedLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        connectedLabel.textColor = .systemGreen
        connectedLabel.isHidden = true

        signOutButton = NSButton(title: "Sign Out", target: self, action: #selector(signOut))
        signOutButton.bezelStyle = .rounded
        signOutButton.controlSize = .small
        signOutButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        signOutButton.isHidden = true

        headerStack.addArrangedSubview(connectedLabel)
        headerStack.addArrangedSubview(signOutButton)

        signInButton = NSButton(title: "Sign in to Adobe Lightroom", target: self, action: #selector(signIn))
        signInButton.bezelStyle = .rounded
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.isHidden = true
        root.addSubview(signInButton)

        errorLabel = NSTextField(wrappingLabelWithString: "")
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.textColor = .systemRed
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true
        root.addSubview(errorLabel)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        root.addSubview(spinner)

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView = NSScrollView()
        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),

            signInButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            signInButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

            spinner.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            spinner.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            errorLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            errorLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -4),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 8),
        ])

        self.view = root
    }

    func refresh() {
        let context = ModelContext(modelContainer)
        let settings = AppSettings.current(in: context)
        Task {
            await AdobeAuthManager.shared.loadTokens(from: settings)
            let signedIn = await AdobeAuthManager.shared.isSignedIn
            await MainActor.run {
                isSignedIn = signedIn
                updateUI()
                if isSignedIn {
                    loadAlbums()
                }
            }
        }
    }

    private func updateUI() {
        signInButton.isHidden = isSignedIn
        headerStack.isHidden = !isSignedIn
        connectedLabel.isHidden = !isSignedIn
        signOutButton.isHidden = !isSignedIn
        scrollView.isHidden = !isSignedIn
    }

    @objc private func signIn() {
        guard let window = view.window else { return }
        signInButton.isEnabled = false
        errorLabel.isHidden = true

        Task {
            do {
                _ = try await AdobeAuthManager.shared.signIn(from: window)
                let context = ModelContext(modelContainer)
                let settings = AppSettings.current(in: context)
                await AdobeAuthManager.shared.saveTokens(to: settings)
                try? context.save()
                await MainActor.run {
                    isSignedIn = true
                    signInButton.isEnabled = true
                    updateUI()
                    loadAlbums()
                }
            } catch {
                await MainActor.run {
                    errorLabel.stringValue = error.localizedDescription
                    errorLabel.isHidden = false
                    signInButton.isEnabled = true
                }
            }
        }
    }

    @objc private func signOut() {
        Task {
            await AdobeAuthManager.shared.signOut()
            await MainActor.run {
                let context = ModelContext(modelContainer)
                let settings = AppSettings.current(in: context)
                settings.adobeAccessToken = nil
                settings.adobeRefreshToken = nil
                settings.adobeTokenExpiry = nil
                settings.lightroomEnabled = false

                let descriptor = FetchDescriptor<Album>(
                    predicate: #Predicate { $0.sourceTypeRaw == "lightroomCloud" }
                )
                if let albums = try? context.fetch(descriptor) {
                    for album in albums { context.delete(album) }
                }
                try? context.save()

                isSignedIn = false
                updateUI()
                for v in stackView.arrangedSubviews { v.removeFromSuperview() }
            }
        }
    }

    private func loadAlbums() {
        spinner.isHidden = false
        spinner.startAnimation(nil)
        errorLabel.isHidden = true

        Task {
            do {
                let infos = try await LightroomConnector.shared.fetchAlbums()
                await MainActor.run {
                    syncAlbumsToDatabase(infos)
                    rebuildCheckboxes()
                    spinner.stopAnimation(nil)
                    spinner.isHidden = true
                }
            } catch {
                await MainActor.run {
                    errorLabel.stringValue = error.localizedDescription
                    errorLabel.isHidden = false
                    spinner.stopAnimation(nil)
                    spinner.isHidden = true
                }
            }
        }
    }

    private func syncAlbumsToDatabase(_ infos: [AlbumInfo]) {
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

    private func rebuildCheckboxes() {
        for v in stackView.arrangedSubviews { v.removeFromSuperview() }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.sourceTypeRaw == "lightroomCloud" },
            sortBy: [SortDescriptor(\Album.name)]
        )
        guard let albums = try? context.fetch(descriptor) else { return }

        if albums.isEmpty {
            let label = NSTextField(labelWithString: "No albums found")
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(label)
            return
        }

        for album in albums {
            let checkbox = NSButton(checkboxWithTitle: album.name, target: self, action: #selector(albumToggled(_:)))
            checkbox.state = album.isSelected ? .on : .off
            checkbox.identifier = NSUserInterfaceItemIdentifier(album.id)
            stackView.addArrangedSubview(checkbox)
        }
    }

    @objc private func albumToggled(_ sender: NSButton) {
        guard let albumID = sender.identifier?.rawValue else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.id == albumID }
        )
        guard let album = try? context.fetch(descriptor).first else { return }
        album.isSelected = sender.state == .on
        try? context.save()
    }
}
