import AppKit
import Foundation

// A quiet document icon: a sage tile, a warm page, a Markdown heading mark.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let iconset = root.appendingPathComponent(".build/DambakMD.iconset")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: alpha)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func iconPNG(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    cg.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let tile = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 225, yRadius: 225)
    NSGradient(starting: color(0x71877B), ending: color(0x415B51))!.draw(in: tile, angle: 90)
    color(0xFFFFFF, alpha: 0.15).setStroke()
    tile.lineWidth = 9
    tile.stroke()

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x1B3028, alpha: 0.25)
    shadow.shadowBlurRadius = 45
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.set()
    rect(216, 150, 592, 724, 54, fill: color(0xF9F7EF))
    NSGraphicsContext.restoreGraphicsState()

    // Folded top-right corner.
    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 683, y: 874))
    fold.line(to: NSPoint(x: 808, y: 749))
    fold.line(to: NSPoint(x: 808, y: 817))
    fold.curve(to: NSPoint(x: 751, y: 874), controlPoint1: NSPoint(x: 808, y: 849), controlPoint2: NSPoint(x: 782, y: 874))
    fold.close()
    color(0xDDE5DA).setFill()
    fold.fill()
    let crease = NSBezierPath()
    crease.move(to: NSPoint(x: 683, y: 874))
    crease.line(to: NSPoint(x: 683, y: 793))
    crease.curve(to: NSPoint(x: 722, y: 749), controlPoint1: NSPoint(x: 683, y: 767), controlPoint2: NSPoint(x: 698, y: 749))
    crease.line(to: NSPoint(x: 808, y: 749))
    color(0xE7EDE5).setFill()
    crease.fill()

    let mark = NSAttributedString(string: "#", attributes: [
        .font: NSFont.systemFont(ofSize: 246, weight: .heavy),
        .foregroundColor: color(0x344D43)
    ])
    mark.draw(at: NSPoint(x: 303, y: 481))
    rect(531, 627, 143, 25, 12, fill: color(0x526D5E))
    rect(531, 575, 102, 25, 12, fill: color(0x7F9A88))
    rect(304, 425, 392, 22, 11, fill: color(0xB9C8B8))
    rect(304, 373, 333, 22, 11, fill: color(0xB9C8B8))
    rect(304, 321, 368, 22, 11, fill: color(0xB9C8B8))

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in sizes {
    try iconPNG(size: size).write(to: iconset.appendingPathComponent(name))
}
try iconPNG(size: 1024).write(to: assets.appendingPathComponent("DambakMD-preview.png"))
print("Generated \(iconset.path) and 1024px preview")
