// Renders Resources/dmg-background.tiff: the installer window background (660×440 pt: the content area of a 660×500 window,
// with a 2× version inside the TIFF). Run: swift Tools/make-dmg-background.swift
import AppKit

let size = NSSize(width: 660, height: 440)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(origin: .zero, size: size)

    // Night background with the icon's pink, violet and blue glow.
    NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1).setFill()
    bounds.fill()
    func glow(_ color: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        NSGradient(colors: [color, color.withAlphaComponent(0)])!
            .draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
    }
    glow(NSColor(red: 0.98, green: 0.36, blue: 0.55, alpha: 0.45), 120, 40, 330)
    glow(NSColor(red: 0.35, green: 0.45, blue: 1.0, alpha: 0.42), 560, 70, 330)
    glow(NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 0.18), 330, -40, 240)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    func text(_ string: String, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ]
        (string as NSString).draw(in: NSRect(x: 30, y: y, width: size == 0 ? 0 : 600, height: size * 2.6), withAttributes: attributes)
    }
    text("Drag Brimtune into Applications", 352, size: 20, weight: .semibold, alpha: 0.95)

    // Arrow between the app (x 165) and the Applications folder (x 495); icons sit at y 185 from the top.
    // The Read Me sits below the arrow, at y 295 from the top.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: 253))
    arrow.line(to: NSPoint(x: 390, y: 253))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.55).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 378, y: 264))
    head.line(to: NSPoint(x: 392, y: 253))
    head.line(to: NSPoint(x: 378, y: 242))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    text("First open: if macOS says it can't verify Brimtune, go to System Settings →", 22, size: 11.5, weight: .regular, alpha: 0.55)
    text("Privacy & Security → Open Anyway. Read Me explains every step and permission.", 5, size: 11.5, weight: .medium, alpha: 0.7)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/dmg-background.tiff")
try! image.tiffRepresentation(using: .lzw, factor: 1)!.write(to: out)
print("Wrote \(out.path)")
