import AppKit
import Foundation

// Generates the PhotoDrift app icon at every macOS slot size, plus the matching
// Contents.json. All geometry is expressed on Apple's 1024pt icon canvas and scaled down.
//
//   swift Tools/GenerateAppIcon.swift PhotoDrift/Assets.xcassets/AppIcon.appiconset
//
// Everything tunable lives in `palette` and the card layout block in renderIcon().

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

struct Palette {
    /// Background ramp, kept within one hue family — a multi-hue sweep reads as generic.
    let background: [(CGFloat, UInt32)]
    /// Front card stock. Warm off-white, not pure white.
    let card: UInt32
    let skyTop: UInt32
    let skyBottom: UInt32
    let sun: UInt32
    let ridgeBack: UInt32
    let ridgeFront: UInt32
    /// Top-edge highlight strength. Keep low; heavy gloss cheapens the icon.
    let sheen: CGFloat
}

let palette = Palette(
    background: [(0.0, 0x2E3A4D), (1.0, 0x151C27)],
    card: 0xF7F4EF,
    skyTop: 0xE8DFD2,
    skyBottom: 0xCBBFAE,
    sun: 0xE0A33C,
    ridgeBack: 0x5A6B84,
    ridgeFront: 0x33415A,
    sheen: 0.10
)

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// One photo card: rounded rect of card stock, optionally carrying the landscape motif.
func drawCard(
    _ ctx: CGContext,
    center: CGPoint,
    size: CGSize,
    rotation: CGFloat,
    fill: NSColor,
    motif: Bool,
    shadowAlpha: CGFloat
) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation * .pi / 180)

    let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    let radius = size.width * 0.11
    let path = roundedRect(rect, radius)

    ctx.setShadow(
        offset: CGSize(width: 0, height: -size.height * 0.045),
        blur: size.width * 0.10,
        color: srgb(0x000000, shadowAlpha).cgColor
    )
    ctx.setFillColor(fill.cgColor)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    guard motif else {
        ctx.restoreGState()
        return
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let inset = rect.insetBy(dx: size.width * 0.055, dy: size.height * 0.055)
    ctx.saveGState()
    ctx.addPath(roundedRect(inset, radius * 0.62))
    ctx.clip()

    if let sky = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [srgb(palette.skyTop).cgColor, srgb(palette.skyBottom).cgColor] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            sky,
            start: CGPoint(x: inset.midX, y: inset.maxY),
            end: CGPoint(x: inset.midX, y: inset.minY),
            options: []
        )
    }

    let sunR = inset.width * 0.115
    ctx.setFillColor(srgb(palette.sun).cgColor)
    ctx.fillEllipse(in: CGRect(
        x: inset.minX + inset.width * 0.70 - sunR,
        y: inset.minY + inset.height * 0.70 - sunR,
        width: sunR * 2,
        height: sunR * 2
    ))

    let back = CGMutablePath()
    back.move(to: CGPoint(x: inset.minX, y: inset.minY))
    back.addLine(to: CGPoint(x: inset.minX + inset.width * 0.34, y: inset.minY + inset.height * 0.62))
    back.addLine(to: CGPoint(x: inset.minX + inset.width * 0.63, y: inset.minY))
    back.closeSubpath()
    ctx.setFillColor(srgb(palette.ridgeBack).cgColor)
    ctx.addPath(back)
    ctx.fillPath()

    let front = CGMutablePath()
    front.move(to: CGPoint(x: inset.minX + inset.width * 0.30, y: inset.minY))
    front.addLine(to: CGPoint(x: inset.minX + inset.width * 0.66, y: inset.minY + inset.height * 0.46))
    front.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
    front.closeSubpath()
    ctx.setFillColor(srgb(palette.ridgeFront).cgColor)
    ctx.addPath(front)
    ctx.fillPath()

    ctx.restoreGState()
    ctx.restoreGState()
    ctx.restoreGState()
}

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024.0, y: CGFloat(pixels) / 1024.0)

    // Squircle body: 824×824 centered on the 1024 canvas, per Apple's macOS icon grid.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = roundedRect(body, 185.4)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 42, color: srgb(0x000000, 0.30).cgColor)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(bodyPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    if let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: palette.background.map { srgb($0.1).cgColor } as CFArray,
        locations: palette.background.map { $0.0 }
    ) {
        ctx.drawLinearGradient(
            bg,
            start: CGPoint(x: body.minX, y: body.maxY),
            end: CGPoint(x: body.maxX, y: body.minY),
            options: []
        )
    }

    if palette.sheen > 0, let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [srgb(0xFFFFFF, palette.sheen).cgColor, srgb(0xFFFFFF, 0).cgColor] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            sheen,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.midY),
            options: []
        )
    }
    ctx.restoreGState()

    // Cascade in one direction so the deck reads as a stack rather than a symmetric fan.
    let cardW: CGFloat = 398
    let cardH: CGFloat = 322
    let center = CGPoint(x: 536, y: 486)

    drawCard(
        ctx,
        center: CGPoint(x: center.x - 92, y: center.y + 52),
        size: CGSize(width: cardW * 0.90, height: cardH * 0.90),
        rotation: 17,
        fill: srgb(palette.card, 0.50),
        motif: false,
        shadowAlpha: 0.26
    )
    drawCard(
        ctx,
        center: CGPoint(x: center.x - 46, y: center.y + 26),
        size: CGSize(width: cardW * 0.95, height: cardH * 0.95),
        rotation: 8,
        fill: srgb(palette.card, 0.78),
        motif: false,
        shadowAlpha: 0.30
    )
    drawCard(
        ctx,
        center: center,
        size: CGSize(width: cardW, height: cardH),
        rotation: 0,
        fill: srgb(palette.card),
        motif: true,
        shadowAlpha: 0.38
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// slot label → pixel dimension
let slots: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

var cache: [Int: Data] = [:]
for slot in slots {
    let png: Data
    if let hit = cache[slot.pixels] {
        png = hit
    } else {
        guard let data = renderIcon(pixels: slot.pixels).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to encode \(slot.name)\n".utf8))
            exit(1)
        }
        cache[slot.pixels] = data
        png = data
    }
    try png.write(to: outDir.appendingPathComponent("\(slot.name).png"))
    print("wrote \(slot.name).png (\(slot.pixels)px, \(png.count) bytes)")
}

var entries: [String] = []
for slot in slots {
    let base = slot.name
        .replacingOccurrences(of: "icon_", with: "")
        .replacingOccurrences(of: "@2x", with: "")
    let scale = slot.name.hasSuffix("@2x") ? "2" : "1"
    entries.append("""
        {
          "filename" : "\(slot.name).png",
          "idiom" : "mac",
          "scale" : "\(scale)x",
          "size" : "\(base)"
        }
    """)
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
