import AppKit
import CoreGraphics
import Foundation

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let scale = size / 1024.0

    // Outer drop shadow for the squircle
    ctx.saveGState()
    let shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
    ctx.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 32 * scale, color: shadowColor)

    // Standard macOS squircle bounds (824 x 824 centered in 1024)
    let squircleInset = 100.0 * scale
    let squircleSize = size - (squircleInset * 2.0)
    let squircleRect = CGRect(x: squircleInset, y: squircleInset, width: squircleSize, height: squircleSize)
    let cornerRadius = 185.0 * scale
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for interior rendering
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Background Gradient: Deep Midnight Indigo to Sapphire Blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.04, green: 0.08, blue: 0.18, alpha: 1.0).cgColor,
        NSColor(red: 0.08, green: 0.16, blue: 0.35, alpha: 1.0).cgColor,
        NSColor(red: 0.03, green: 0.28, blue: 0.52, alpha: 1.0).cgColor
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: size / 2, y: size - squircleInset),
            end: CGPoint(x: size / 2, y: squircleInset),
            options: []
        )
    }

    // Specular Top Rim Light
    let rimColors = [
        NSColor.white.withAlphaComponent(0.35).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let rimGradient = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            rimGradient,
            start: CGPoint(x: size / 2, y: size - squircleInset),
            end: CGPoint(x: size / 2, y: size - squircleInset - (120 * scale)),
            options: []
        )
    }

    // Outer Glow / Ambient Circular Flare
    let flareColors = [
        NSColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 0.28).cgColor,
        NSColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let flareGradient = CGGradient(colorsSpace: colorSpace, colors: flareColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            flareGradient,
            startCenter: CGPoint(x: size / 2, y: size / 2),
            startRadius: 0,
            endCenter: CGPoint(x: size / 2, y: size / 2),
            endRadius: 360 * scale,
            options: []
        )
    }

    // Radial Orbital Ring
    let ringRadius = 240.0 * scale
    let center = CGPoint(x: size / 2, y: size / 2)

    ctx.saveGState()
    ctx.setStrokeColor(NSColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.35).cgColor)
    ctx.setLineWidth(3.0 * scale)
    ctx.setLineDash(phase: 0, lengths: [10 * scale, 8 * scale])
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Orbital Nodes (8 colored conversion dots)
    let nodeColors: [NSColor] = [
        NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.2, green: 0.9, blue: 0.6, alpha: 1.0),
        NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0),
        NSColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0),
        NSColor(red: 0.9, green: 0.3, blue: 0.8, alpha: 1.0),
        NSColor(red: 0.5, green: 0.4, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.3, green: 1.0, blue: 0.9, alpha: 1.0)
    ]

    for (i, col) in nodeColors.enumerated() {
        let angle = (CGFloat(i) / 8.0) * (.pi * 2.0) - (.pi / 2.0)
        let nx = center.x + cos(angle) * ringRadius
        let ny = center.y + sin(angle) * ringRadius
        let nodeR = 14.0 * scale

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 12 * scale, color: col.withAlphaComponent(0.6).cgColor)
        ctx.setFillColor(col.cgColor)
        ctx.fillEllipse(in: CGRect(x: nx - nodeR, y: ny - nodeR, width: nodeR * 2, height: nodeR * 2))
        ctx.restoreGState()
    }

    // Inner Glass Hub Circle
    let hubRadius = 140.0 * scale
    ctx.saveGState()
    let hubRect = CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)
    ctx.setShadow(offset: CGSize(width: 0, height: -4 * scale), blur: 18 * scale, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.setFillColor(NSColor(red: 0.08, green: 0.14, blue: 0.28, alpha: 0.85).cgColor)
    ctx.fillEllipse(in: hubRect)

    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    ctx.setLineWidth(2.5 * scale)
    ctx.strokeEllipse(in: hubRect)
    ctx.restoreGState()

    // Central Icon: Dual Dynamic Conversion Arrows + Swift Flash
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24 * scale, color: NSColor(red: 0.2, green: 0.85, blue: 1.0, alpha: 0.8).cgColor)

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(16.0 * scale)
    ctx.setLineCap(.round)

    let arcR = 75.0 * scale
    ctx.addArc(center: center, radius: arcR, startAngle: 0.2, endAngle: .pi - 0.35, clockwise: false)
    ctx.strokePath()

    let head1Angle = .pi - 0.35
    let h1x = center.x + cos(head1Angle) * arcR
    let h1y = center.y + sin(head1Angle) * arcR
    let path1 = CGMutablePath()
    path1.move(to: CGPoint(x: h1x - (8 * scale), y: h1y + (22 * scale)))
    path1.addLine(to: CGPoint(x: h1x - (2 * scale), y: h1y))
    path1.addLine(to: CGPoint(x: h1x + (20 * scale), y: h1y + (10 * scale)))
    ctx.addPath(path1)
    ctx.strokePath()

    ctx.addArc(center: center, radius: arcR, startAngle: .pi + 0.2, endAngle: (.pi * 2) - 0.35, clockwise: false)
    ctx.strokePath()

    let head2Angle = (.pi * 2) - 0.35
    let h2x = center.x + cos(head2Angle) * arcR
    let h2y = center.y + sin(head2Angle) * arcR
    let path2 = CGMutablePath()
    path2.move(to: CGPoint(x: h2x + (8 * scale), y: h2y - (22 * scale)))
    path2.addLine(to: CGPoint(x: h2x + (2 * scale), y: h2y))
    path2.addLine(to: CGPoint(x: h2x - (20 * scale), y: h2y - (10 * scale)))
    ctx.addPath(path2)
    ctx.strokePath()

    let corePath = CGMutablePath()
    corePath.move(to: CGPoint(x: center.x + (6 * scale), y: center.y + (38 * scale)))
    corePath.addLine(to: CGPoint(x: center.x - (16 * scale), y: center.y + (2 * scale)))
    corePath.addLine(to: CGPoint(x: center.x - (2 * scale), y: center.y + (2 * scale)))
    corePath.addLine(to: CGPoint(x: center.x - (8 * scale), y: center.y - (38 * scale)))
    corePath.addLine(to: CGPoint(x: center.x + (16 * scale), y: center.y - (2 * scale)))
    corePath.addLine(to: CGPoint(x: center.x + (2 * scale), y: center.y - (2 * scale)))
    corePath.closeSubpath()

    ctx.setFillColor(NSColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0).cgColor)
    ctx.addPath(corePath)
    ctx.fillPath()

    ctx.restoreGState()
    ctx.restoreGState()
}

