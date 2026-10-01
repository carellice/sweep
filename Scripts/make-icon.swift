// Draws the app icon and writes it as a 1024px PNG.
// Usage: swift Scripts/make-icon.swift <output.png>
import AppKit

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func withShadow(_ color: NSColor, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// Four-pointed sparkle with concave sides.
func sparkle(at center: NSPoint, radius r: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let tips = [NSPoint(x: 0, y: r), NSPoint(x: r, y: 0), NSPoint(x: 0, y: -r), NSPoint(x: -r, y: 0)]
    path.move(to: NSPoint(x: center.x + tips[3].x, y: center.y + tips[3].y))
    for tip in tips {
        let end = NSPoint(x: center.x + tip.x, y: center.y + tip.y)
        path.curve(to: end, controlPoint1: center, controlPoint2: center)
    }
    path.close()
    return path
}

let side = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// MARK: Tile — macOS icon grid: 824pt rounded square centred in the 1024pt canvas.

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

withShadow(rgb(0x000000, 0.35), blur: 28, y: -12) {
    rgb(0x1B2A6B).setFill()
    shape.fill()
}
NSGradient(colors: [rgb(0x5B7CFA), rgb(0x3A3FD4), rgb(0x241B7A)])!.draw(in: shape, angle: -70)

NSGraphicsContext.saveGraphicsState()
shape.addClip()
// Soft glow on the floor where the broom sweeps, and a light sheen from the top.
NSGradient(starting: rgb(0x7FE3FF, 0.55), ending: rgb(0x7FE3FF, 0))!
    .draw(fromCenter: NSPoint(x: 570, y: 170), radius: 0, toCenter: NSPoint(x: 570, y: 170), radius: 470, options: [])
NSGradient(starting: rgb(0xFFFFFF, 0.22), ending: rgb(0xFFFFFF, 0))!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

// Sweep trail: the arc the bristles have just cleaned.
let trail = NSBezierPath()
trail.move(to: NSPoint(x: 330, y: 250))
trail.curve(to: NSPoint(x: 800, y: 300), controlPoint1: NSPoint(x: 480, y: 170), controlPoint2: NSPoint(x: 680, y: 190))
trail.lineWidth = 26
trail.lineCapStyle = .round
rgb(0xFFFFFF, 0.28).setStroke()
trail.stroke()
NSGraphicsContext.restoreGraphicsState()

// MARK: Broom — drawn upright around the origin, then tilted.

NSGraphicsContext.saveGraphicsState()
let tilt = NSAffineTransform()
tilt.translateX(by: 500, yBy: 530)
tilt.rotate(byDegrees: -38)
tilt.concat()

withShadow(rgb(0x0B0A3A, 0.45), blur: 30, y: -18) {
    // Handle
    let handle = NSBezierPath(roundedRect: NSRect(x: -19, y: 40, width: 38, height: 400), xRadius: 19, yRadius: 19)
    NSGradient(starting: rgb(0xFFFFFF), ending: rgb(0xD5DCFF))!.draw(in: handle, angle: 0)

    // Bristles
    let bristles = NSBezierPath()
    bristles.move(to: NSPoint(x: -74, y: 30))
    bristles.line(to: NSPoint(x: 74, y: 30))
    bristles.curve(to: NSPoint(x: 168, y: -236), controlPoint1: NSPoint(x: 96, y: -60), controlPoint2: NSPoint(x: 150, y: -150))
    bristles.curve(to: NSPoint(x: -168, y: -236), controlPoint1: NSPoint(x: 70, y: -272), controlPoint2: NSPoint(x: -70, y: -272))
    bristles.curve(to: NSPoint(x: -74, y: 30), controlPoint1: NSPoint(x: -150, y: -150), controlPoint2: NSPoint(x: -96, y: -60))
    bristles.close()
    NSGradient(starting: rgb(0xFFE27A), ending: rgb(0xFF9F2E))!.draw(in: bristles, angle: -90)

    // Strands
    NSGraphicsContext.saveGraphicsState()
    bristles.addClip()
    rgb(0xC96A10, 0.45).setStroke()
    for i in -3...3 {
        let strand = NSBezierPath()
        let t = CGFloat(i) / 3
        strand.move(to: NSPoint(x: t * 52, y: -20))
        strand.curve(
            to: NSPoint(x: t * 138, y: -270),
            controlPoint1: NSPoint(x: t * 70, y: -100), controlPoint2: NSPoint(x: t * 120, y: -190))
        strand.lineWidth = 7
        strand.lineCapStyle = .round
        strand.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Binding
    let band = NSBezierPath(roundedRect: NSRect(x: -86, y: 6, width: 172, height: 62), xRadius: 22, yRadius: 22)
    NSGradient(starting: rgb(0xFF6B6B), ending: rgb(0xE23D5B))!.draw(in: band, angle: -90)
}
rgb(0xFFFFFF, 0.35).setFill()
NSBezierPath(roundedRect: NSRect(x: -70, y: 46, width: 140, height: 10), xRadius: 5, yRadius: 5).fill()
NSGraphicsContext.restoreGraphicsState()

// MARK: Sparkles

withShadow(rgb(0xFFFFFF, 0.8), blur: 24, y: 0) {
    rgb(0xFFFFFF).setFill()
    sparkle(at: NSPoint(x: 712, y: 372), radius: 78).fill()
    sparkle(at: NSPoint(x: 812, y: 508), radius: 40).fill()
    sparkle(at: NSPoint(x: 596, y: 262), radius: 30).fill()
}

NSGraphicsContext.current?.flushGraphics()
try rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
