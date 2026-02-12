import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoDrift

// MARK: - Test helpers

private func makeTestJPEG(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = ctx.makeImage() else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

// MARK: - RGB ↔ HSB conversion

struct RGBtoHSBTests {
    @Test func pureRed() {
        let (h, s, b) = PaletteExtractor.rgbToHSB(r: 1, g: 0, b: 0)
        #expect(abs(h - 0.0) < 0.01)
        #expect(abs(s - 1.0) < 0.01)
        #expect(abs(b - 1.0) < 0.01)
    }

    @Test func pureGreen() {
        let (h, s, b) = PaletteExtractor.rgbToHSB(r: 0, g: 1, b: 0)
        #expect(abs(h - 0.333) < 0.01)
        #expect(abs(s - 1.0) < 0.01)
        #expect(abs(b - 1.0) < 0.01)
    }

    @Test func pureBlue() {
        let (h, s, b) = PaletteExtractor.rgbToHSB(r: 0, g: 0, b: 1)
        #expect(abs(h - 0.666) < 0.01)
        #expect(abs(s - 1.0) < 0.01)
        #expect(abs(b - 1.0) < 0.01)
    }

    @Test func white() {
        let (_, s, b) = PaletteExtractor.rgbToHSB(r: 1, g: 1, b: 1)
        #expect(abs(s - 0.0) < 0.01)
        #expect(abs(b - 1.0) < 0.01)
    }

    @Test func black() {
        let (_, s, b) = PaletteExtractor.rgbToHSB(r: 0, g: 0, b: 0)
        #expect(abs(s - 0.0) < 0.01)
        #expect(abs(b - 0.0) < 0.01)
    }

    @Test func roundTrip() {
        let inputs: [(Double, Double, Double)] = [
            (0.8, 0.3, 0.5),
            (0.2, 0.7, 0.9),
            (0.0, 1.0, 0.5),
            (1.0, 1.0, 1.0),
        ]
        for (r, g, b) in inputs {
            let (h, s, bri) = PaletteExtractor.rgbToHSB(r: r, g: g, b: b)
            let (rr, rg, rb) = PaletteExtractor.hsbToRGB(h: h, s: s, b: bri)
            #expect(abs(rr - r) < 0.01)
            #expect(abs(rg - g) < 0.01)
            #expect(abs(rb - b) < 0.01)
        }
    }
}

// MARK: - Aspect-fit geometry

struct AspectFitTests {
    @Test func landscapeImageInLandscapeScreen() {
        let rect = GradientRenderer.aspectFitRect(
            imageSize: CGSize(width: 2000, height: 1000),
            bounds: CGSize(width: 2560, height: 1600)
        )
        // Image aspect 2:1, screen aspect 1.6:1 → height-limited
        #expect(rect.width <= 2560)
        #expect(rect.height <= 1600)
        // Should be centered
        #expect(abs(rect.midX - 1280) < 1)
        #expect(abs(rect.midY - 800) < 1)
    }

    @Test func portraitImageInLandscapeScreen() {
        let rect = GradientRenderer.aspectFitRect(
            imageSize: CGSize(width: 1000, height: 2000),
            bounds: CGSize(width: 2560, height: 1600)
        )
        // Height-limited: scale = 1600/2000 = 0.8 → width = 800
        #expect(abs(rect.width - 800) < 1)
        #expect(abs(rect.height - 1600) < 1)
        #expect(abs(rect.midX - 1280) < 1)
    }

    @Test func exactFit() {
        let rect = GradientRenderer.aspectFitRect(
            imageSize: CGSize(width: 2560, height: 1600),
            bounds: CGSize(width: 2560, height: 1600)
        )
        #expect(abs(rect.width - 2560) < 1)
        #expect(abs(rect.height - 1600) < 1)
        #expect(abs(rect.origin.x) < 1)
        #expect(abs(rect.origin.y) < 1)
    }

    @Test func zeroImageSize() {
        let rect = GradientRenderer.aspectFitRect(
            imageSize: CGSize(width: 0, height: 0),
            bounds: CGSize(width: 2560, height: 1600)
        )
        #expect(rect.width == 2560)
        #expect(rect.height == 1600)
    }
}

// MARK: - Needs gradient matte

struct NeedsGradientMatteTests {
    @Test func portraitImageNeedsMatte() {
        let needs = GradientRenderer.needsGradientMatte(
            imageSize: CGSize(width: 1000, height: 2000),
            screenSize: CGSize(width: 2560, height: 1600)
        )
        #expect(needs == true)
    }

    @Test func exactFitDoesNotNeedMatte() {
        let needs = GradientRenderer.needsGradientMatte(
            imageSize: CGSize(width: 2560, height: 1600),
            screenSize: CGSize(width: 2560, height: 1600)
        )
        #expect(needs == false)
    }

    @Test func proportionalFitDoesNotNeedMatte() {
        // Same aspect ratio, different size
        let needs = GradientRenderer.needsGradientMatte(
            imageSize: CGSize(width: 1280, height: 800),
            screenSize: CGSize(width: 2560, height: 1600)
        )
        #expect(needs == false)
    }
}

// MARK: - Palette extraction

struct PaletteExtractorTests {
    @Test func extractsFromRedImage() {
        guard let jpeg = makeTestJPEG(width: 100, height: 100, r: 0.9, g: 0.1, b: 0.1) else {
            Issue.record("Failed to create test JPEG")
            return
        }
        let palette = PaletteExtractor.extract(from: jpeg)
        #expect(palette != nil)
    }

    @Test func extractsFromGreenImage() {
        guard let jpeg = makeTestJPEG(width: 100, height: 100, r: 0.1, g: 0.8, b: 0.1) else {
            Issue.record("Failed to create test JPEG")
            return
        }
        let palette = PaletteExtractor.extract(from: jpeg)
        #expect(palette != nil)
    }

    @Test func handlesGreyscaleImage() {
        // A mid-grey image — all pixels will be filtered out (low saturation)
        // Should still return a palette (the neutral fallback)
        guard let jpeg = makeTestJPEG(width: 100, height: 100, r: 0.5, g: 0.5, b: 0.5) else {
            Issue.record("Failed to create test JPEG")
            return
        }
        let palette = PaletteExtractor.extract(from: jpeg)
        #expect(palette != nil)
    }

    @Test func returnsNilForInvalidData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        let palette = PaletteExtractor.extract(from: garbage)
        #expect(palette == nil)
    }
}

