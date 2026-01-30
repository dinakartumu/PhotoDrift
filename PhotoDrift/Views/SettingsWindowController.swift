import AppKit
import SwiftData
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    convenience init(modelContainer: ModelContainer) {
        let vc = SettingsViewController(modelContainer: modelContainer)
        let window = NSWindow(contentViewController: vc)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 340))
        window.center()
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
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
    private var adobeStatusLabel: NSTextField!
    private var launchAtLoginCheckbox: NSButton!

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

        photosCheckbox = NSButton(checkboxWithTitle: "Apple Photos", target: self, action: #selector(photosToggled(_:)))
        photosCheckbox.state = settings.photosEnabled ? .on : .off
        root.addArrangedSubview(photosCheckbox)

        lightroomCheckbox = NSButton(checkboxWithTitle: "Adobe Lightroom", target: self, action: #selector(lightroomToggled(_:)))
        lightroomCheckbox.state = settings.lightroomEnabled ? .on : .off
        root.addArrangedSubview(lightroomCheckbox)

        adobeStatusLabel = NSTextField(labelWithString: "")
        adobeStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        adobeStatusLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(adobeStatusLabel)
        updateAdobeStatus()

        // --- General ---
        root.addArrangedSubview(makeSectionLabel("General"))

        let isLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(launchAtLoginToggled(_:)))
        launchAtLoginCheckbox.state = isLoginEnabled ? .on : .off
        root.addArrangedSubview(launchAtLoginCheckbox)

        self.view = root
    }

    private func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func updateAdobeStatus() {
        if settings.lightroomEnabled {
            if settings.adobeAccessToken != nil {
                adobeStatusLabel.stringValue = "✓ Connected to Adobe"
                adobeStatusLabel.textColor = .systemGreen
            } else {
                adobeStatusLabel.stringValue = "Sign in via Choose Albums > Lightroom tab"
                adobeStatusLabel.textColor = .secondaryLabelColor
            }
            adobeStatusLabel.isHidden = false
        } else {
            adobeStatusLabel.isHidden = true
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
        updateAdobeStatus()
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
}
