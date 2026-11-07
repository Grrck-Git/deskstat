// From the repository root, generate an iconset with
// swift Assets/GenerateIcon.swift /tmp/DeskStat.iconset
// Then package it with iconutil -c icns /tmp/DeskStat.iconset -o Assets/AppIcon.icns
import AppKit

func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                            xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(white: 0.12, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1),
                              ending: NSColor(srgbRed: 0.24, green: 0.27, blue: 0.31, alpha: 1))!
    gradient.draw(in: tile, angle: 90)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    NSColor(white: 0.97, alpha: 1).setStroke()
    let screen = NSBezierPath(roundedRect: NSRect(x: 208, y: 296, width: 608, height: 488),
                              xRadius: 70, yRadius: 70)
    screen.lineWidth = 34
    screen.stroke()

    let widgets = [NSRect(x: 276, y: 578, width: 192, height: 136),
                   NSRect(x: 276, y: 364, width: 192, height: 146),
                   NSRect(x: 532, y: 364, width: 216, height: 350)]
    for rect in widgets {
        let widget = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        widget.lineWidth = 24
        widget.stroke()
    }

    let stand = NSBezierPath()
    stand.lineWidth = 34
    stand.lineCapStyle = .round
    stand.move(to: NSPoint(x: 512, y: 296))
    stand.line(to: NSPoint(x: 512, y: 202))
    stand.move(to: NSPoint(x: 372, y: 202))
    stand.line(to: NSPoint(x: 652, y: 202))
    stand.stroke()
}

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/DeskStat.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(points)x\(points)\(suffix).png"
        try render(pixels: points * scale).write(to: destination.appendingPathComponent(name))
    }
}
print("Generated the ten macOS icon representations.")
