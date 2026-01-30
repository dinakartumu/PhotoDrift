import AppKit

final class ShortcutRecorderView: NSView {
    private(set) var keyCode: Int = -1
    private(set) var carbonModifiers: UInt32 = 0
    var onChange: ((Int, UInt32) -> Void)?

    private var isRecording = false
    private let displayField = NSTextField()
    private let clearButton = NSButton()
    private var localMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        displayField.isEditable = false
        displayField.isSelectable = false
        displayField.isBezeled = false
        displayField.drawsBackground = false
        displayField.alignment = .center
        displayField.font = .systemFont(ofSize: NSFont.systemFontSize)
        addSubview(displayField)

        clearButton.bezelStyle = .inline
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.imagePosition = .imageOnly
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.isHidden = true
        addSubview(clearButton)

        updateDisplay()
    }

    override func layout() {
        super.layout()
        let clearSize: CGFloat = 16
        let clearPadding: CGFloat = clearButton.isHidden ? 0 : clearSize + 4
        displayField.frame = NSRect(
            x: 4,
            y: (bounds.height - 18) / 2,
            width: bounds.width - 8 - clearPadding,
            height: 18
        )
        clearButton.frame = NSRect(
            x: bounds.width - clearSize - 6,
            y: (bounds.height - clearSize) / 2,
            width: clearSize,
            height: clearSize
        )
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        startRecording()
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        updateDisplay()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        updateDisplay()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == 0x35 { // Escape
            stopRecording()
            return
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = !mods.intersection([.command, .option, .control, .shift]).isEmpty

        guard hasModifier else { return }

        keyCode = Int(event.keyCode)
        carbonModifiers = GlobalHotkeyManager.carbonModifiers(from: mods)
        stopRecording()
        onChange?(keyCode, carbonModifiers)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording()
        }
        return super.resignFirstResponder()
    }

    @objc private func clearShortcut() {
        keyCode = -1
        carbonModifiers = 0
        updateDisplay()
        onChange?(keyCode, carbonModifiers)
    }

    private func updateDisplay() {
        if isRecording {
            displayField.stringValue = "Type shortcut\u{2026}"
            displayField.textColor = .placeholderTextColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2
            clearButton.isHidden = true
        } else if keyCode >= 0 {
            displayField.stringValue = GlobalHotkeyManager.displayString(
                keyCode: keyCode,
                carbonModifiers: carbonModifiers
            )
            displayField.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
            clearButton.isHidden = false
        } else {
            displayField.stringValue = "Click to record shortcut"
            displayField.textColor = .placeholderTextColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
            clearButton.isHidden = true
        }
        needsLayout = true
    }

    func configure(keyCode: Int, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        updateDisplay()
    }
}
