import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum GradientRenderer {

    /// Composites a gradient background with the photo drawn aspect-fit on top.
    /// Returns PNG data sized to `screenSize` (in pixels).
    static func composite(imageData: Data, screenSize: CGSize) -> Data? {
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
        drawGradient(in: ctx, size: screenSize, palette: palette)

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

    private static func drawGradient(in ctx: CGContext, size: CGSize, palette: GradientPalette) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [palette.bottomColor, palette.topColor] as CFArray,
            locations: [0.0, 1.0]
        ) else { return }

        // Bottom-to-top linear gradient
        let start = CGPoint(x: size.width / 2, y: 0)
        let end = CGPoint(x: size.width / 2, y: size.height)
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
