import AppKit
import QuartzCore

final class LiveWallpaperRendererView: NSView {
    private struct VibrantStops {
        let deep: CGColor
        let base: CGColor
        let accent: CGColor
        let highlight: CGColor
    }

    private let gradientLayer = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    private let waveLayerFar = CAGradientLayer()
    private let waveLayerNear = CAGradientLayer()
    private let waveMaskFar = CAShapeLayer()
    private let waveMaskNear = CAShapeLayer()
    private let imageLayer = CALayer()

    private var palette: GradientPalette?
    private var isAnimating = false
    private var currentMotionEffect: LiveGradientMotionEffect = .mediumLoops

    private struct MotionProfile {
        let farDuration: CFTimeInterval
        let nearDuration: CFTimeInterval
        let colorDuration: CFTimeInterval
        let glowDuration: CFTimeInterval
        let nearOpacityRange: ClosedRange<Float>
        let farOpacityRange: ClosedRange<Float>
    }

    private struct WaveBandGeometry {
        let baseline: CGFloat
        let amplitude: CGFloat
        let wavelength: CGFloat
        let thickness: CGFloat
        let phaseOffset: CGFloat
    }

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
        waveLayerFar.contentsScale = scale
        waveLayerNear.contentsScale = scale
        waveMaskFar.contentsScale = scale
        waveMaskNear.contentsScale = scale
        imageLayer.contentsScale = scale
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        glowLayer.frame = bounds
        waveLayerFar.frame = bounds
        waveLayerNear.frame = bounds
        imageLayer.frame = bounds