func saveBitmapPNG(pixels: Int, path: String) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: pixels * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create context for \(pixels)x\(pixels)")
        return
    }

    drawIcon(in: ctx, size: CGFloat(pixels))

    guard let cgImage = ctx.makeImage() else {
        print("Failed to make image for \(pixels)x\(pixels)")
        return
    }

    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        print("Failed to create destination for \(path)")
        return
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    if CGImageDestinationFinalize(destination) {
        print("Saved exact \(pixels)x\(pixels) to \(path)")
    } else {
        print("Failed to finalize PNG for \(path)")
    }
}

let appIconDir = "Fettle/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: appIconDir, withIntermediateDirectories: true)

let sizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

var imagesJSON: [[String: String]] = []

for entry in sizes {
    let px = entry.size * entry.scale
    let fileName = "icon_\(entry.size)x\(entry.size)@\(entry.scale)x.png"
    let filePath = "\(appIconDir)/\(fileName)"
    saveBitmapPNG(pixels: px, path: filePath)

    imagesJSON.append([
        "idiom": "mac",
        "scale": "\(entry.scale)x",
        "size": "\(entry.size)x\(entry.size)",
        "filename": fileName
    ])
}

let contents: [String: Any] = [
    "images": imagesJSON,
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

if let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted]) {
    try? data.write(to: URL(fileURLWithPath: "\(appIconDir)/Contents.json"))
    print("Updated Contents.json")
}
