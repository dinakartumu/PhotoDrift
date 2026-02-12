import AppKit
import QuartzCore
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
    }

    private var windowsByDisplayID: [CGDirectDisplayID: NSWindow] = [:]
    private var viewsByDisplayID: [CGDirectDisplayID: LiveDesktopLayerView] = [:]
    private var contentState: ContentState?
    private var screenObserver: NSObjectProtocol?

    private init() {}

    func present(imageData: Data, animateGradient: Bool) throws {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ServiceError.invalidImageData
        }

        let palette = PaletteExtractor.extract(from: imageData)
            ?? GradientPalette(
                topColor: CGColor(red: 0.16, green: 0.23, blue: 0.42, alpha: 1),
                bottomColor: CGColor(red: 0.08, green: 0.11, blue: 0.24, alpha: 1)
            )

        contentState = ContentState(image: image, palette: palette, animateGradient: animateGradient)
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

            let view = LiveDesktopLayerView(frame: screen.frame)
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
                animateGradient: contentState.animateGradient
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

private final class LiveDesktopLayerView: NSView {
    private struct VibrantStops {
        let deep: CGColor
        let base: CGColor
        let accent: CGColor
        let highlight: CGColor
    }

    private let gradientLayer = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    private let imageLayer = CALayer()

    private var palette: GradientPalette?
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        gradientLayer.contentsScale = scale
        glowLayer.contentsScale = scale
        imageLayer.contentsScale = scale
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        glowLayer.frame = bounds
        imageLayer.frame = bounds
    }

    func render(image: CGImage, palette: GradientPalette, animateGradient: Bool) {
        self.palette = palette

        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspect

        applyStops(phase: 0)
        updateAnimation(enabled: animateGradient)
    }

    private func setupLayers() {
        wantsLayer = true

        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true
        layer = root

        gradientLayer.frame = bounds
        gradientLayer.startPoint = CGPoint(x: 0.08, y: 0.18)
        gradientLayer.endPoint = CGPoint(x: 0.92, y: 0.82)
        root.addSublayer(gradientLayer)

        glowLayer.type = .radial
        glowLayer.frame = bounds
        glowLayer.startPoint = CGPoint(x: 0.30, y: 0.30)
        glowLayer.endPoint = CGPoint(x: 1.00, y: 1.00)
        root.addSublayer(glowLayer)

        imageLayer.frame = bounds
        imageLayer.magnificationFilter = .trilinear
        imageLayer.minificationFilter = .trilinear
        imageLayer.contentsGravity = .resizeAspect
        root.addSublayer(imageLayer)
    }

    private func updateAnimation(enabled: Bool) {
        guard enabled != isAnimating else { return }
        isAnimating = enabled

        gradientLayer.removeAllAnimations()
        glowLayer.removeAllAnimations()

        guard enabled, let palette else {
            gradientLayer.startPoint = CGPoint(x: 0.08, y: 0.18)
            gradientLayer.endPoint = CGPoint(x: 0.92, y: 0.82)
            glowLayer.startPoint = CGPoint(x: 0.30, y: 0.30)
            glowLayer.endPoint = CGPoint(x: 1.00, y: 1.00)
            return
        }

        let axisStart = CABasicAnimation(keyPath: "startPoint")
        axisStart.fromValue = NSValue(point: CGPoint(x: 0.07, y: 0.16))
        axisStart.toValue = NSValue(point: CGPoint(x: 0.90, y: 0.84))
        axisStart.duration = 18
        axisStart.autoreverses = true
        axisStart.repeatCount = .infinity
        axisStart.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(axisStart, forKey: "axisStart")

        let axisEnd = CABasicAnimation(keyPath: "endPoint")
        axisEnd.fromValue = NSValue(point: CGPoint(x: 0.93, y: 0.84))
        axisEnd.toValue = NSValue(point: CGPoint(x: 0.10, y: 0.16))
        axisEnd.duration = 18
        axisEnd.autoreverses = true
        axisEnd.repeatCount = .infinity
        axisEnd.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(axisEnd, forKey: "axisEnd")

        let phases: [CGFloat] = [0, 0.25, 0.5, 0.75, 1.0]
        let colorFrames: [[CGColor]] = phases.map { phase in
            let stops = vibrantStops(from: palette, phase: phase)
            return [stops.deep, stops.base, stops.accent, stops.highlight]
        }

        let colorsAnimation = CAKeyframeAnimation(keyPath: "colors")
        colorsAnimation.values = colorFrames
        colorsAnimation.keyTimes = phases.map { NSNumber(value: Double($0)) }
        colorsAnimation.duration = 16
        colorsAnimation.repeatCount = .infinity
        colorsAnimation.calculationMode = .linear
        colorsAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        gradientLayer.add(colorsAnimation, forKey: "colors")

        let glowStart = CABasicAnimation(keyPath: "startPoint")
        glowStart.fromValue = NSValue(point: CGPoint(x: 0.20, y: 0.24))
        glowStart.toValue = NSValue(point: CGPoint(x: 0.76, y: 0.72))
        glowStart.duration = 14
        glowStart.autoreverses = true
        glowStart.repeatCount = .infinity
        glowStart.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(glowStart, forKey: "glowStartPoint")

        let glowEnd = CABasicAnimation(keyPath: "endPoint")
        glowEnd.fromValue = NSValue(point: CGPoint(x: 1.00, y: 1.00))
        glowEnd.toValue = NSValue(point: CGPoint(x: 0.58, y: 0.58))
        glowEnd.duration = 14
        glowEnd.autoreverses = true
        glowEnd.repeatCount = .infinity
        glowEnd.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(glowEnd, forKey: "glowEndPoint")
    }

    private func applyStops(phase: CGFloat) {
        guard let palette else { return }
        let stops = vibrantStops(from: palette, phase: phase)

        gradientLayer.colors = [stops.deep, stops.base, stops.accent, stops.highlight]
        gradientLayer.locations = [0.0, 0.34, 0.72, 1.0]

        glowLayer.colors = [
            withAlpha(stops.highlight, alpha: 0.42),
            withAlpha(stops.base, alpha: 0.18),
            withAlpha(stops.deep, alpha: 0.0),
        ]
        glowLayer.locations = [0.0, 0.45, 1.0]
    }

    private func vibrantStops(from palette: GradientPalette, phase: CGFloat) -> VibrantStops {
        let wave = (sin(phase * .pi * 2) + 1) / 2
        let accentMix = 0.22 + 0.22 * wave
        let highlightMix = 0.52 - 0.20 * wave

        let deep = imageDerivedColor(
            from: palette.bottomColor,
            saturationMultiplier: 1.06,
            brightnessMultiplier: 0.62,
            minimumBrightness: 0.16
        )
        let base = imageDerivedColor(
            from: palette.topColor,
            saturationMultiplier: 1.10,
            brightnessMultiplier: 0.92,
            minimumBrightness: 0.26
        )
        let accent = imageDerivedColor(
            from: blend(palette.topColor, with: palette.bottomColor, amount: accentMix),
            saturationMultiplier: 1.12,
            brightnessMultiplier: 1.04,
            minimumBrightness: 0.32
        )
        let highlight = imageDerivedColor(
            from: blend(palette.topColor, with: palette.bottomColor, amount: highlightMix),
            saturationMultiplier: 0.92,
            brightnessMultiplier: 1.20,
            minimumBrightness: 0.46
        )

        return VibrantStops(deep: deep, base: base, accent: accent, highlight: highlight)
    }

    private func imageDerivedColor(
        from color: CGColor,
        saturationMultiplier: CGFloat,
        brightnessMultiplier: CGFloat,
        minimumBrightness: CGFloat
    ) -> CGColor {
        let rgba = rgbaComponents(from: color)
        let hsb = PaletteExtractor.rgbToHSB(
            r: Double(rgba.r),
            g: Double(rgba.g),
            b: Double(rgba.b)
        )

        let saturation = min(max(CGFloat(hsb.s) * saturationMultiplier, 0.0), 0.96)
        let brightness = min(max(CGFloat(hsb.b) * brightnessMultiplier, minimumBrightness), 0.98)

        let rgb = PaletteExtractor.hsbToRGB(
            h: hsb.h,
            s: Double(saturation),
            b: Double(brightness)
        )
        return CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    private func blend(_ a: CGColor, with b: CGColor, amount: CGFloat) -> CGColor {
        let t = min(max(amount, 0), 1)
        let ca = rgbaComponents(from: a)
        let cb = rgbaComponents(from: b)
        return CGColor(
            red: ca.r + (cb.r - ca.r) * t,
            green: ca.g + (cb.g - ca.g) * t,
            blue: ca.b + (cb.b - ca.b) * t,
            alpha: ca.a + (cb.a - ca.a) * t
        )
    }

    private func withAlpha(_ color: CGColor, alpha: CGFloat) -> CGColor {
        let c = rgbaComponents(from: color)
        return CGColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    private func rgbaComponents(from color: CGColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        if let converted = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
           let components = converted.components,
           components.count >= 4 {
            return (components[0], components[1], components[2], components[3])
        }
        if let components = color.components, components.count == 2 {
            return (components[0], components[0], components[0], components[1])
        }
        return (0, 0, 0, 1)
    }
}