// MARK: - Gradient compositing

struct GradientRendererTests {
    @Test func compositesPortraitImage() {
        guard let jpeg = makeTestJPEG(width: 100, height: 200, r: 0.6, g: 0.2, b: 0.2) else {
            Issue.record("Failed to create test JPEG")
            return
        }
        let screenSize = CGSize(width: 800, height: 600)
        let result = GradientRenderer.composite(imageData: jpeg, screenSize: screenSize)
        #expect(result != nil)

        // Verify the output is a valid PNG at the right size
        if let data = result,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            #expect(image.width == 800)
            #expect(image.height == 600)
        } else {
            Issue.record("Output is not a valid image")
        }
    }

    @Test func compositesLandscapeImage() {
        guard let jpeg = makeTestJPEG(width: 200, height: 100, r: 0.2, g: 0.6, b: 0.2) else {
            Issue.record("Failed to create test JPEG")
            return
        }
        let screenSize = CGSize(width: 800, height: 600)
        let result = GradientRenderer.composite(imageData: jpeg, screenSize: screenSize)
        #expect(result != nil)
    }

    @Test func animatedGradientFramesDifferAcrossPhases() {
        guard let jpeg = makeTestJPEG(width: 100, height: 200, r: 0.3, g: 0.4, b: 0.8) else {
            Issue.record("Failed to create test JPEG")
            return
        }
        let screenSize = CGSize(width: 800, height: 600)
        let phaseA = GradientRenderer.composite(imageData: jpeg, screenSize: screenSize, phase: 0.0)
        let phaseB = GradientRenderer.composite(imageData: jpeg, screenSize: screenSize, phase: 0.5)
        #expect(phaseA != nil)
        #expect(phaseB != nil)
        #expect(phaseA != phaseB)
    }

    @Test func returnsNilForInvalidData() {
        let garbage = Data([0xFF, 0xFE, 0xFD])
        let result = GradientRenderer.composite(imageData: garbage, screenSize: CGSize(width: 800, height: 600))
        #expect(result == nil)
    }

    @Test func returnsNilForZeroScreenSize() {
        guard let jpeg = makeTestJPEG(width: 100, height: 100, r: 0.5, g: 0.5, b: 0.8) else {
            Issue.record("Failed to create test JPEG")
            return
        }
        let result = GradientRenderer.composite(imageData: jpeg, screenSize: CGSize(width: 0, height: 0))
        #expect(result == nil)
    }
}
