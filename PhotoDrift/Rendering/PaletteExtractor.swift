import CoreGraphics
import Foundation
import ImageIO

struct GradientPalette: Equatable {
    let topColor: CGColor
    let bottomColor: CGColor
}

enum PaletteExtractor {

    static func extract(from imageData: Data) -> GradientPalette? {
        guard let thumbnail = downsample(data: imageData, maxDimension: 80) else { return nil }

        let width = thumbnail.width
        let height = thumbnail.height
        guard width > 0, height > 0 else { return nil }

        guard let pixelData = pixelBuffer(from: thumbnail, width: width, height: height) else { return nil }

        let buckets = bucketByHue(pixelData: pixelData, width: width, height: height)
        return paletteFromBuckets(buckets)
    }

    // MARK: - Downsampling

    private static func downsample(data: Data, maxDimension: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary)
    }

    // MARK: - Pixel reading

    private static func pixelBuffer(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    // MARK: - Hue bucketing

    private struct HueBucket {
        var count: Int = 0
        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0

        var averageR: Double { count > 0 ? totalR / Double(count) : 0 }
        var averageG: Double { count > 0 ? totalG / Double(count) : 0 }
        var averageB: Double { count > 0 ? totalB / Double(count) : 0 }
    }

    static let bucketCount = 24

    private static func bucketByHue(pixelData: [UInt8], width: Int, height: Int) -> [HueBucket] {
        var buckets = [HueBucket](repeating: HueBucket(), count: bucketCount)
        let bytesPerPixel = 4

        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = (y * width + x) * bytesPerPixel
                let r = Double(pixelData[offset]) / 255.0
                let g = Double(pixelData[offset + 1]) / 255.0
                let b = Double(pixelData[offset + 2]) / 255.0

                let (hue, sat, bri) = rgbToHSB(r: r, g: g, b: b)

                // Filter out near-white, near-black, and very desaturated pixels
                if bri > 0.95 && sat < 0.1 { continue }
                if bri < 0.05 { continue }
                if sat < 0.05 { continue }

                let bucketIndex = min(Int(hue * Double(bucketCount)), bucketCount - 1)
                buckets[bucketIndex].count += 1
                buckets[bucketIndex].totalR += r
                buckets[bucketIndex].totalG += g
                buckets[bucketIndex].totalB += b
            }
        }

        return buckets
    }

    // MARK: - Palette generation

    private static func paletteFromBuckets(_ buckets: [HueBucket]) -> GradientPalette {
        let sorted = buckets.enumerated()
            .filter { $0.element.count > 0 }
            .sorted { $0.element.count > $1.element.count }

        let baseColor: (r: Double, g: Double, b: Double)
        let secondaryColor: (r: Double, g: Double, b: Double)

        if sorted.count >= 2 {
            let top = sorted[0].element
            baseColor = (top.averageR, top.averageG, top.averageB)
            let second = sorted[1].element
            secondaryColor = (second.averageR, second.averageG, second.averageB)
        } else if sorted.count == 1 {
            let top = sorted[0].element
            baseColor = (top.averageR, top.averageG, top.averageB)
            // Derive secondary by darkening
            secondaryColor = (baseColor.r * 0.5, baseColor.g * 0.5, baseColor.b * 0.5)
        } else {
            // No colorful pixels — use a neutral dark gradient
            return GradientPalette(
                topColor: CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1),
                bottomColor: CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
            )
        }

        let top = clampedColor(r: baseColor.r, g: baseColor.g, b: baseColor.b, darken: 0.6)
        let bottom = clampedColor(r: secondaryColor.r, g: secondaryColor.g, b: secondaryColor.b, darken: 1.0)

        return GradientPalette(topColor: top, bottomColor: bottom)
    }

    // MARK: - Color math

    private static func clampedColor(r: Double, g: Double, b: Double, darken: Double) -> CGColor {
        var (h, s, bri) = rgbToHSB(r: r, g: g, b: b)
        s = min(s, 0.65)
        bri = min(max(bri, 0.18), 0.75)
        bri *= darken
        bri = min(max(bri, 0.08), 0.75)
        let (cr, cg, cb) = hsbToRGB(h: h, s: s, b: bri)
        return CGColor(red: cr, green: cg, blue: cb, alpha: 1)
    }

    static func rgbToHSB(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        let brightness = maxC
        let saturation = maxC > 0 ? delta / maxC : 0

        var hue: Double = 0
        if delta > 0 {
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return (hue, saturation, brightness)
    }

    static func hsbToRGB(h: Double, s: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        guard s > 0 else { return (b, b, b) }

        let h6 = h * 6
        let sector = Int(h6) % 6
        let f = h6 - Double(Int(h6))
        let p = b * (1 - s)
        let q = b * (1 - s * f)
        let t = b * (1 - s * (1 - f))

        switch sector {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }
}