        waveMaskFar.frame = bounds
        waveMaskNear.frame = bounds
        updateWaveMaskPaths()
    }

    func render(
        image: CGImage,
        palette: GradientPalette,
        animateGradient: Bool,
        motionEffect: LiveGradientMotionEffect
    ) {
        let motionEffectChanged = motionEffect != currentMotionEffect
        self.palette = palette
        self.currentMotionEffect = motionEffect

        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspect

        updateWaveMaskPaths()
        applyStops(phase: 0)
        if motionEffectChanged, animateGradient, isAnimating {
            updateAnimation(enabled: false, refreshTimeline: true)
        }
        updateAnimation(enabled: animateGradient, refreshTimeline: true)
    }

    private func updateWaveMaskPaths() {
        guard !bounds.isEmpty else { return }
        let farBand = waveBandGeometry(for: currentMotionEffect, isNearBand: false)
        let nearBand = waveBandGeometry(for: currentMotionEffect, isNearBand: true)
        waveMaskFar.path = waveRibbonPath(
            in: bounds,
            phase: farBand.phaseOffset,
            baseline: farBand.baseline,
            amplitude: farBand.amplitude,
            wavelength: farBand.wavelength,
            thickness: farBand.thickness,
            motionEffect: currentMotionEffect
        )
        waveMaskNear.path = waveRibbonPath(
            in: bounds,
            phase: nearBand.phaseOffset,
            baseline: nearBand.baseline,
            amplitude: nearBand.amplitude,
            wavelength: nearBand.wavelength,
            thickness: nearBand.thickness,
            motionEffect: currentMotionEffect
        )
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

        waveLayerFar.frame = bounds
        waveLayerFar.startPoint = CGPoint(x: 0, y: 0.5)
        waveLayerFar.endPoint = CGPoint(x: 1, y: 0.5)
        waveLayerFar.mask = waveMaskFar
        root.addSublayer(waveLayerFar)

        waveLayerNear.frame = bounds
        waveLayerNear.startPoint = CGPoint(x: 0, y: 0.5)
        waveLayerNear.endPoint = CGPoint(x: 1, y: 0.5)
        waveLayerNear.mask = waveMaskNear
        root.addSublayer(waveLayerNear)

        imageLayer.frame = bounds
        imageLayer.magnificationFilter = .trilinear
        imageLayer.minificationFilter = .trilinear
        imageLayer.contentsGravity = .resizeAspect
        root.addSublayer(imageLayer)
    }

    private func updateAnimation(enabled: Bool, refreshTimeline: Bool = false) {
        guard enabled != isAnimating || refreshTimeline else { return }
        isAnimating = enabled

        gradientLayer.removeAllAnimations()
        glowLayer.removeAllAnimations()
        waveLayerFar.removeAllAnimations()
        waveLayerNear.removeAllAnimations()
        waveMaskFar.removeAllAnimations()
        waveMaskNear.removeAllAnimations()

        guard enabled, let palette else {
            gradientLayer.startPoint = CGPoint(x: 0.08, y: 0.18)
            gradientLayer.endPoint = CGPoint(x: 0.92, y: 0.82)
            glowLayer.startPoint = CGPoint(x: 0.30, y: 0.30)
            glowLayer.endPoint = CGPoint(x: 1.00, y: 1.00)
            waveLayerFar.opacity = 0
            waveLayerNear.opacity = 0
            return
        }

        let profile = motionProfile(for: currentMotionEffect)
        installWaveAnimations(profile: profile)

        let axisStart = CABasicAnimation(keyPath: "startPoint")
        axisStart.fromValue = NSValue(point: CGPoint(x: 0.07, y: 0.16))
        axisStart.toValue = NSValue(point: CGPoint(x: 0.90, y: 0.84))
        axisStart.duration = profile.farDuration
        axisStart.autoreverses = true
        axisStart.repeatCount = .infinity
        axisStart.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(axisStart, forKey: "axisStart")

        let axisEnd = CABasicAnimation(keyPath: "endPoint")
        axisEnd.fromValue = NSValue(point: CGPoint(x: 0.93, y: 0.84))
        axisEnd.toValue = NSValue(point: CGPoint(x: 0.10, y: 0.16))
        axisEnd.duration = profile.farDuration
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
        colorsAnimation.duration = profile.colorDuration
        colorsAnimation.repeatCount = .infinity
        colorsAnimation.calculationMode = .linear
        colorsAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        gradientLayer.add(colorsAnimation, forKey: "colors")

        let glowStart = CABasicAnimation(keyPath: "startPoint")
        glowStart.fromValue = NSValue(point: CGPoint(x: 0.20, y: 0.24))
        glowStart.toValue = NSValue(point: CGPoint(x: 0.76, y: 0.72))
        glowStart.duration = profile.glowDuration
        glowStart.autoreverses = true
        glowStart.repeatCount = .infinity
        glowStart.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(glowStart, forKey: "glowStartPoint")

        let glowEnd = CABasicAnimation(keyPath: "endPoint")
        glowEnd.fromValue = NSValue(point: CGPoint(x: 1.00, y: 1.00))
        glowEnd.toValue = NSValue(point: CGPoint(x: 0.58, y: 0.58))
        glowEnd.duration = profile.glowDuration
        glowEnd.autoreverses = true
        glowEnd.repeatCount = .infinity
        glowEnd.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(glowEnd, forKey: "glowEndPoint")
    }

    private func installWaveAnimations(profile: MotionProfile) {
        guard !bounds.isEmpty else { return }

        waveLayerFar.opacity = 0.48
        waveLayerNear.opacity = 0.62

        let farBand = waveBandGeometry(for: currentMotionEffect, isNearBand: false)
        let nearBand = waveBandGeometry(for: currentMotionEffect, isNearBand: true)
        let farPhases = phaseSamples(for: currentMotionEffect)
        let farPaths: [CGPath] = farPhases.map { phase in
            waveRibbonPath(
                in: bounds,
                phase: phase + farBand.phaseOffset,
                baseline: farBand.baseline,
                amplitude: farBand.amplitude,
                wavelength: farBand.wavelength,
                thickness: farBand.thickness,
                motionEffect: currentMotionEffect
            )
        }
        let farAnimation = CAKeyframeAnimation(keyPath: "path")
        farAnimation.values = farPaths
        farAnimation.keyTimes = farPhases.map { NSNumber(value: Double($0)) }
        farAnimation.duration = profile.farDuration
        farAnimation.repeatCount = .infinity
        farAnimation.calculationMode = .linear
        farAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        waveMaskFar.add(farAnimation, forKey: "wavePath")

        let nearPhases = phaseSamples(for: currentMotionEffect)
        let nearPaths: [CGPath] = nearPhases.map { phase in
            waveRibbonPath(
                in: bounds,
                phase: phase + nearBand.phaseOffset,
                baseline: nearBand.baseline,
                amplitude: nearBand.amplitude,
                wavelength: nearBand.wavelength,
                thickness: nearBand.thickness,
                motionEffect: currentMotionEffect
            )
        }
        let nearAnimation = CAKeyframeAnimation(keyPath: "path")
        nearAnimation.values = nearPaths
        nearAnimation.keyTimes = nearPhases.map { NSNumber(value: Double($0)) }
        nearAnimation.duration = profile.nearDuration
        nearAnimation.repeatCount = .infinity
        nearAnimation.calculationMode = .linear
        nearAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        waveMaskNear.add(nearAnimation, forKey: "wavePath")

        let nearOpacity = CABasicAnimation(keyPath: "opacity")
        nearOpacity.fromValue = profile.nearOpacityRange.lowerBound
        nearOpacity.toValue = profile.nearOpacityRange.upperBound
        nearOpacity.duration = 6
        nearOpacity.autoreverses = true
        nearOpacity.repeatCount = .infinity
        nearOpacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        waveLayerNear.add(nearOpacity, forKey: "breath")

        let farOpacity = CABasicAnimation(keyPath: "opacity")
        farOpacity.fromValue = profile.farOpacityRange.lowerBound
        farOpacity.toValue = profile.farOpacityRange.upperBound
        farOpacity.duration = 8
        farOpacity.autoreverses = true
        farOpacity.repeatCount = .infinity
        farOpacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        waveLayerFar.add(farOpacity, forKey: "breath")
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

        waveLayerFar.colors = [
            withAlpha(stops.base, alpha: 0.0),
            withAlpha(stops.accent, alpha: 0.20),
            withAlpha(stops.highlight, alpha: 0.34),
            withAlpha(stops.base, alpha: 0.0),
        ]
        waveLayerFar.locations = [0.0, 0.38, 0.62, 1.0]

        waveLayerNear.colors = [
            withAlpha(stops.deep, alpha: 0.0),
            withAlpha(stops.accent, alpha: 0.24),
            withAlpha(stops.highlight, alpha: 0.40),
            withAlpha(stops.deep, alpha: 0.0),
        ]
        waveLayerNear.locations = [0.0, 0.35, 0.65, 1.0]
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

    private func waveRibbonPath(
        in rect: CGRect,
        phase: CGFloat,
        baseline: CGFloat,
        amplitude: CGFloat,
        wavelength: CGFloat,
        thickness: CGFloat,
        motionEffect: LiveGradientMotionEffect
    ) -> CGPath {
        let width = rect.width
        let height = rect.height
        let yBase = height * baseline
        let amp = height * amplitude
        let band = height * thickness
        let waveLength = max(80, width * wavelength)
        let step = max(4, width / samplingDivisor(for: motionEffect))

        let path = CGMutablePath()
        var x: CGFloat = 0

        let startY = yBase + knotValue(
            progress: 0,
            phase: phase,
            motionEffect: motionEffect
        ) * amp
        path.move(to: CGPoint(x: 0, y: startY))

        while x <= width {
            let progress = (x / waveLength) * .pi * 2
            let y = yBase + knotValue(
                progress: progress,
                phase: phase,
                motionEffect: motionEffect
            ) * amp
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        let edgeProgress = (width / waveLength) * .pi * 2
        let edgeWave = knotValue(
            progress: edgeProgress,
            phase: phase,
            motionEffect: motionEffect
        )
        path.addLine(to: CGPoint(x: width, y: yBase + edgeWave * amp + band))

        var reverseX = width
        while reverseX >= 0 {
            let progress = (reverseX / waveLength) * .pi * 2
            let y = yBase + knotValue(
                progress: progress,
                phase: phase,
                motionEffect: motionEffect
            ) * amp + band
            path.addLine(to: CGPoint(x: reverseX, y: y))
            reverseX -= step
        }
        path.closeSubpath()
        return path
    }

    private func motionProfile(for effect: LiveGradientMotionEffect) -> MotionProfile {
        switch effect {
        case .simpleEllipse:
            MotionProfile(
                farDuration: 30,
                nearDuration: 22,
                colorDuration: 22,
                glowDuration: 16,
                nearOpacityRange: 0.50...0.60,
                farOpacityRange: 0.38...0.46
            )
        case .mediumLoops:
            MotionProfile(
                farDuration: 20,
                nearDuration: 14,
                colorDuration: 16,
                glowDuration: 12,
                nearOpacityRange: 0.50...0.68,
                farOpacityRange: 0.38...0.52
            )
        case .denseKnots:
            MotionProfile(
                farDuration: 12,
                nearDuration: 8,
                colorDuration: 12,
                glowDuration: 9,
                nearOpacityRange: 0.46...0.76,
                farOpacityRange: 0.34...0.58
            )
        case .gridLattice:
            MotionProfile(
                farDuration: 9,
                nearDuration: 9,
                colorDuration: 10,
                glowDuration: 8,
                nearOpacityRange: 0.42...0.70,
                farOpacityRange: 0.34...0.56
            )
        }
    }

    private func waveBandGeometry(
        for effect: LiveGradientMotionEffect,
        isNearBand: Bool
    ) -> WaveBandGeometry {
        switch (effect, isNearBand) {
        case (.simpleEllipse, false):
            return WaveBandGeometry(
                baseline: 0.46,
                amplitude: 0.017,
                wavelength: 1.08,
                thickness: 0.17,
                phaseOffset: 0.00
            )
        case (.simpleEllipse, true):
            return WaveBandGeometry(
                baseline: 0.64,
                amplitude: 0.024,
                wavelength: 1.18,
                thickness: 0.23,
                phaseOffset: 0.17
            )
        case (.mediumLoops, false):
            return WaveBandGeometry(
                baseline: 0.44,
                amplitude: 0.032,
                wavelength: 0.74,
                thickness: 0.16,
                phaseOffset: 0.00
            )
        case (.mediumLoops, true):
            return WaveBandGeometry(
                baseline: 0.62,
                amplitude: 0.048,
                wavelength: 0.82,
                thickness: 0.22,
                phaseOffset: 0.28
            )
        case (.denseKnots, false):
            return WaveBandGeometry(
                baseline: 0.42,
                amplitude: 0.052,
                wavelength: 0.50,
                thickness: 0.18,
                phaseOffset: 0.00
            )
        case (.denseKnots, true):
            return WaveBandGeometry(
                baseline: 0.60,
                amplitude: 0.074,
                wavelength: 0.56,
                thickness: 0.24,
                phaseOffset: 0.35
            )
        case (.gridLattice, false):
            return WaveBandGeometry(
                baseline: 0.45,
                amplitude: 0.028,
                wavelength: 0.40,
                thickness: 0.15,
                phaseOffset: 0.00
            )
        case (.gridLattice, true):
            return WaveBandGeometry(
                baseline: 0.62,
                amplitude: 0.036,
                wavelength: 0.36,
                thickness: 0.19,
                phaseOffset: 0.24
            )
        }
    }

    private func phaseSamples(for effect: LiveGradientMotionEffect) -> [CGFloat] {
        switch effect {
        case .simpleEllipse:
            return [0.00, 0.16, 0.32, 0.48, 0.64, 0.80, 1.00]
        case .mediumLoops:
            return [0.00, 0.14, 0.28, 0.42, 0.56, 0.70, 0.84, 1.00]
        case .denseKnots:
            return [0.00, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00]
        case .gridLattice:
            return [0.00, 0.125, 0.25, 0.375, 0.50, 0.625, 0.75, 0.875, 1.00]
        }
    }

    private func samplingDivisor(for effect: LiveGradientMotionEffect) -> CGFloat {
        switch effect {
        case .simpleEllipse:
            return 100
        case .mediumLoops:
            return 116
        case .denseKnots:
            return 140
        case .gridLattice:
            return 160
        }
    }

    private func knotValue(
        progress: CGFloat,
        phase: CGFloat,
        motionEffect: LiveGradientMotionEffect
    ) -> CGFloat {
        let p = phase * .pi * 2

        switch motionEffect {
        case .simpleEllipse:
            return sin(progress + (p * 0.75))
        case .mediumLoops:
            let a = sin(progress + p)
            let b = cos((progress * 0.52) - (p * 0.65))
            return (a * b) * 1.06
        case .denseKnots:
            let a = sin((progress * 2.3) + (p * 1.6))
            let b = sin((progress * 4.9) - (p * 1.2))
            let c = cos((progress * 7.4) + (p * 0.55))
            return (a * 0.42) + (b * 0.33) + (c * 0.25)
        case .gridLattice:
            let lattice = sin((progress * 3.6) + p) * sin((progress * 5.2) - (p * 1.4))
            let shimmer = sin((progress * 9.0) + (p * 0.5))
            return (lattice * 0.68) + (shimmer * 0.32)
        }
    }
}
