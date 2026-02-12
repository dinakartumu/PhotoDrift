import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum GradientRenderer {

    /// Composites a gradient background with the photo drawn aspect-fit on top.
    /// Returns PNG data sized to `screenSize` (in pixels).
    static func composite(imageData: Data, screenSize: CGSize, phase: CGFloat = 0) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let palette = PaletteExtractor.extract(from: imageData)
            ?? GradientPalette(
                topColor: CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1),
                bottomColor: CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
            )

        let width = Int(screenSize.width)
        let height = Int(screenSize.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 1. Draw gradient background
        drawGradient(in: ctx, size: screenSize, palette: palette, phase: phase)

        // 2. Draw aspect-fit image
        let imageSize = CGSize(width: image.width, height: image.height)
        let fitRect = aspectFitRect(imageSize: imageSize, bounds: CGSize(width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: fitRect)

        // 3. Export as PNG
        guard let composited = ctx.makeImage() else { return nil }
        return pngData(from: composited)
    }

    // MARK: - Gradient drawing

    private static func drawGradient(in ctx: CGContext, size: CGSize, palette: GradientPalette, phase: CGFloat) {
        let normalizedPhase = phase.truncatingRemainder(dividingBy: 1)
        let wave = (sin(normalizedPhase * .pi * 2) + 1) / 2
        let vibrant = vibrantPalette(from: palette, phase: normalizedPhase)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [vibrant.deep, vibrant.base, vibrant.accent, vibrant.highlight] as CFArray,
            locations: [0.0, 0.34, 0.72, 1.0]
        ) else { return }

        // Long moving axis for color flow.
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let angle = normalizedPhase * .pi * 2
        let radius = max(1, min(size.width, size.height) * 0.72)
        let vector = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        let start = CGPoint(x: center.x - vector.x, y: center.y - vector.y)
        let end = CGPoint(x: center.x + vector.x, y: center.y + vector.y)
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        // Add a soft moving bloom similar to Apple's vibrant wallpaper glow.
        let glowX = size.width * (0.22 + 0.56 * wave)
        let glowY = size.height * (0.26 + 0.44 * (1 - wave))
        let glowCenter = CGPoint(x: glowX, y: glowY)
        let glowRadius = max(size.width, size.height) * 0.66
        guard let radial = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                withAlpha(vibrant.highlight, alpha: 0.40),
                withAlpha(vibrant.base, alpha: 0.18),
                withAlpha(vibrant.deep, alpha: 0.0),
            ] as CFArray,
            locations: [0.0, 0.45, 1.0]
        ) else { return }

        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.drawRadialGradient(
            radial,
            startCenter: glowCenter,
            startRadius: 0,
            endCenter: glowCenter,
            endRadius: glowRadius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }

    private static func blend(_ a: CGColor, with b: CGColor, amount: CGFloat) -> CGColor {
        let t = min(max(amount, 0), 1)
        let ca = rgbaComponents(from: a)
        let cb = rgbaComponents(from: b)
        let r = ca.r + (cb.r - ca.r) * t
        let g = ca.g + (cb.g - ca.g) * t
        let bl = ca.b + (cb.b - ca.b) * t
        let alpha = ca.a + (cb.a - ca.a) * t
        return CGColor(red: r, green: g, blue: bl, alpha: alpha)
    }

    private static func rgbaComponents(from color: CGColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        if let converted = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
           let c = converted.components,
           c.count >= 4 {
            return (c[0], c[1], c[2], c[3])
        }
        if let c = color.components, c.count == 2 {
            return (c[0], c[0], c[0], c[1])
        }
        return (0, 0, 0, 1)
    }

    private struct VibrantPalette {
        let deep: CGColor
        let base: CGColor
        let accent: CGColor
        let highlight: CGColor
    }

    private static func vibrantPalette(from palette: GradientPalette, phase: CGFloat) -> VibrantPalette {
        let wave = (sin(phase * .pi * 2) + 1) / 2
        let accentMix = 0.22 + 0.22 * wave
        let highlightMix = 0.52 - 0.20 * wave

        let deep = imageDerivedVibrantColor(
            from: palette.bottomColor,
            saturationMultiplier: 1.06,
            brightnessMultiplier: 0.62,
            minimumBrightness: 0.16
        )
        let base = imageDerivedVibrantColor(
            from: palette.topColor,
            saturationMultiplier: 1.10,
            brightnessMultiplier: 0.92,
            minimumBrightness: 0.26
        )
        let accentSource = blend(palette.topColor, with: palette.bottomColor, amount: accentMix)
        let accent = imageDerivedVibrantColor(
            from: accentSource,
            saturationMultiplier: 1.12,
            brightnessMultiplier: 1.04,
            minimumBrightness: 0.32
        )
        let highlightSource = blend(palette.topColor, with: palette.bottomColor, amount: highlightMix)
        let highlight = imageDerivedVibrantColor(
            from: highlightSource,
            saturationMultiplier: 0.92,
            brightnessMultiplier: 1.20,
            minimumBrightness: 0.46
        )

        return VibrantPalette(deep: deep, base: base, accent: accent, highlight: highlight)
    }

    private static func imageDerivedVibrantColor(
        from color: CGColor,
        saturationMultiplier: CGFloat,
        brightnessMultiplier: CGFloat,
        minimumBrightness: CGFloat
    ) -> CGColor {
        let rgb = rgbaComponents(from: color)
        let hsb = PaletteExtractor.rgbToHSB(
            r: Double(rgb.r),
            g: Double(rgb.g),
            b: Double(rgb.b)
        )

        let hue = CGFloat(hsb.h)
        let saturation = min(max(CGFloat(hsb.s) * saturationMultiplier, 0.0), 0.96)
        let brightness = min(max(CGFloat(hsb.b) * brightnessMultiplier, minimumBrightness), 0.98)

        let shiftedRGB = PaletteExtractor.hsbToRGB(
            h: Double(hue),
            s: Double(saturation),
            b: Double(brightness)
        )
        return CGColor(red: shiftedRGB.r, green: shiftedRGB.g, blue: shiftedRGB.b, alpha: 1)
    }

    private static func withAlpha(_ color: CGColor, alpha: CGFloat) -> CGColor {
        let c = rgbaComponents(from: color)
        return CGColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    // MARK: - Geometry

    static func aspectFitRect(imageSize: CGSize, bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fitWidth = imageSize.width * scale
        let fitHeight = imageSize.height * scale
        let x = (bounds.width - fitWidth) / 2
        let y = (bounds.height - fitHeight) / 2

        return CGRect(x: x, y: y, width: fitWidth, height: fitHeight)
    }

    /// Returns true when the image would leave visible letterbox/pillarbox bars.
    static func needsGradientMatte(imageSize: CGSize, screenSize: CGSize) -> Bool {
        let fitRect = aspectFitRect(imageSize: imageSize, bounds: screenSize)
        return fitRect.width < screenSize.width - 1 || fitRect.height < screenSize.height - 1
    }

    // MARK: - PNG export

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
