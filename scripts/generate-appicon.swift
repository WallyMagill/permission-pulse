// Generates the Permission Pulse app icon: a brand-gradient squircle,
// white shield, and pulse line, rendered at every AppIcon.appiconset size.
//
// Usage: swift scripts/generate-appicon.swift <output-directory>
//
// Deterministic — same input produces byte-identical geometry. The brand
// gradient stops mirror PPColor.brandGradient in Palette.swift.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

// PPColor.brandGradient stops (Palette.swift)
let brandLight = CGColor(srgbRed: 0.37, green: 0.55, blue: 1.0, alpha: 1)
let brandDark = CGColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift generate-appicon.swift <output-directory>\n".utf8))
    exit(2)
}
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// MARK: - Paths (y-up, 1024pt canvas)

// Apple's macOS icon grid: an 824pt rounded square centered in 1024,
// corner radius ~22.5% of the square edge.
func squirclePath() -> CGPath {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 824 * 0.225
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func shieldPath() -> CGPath {
    let path = CGMutablePath()
    let cx: CGFloat = 512
    let halfWidth: CGFloat = 250
    let topY: CGFloat = 756
    let bottomY: CGFloat = 240
    let cornerRadius: CGFloat = 60
    let sideBottom: CGFloat = 566  // sides run straight down to here

    // Rounded top corners, straight upper sides, then a taper to a rounded
    // bottom point — the classic heraldic shield silhouette.
    path.move(to: CGPoint(x: cx - halfWidth, y: topY - cornerRadius))
    path.addQuadCurve(
        to: CGPoint(x: cx - halfWidth + cornerRadius, y: topY),
        control: CGPoint(x: cx - halfWidth, y: topY)
    )
    path.addLine(to: CGPoint(x: cx + halfWidth - cornerRadius, y: topY))
    path.addQuadCurve(
        to: CGPoint(x: cx + halfWidth, y: topY - cornerRadius),
        control: CGPoint(x: cx + halfWidth, y: topY)
    )
    // Symmetric cubics meeting at the bottom center with a horizontal
    // tangent (control2/control1 share the endpoint's y) — no visible kink.
    path.addLine(to: CGPoint(x: cx + halfWidth, y: sideBottom))
    path.addCurve(
        to: CGPoint(x: cx, y: bottomY),
        control1: CGPoint(x: cx + halfWidth, y: 396),
        control2: CGPoint(x: cx + 128, y: bottomY)
    )
    path.addCurve(
        to: CGPoint(x: cx - halfWidth, y: sideBottom),
        control1: CGPoint(x: cx - 128, y: bottomY),
        control2: CGPoint(x: cx - halfWidth, y: 396)
    )
    path.closeSubpath()
    return path
}

func pulsePath() -> CGPath {
    // EKG trace across the shield's midline: flat lead-in, shallow dip,
    // tall spike, undershoot, flat lead-out. Spans past the shield edges;
    // the shield clip trims the ends flush.
    let baseline: CGFloat = 508
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 230, y: baseline))
    path.addLine(to: CGPoint(x: 410, y: baseline))
    path.addLine(to: CGPoint(x: 452, y: baseline - 56))
    path.addLine(to: CGPoint(x: 516, y: baseline + 158))
    path.addLine(to: CGPoint(x: 578, y: baseline - 100))
    path.addLine(to: CGPoint(x: 618, y: baseline))
    path.addLine(to: CGPoint(x: 794, y: baseline))
    return path
}

// MARK: - Master render

func renderMaster() -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas),
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Gradient-filled squircle, top-leading light to bottom-trailing dark,
    // matching PPColor.brandGradient's direction.
    context.saveGState()
    context.addPath(squirclePath())
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [brandLight, brandDark] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 100, y: 924),
        end: CGPoint(x: 924, y: 100),
        options: []
    )
    context.restoreGState()

    // White shield with a soft shadow so it lifts off the gradient.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -12), blur: 36,
        color: CGColor(srgbRed: 0, green: 0.1, blue: 0.35, alpha: 0.30)
    )
    context.addPath(shieldPath())
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Pulse line, clipped to the shield so the trace runs edge to edge.
    context.saveGState()
    context.addPath(shieldPath())
    context.clip()
    context.addPath(pulsePath())
    context.setStrokeColor(brandDark)
    context.setLineWidth(46)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()!
}

// MARK: - Output

func write(_ image: CGImage, pixels: Int, to url: URL) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let scaled = context.makeImage()!

    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        FileHandle.standardError.write(Data("cannot create \(url.path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, scaled, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("cannot write \(url.path)\n".utf8))
        exit(1)
    }
}

let master = renderMaster()
// (points, scale) for every slot declared in AppIcon.appiconset/Contents.json.
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in slots {
    let suffix = scale == 2 ? "@2x" : ""
    let url = outputDir.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    write(master, pixels: points * scale, to: url)
    print("wrote \(url.lastPathComponent) (\(points * scale)px)")
}
