#!/usr/bin/env swift
// Draws the app icon: a paper sheet tilted slightly on an indigo ground, carrying three pastel regions (structure,
// input and action families) with an indigo selection ring and handles on one. Writes every size of the asset
// catalog's AppIcon set and its Contents.json. Running it again gives identical files.
//
//   swift scripts/render-app-icon.swift [output folder]
//
// The folder defaults to InterfaceDescriber/Assets.xcassets/AppIcon.appiconset. Colors are PaperPalette.light's
// (Packages/DescriberCore/Sources/DescriberCore/Style/PaperPalette.swift); change them together.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let accent = color(0x4A4FD1)
let accentDeep = color(0x3A3FB8)
let sheet = color(0xFFFDF9)
let sheetBorder = color(0xDDD5C8)
let card = color(0xFFFFFF)
let regions: [(frame: CGRect, fill: CGColor, border: CGColor)] = [
    // Structure: a header across the top.
    (CGRect(x: 60, y: 70, width: 440, height: 150), color(0xEFECF9), color(0xB9AEE6)),
    // Input: a field in the middle.
    (CGRect(x: 60, y: 260, width: 440, height: 110), color(0xDDF1E8), color(0x8CC9AE)),
    // Action: a button near the bottom, which is selected.
    (CGRect(x: 60, y: 430, width: 440, height: 120), color(0xFBE1CC), color(0xE3A97A)),
]
let selected = 2
let sheetSize = CGSize(width: 560, height: 640)

/// Draws the icon in a 1024 × 1024 space with the origin at the top left.
func drawIcon(in context: CGContext) {
    // The ground: the macOS icon shape, an indigo rounded square with a soft shadow.
    let ground = CGRect(x: 100, y: 100, width: 824, height: 824)
    let groundPath = CGPath(roundedRect: ground, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: color(0x000000, alpha: 0.25))
    context.addPath(groundPath)
    context.setFillColor(accent)
    context.drawPath(using: .fill)
    context.restoreGState()
    // A deeper band at the bottom of the ground, for depth.
    // (Masked with destination-in rather than clipped: the script runs in the interpreter, which can't find the
    // CoreGraphics overlay's clip and fill functions on the CI runner.)
    context.saveGState()
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [accent, accentDeep] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.setBlendMode(.destinationIn)
    context.addPath(groundPath)
    context.drawPath(using: .fill)
    context.endTransparencyLayer()
    context.restoreGState()

    // The sheet, tilted a little, with its shadow.
    context.saveGState()
    context.translateBy(x: 512, y: 530)
    context.rotate(by: -6 * .pi / 180)
    context.translateBy(x: -sheetSize.width / 2, y: -sheetSize.height / 2)
    let sheetRect = CGRect(origin: .zero, size: sheetSize)
    let sheetPath = CGPath(roundedRect: sheetRect, cornerWidth: 44, cornerHeight: 44, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: color(0x1F1C19, alpha: 0.35))
    context.addPath(sheetPath)
    context.setFillColor(sheet)
    context.drawPath(using: .fill)
    context.restoreGState()
    context.addPath(sheetPath)
    context.setStrokeColor(sheetBorder)
    context.setLineWidth(4)
    context.strokePath()

    for (index, region) in regions.enumerated() {
        let path = CGPath(roundedRect: region.frame, cornerWidth: 22, cornerHeight: 22, transform: nil)
        context.addPath(path)
        context.setFillColor(region.fill)
        context.drawPath(using: .fill)
        context.addPath(path)
        context.setStrokeColor(index == selected ? accent : region.border)
        context.setLineWidth(index == selected ? 14 : 6)
        context.strokePath()
    }
    // Round handles on the selected region's corners.
    let frame = regions[selected].frame
    for corner in [
        CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
        CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY),
    ] {
        let handle = CGRect(x: corner.x - 22, y: corner.y - 22, width: 44, height: 44)
        context.setFillColor(card)
        context.fillEllipse(in: handle)
        context.setStrokeColor(accent)
        context.setLineWidth(9)
        context.strokeEllipse(in: handle.insetBy(dx: 4.5, dy: 4.5))
    }
    context.restoreGState()
}

/// The icon as PNG data, `pixels` on a side.
func png(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    // Top-left origin, 1024 units across.
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
    drawIcon(in: context)
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't encode a \(pixels) px icon") }
    return data as Data
}

let arguments = CommandLine.arguments.dropFirst()
let folder = URL(
    fileURLWithPath: arguments.first ?? "InterfaceDescriber/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try png(pixels: size * scale).write(to: folder.appendingPathComponent(name))
        images.append(
            """
                {
                  "filename" : "\(name)",
                  "idiom" : "mac",
                  "scale" : "\(scale)x",
                  "size" : "\(size)x\(size)"
                }
            """)
    }
}
let contents = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(folder.path)")
