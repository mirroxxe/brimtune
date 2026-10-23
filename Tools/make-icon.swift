// Renders Resources/AppIcon.icns: a dark squircle with a glowing island holding
// a cover and waveform. Run: swift Tools/make-icon.swift
import AppKit

let S: CGFloat = 1024
let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle body on Apple's 824pt grid.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
let shadow = NSShadow(); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.set()
NSColor.black.setFill(); squircle.fill()
ctx.restoreGState()

ctx.saveGState()
squircle.addClip()
NSGradient(colors: [NSColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1), NSColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)])!
    .draw(in: body, angle: -90)
// Album-colour aurora.
func blob(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    NSGradient(colors: [c.withAlphaComponent(0.85), c.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
}
blob(NSColor(red: 0.98, green: 0.36, blue: 0.55, alpha: 1), 300, 260, 420)
blob(NSColor(red: 0.35, green: 0.45, blue: 1.0, alpha: 1), 760, 330, 420)
blob(NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1), 520, 120, 300)
// Glass sheen.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    .draw(in: CGRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

// The island.
let island = CGRect(x: 232, y: 600, width: 560, height: 168)
let pill = NSBezierPath(roundedRect: island, xRadius: 84, yRadius: 84)
ctx.saveGState()
let glow = NSShadow(); glow.shadowBlurRadius = 60; glow.shadowOffset = .zero
glow.shadowColor = NSColor(red: 0.98, green: 0.4, blue: 0.6, alpha: 0.7); glow.set()
NSColor.black.setFill(); pill.fill()
ctx.restoreGState()
NSColor.white.withAlphaComponent(0.10).setStroke(); pill.lineWidth = 3; pill.stroke()

// Cover.
let cover = CGRect(x: 280, y: 636, width: 96, height: 96)
let coverPath = NSBezierPath(roundedRect: cover, xRadius: 22, yRadius: 22)
ctx.saveGState(); coverPath.addClip()
NSGradient(colors: [NSColor(red: 1.0, green: 0.55, blue: 0.3, alpha: 1), NSColor(red: 0.95, green: 0.25, blue: 0.55, alpha: 1),
                    NSColor(red: 0.45, green: 0.3, blue: 0.95, alpha: 1)])!.draw(in: cover, angle: -45)
ctx.restoreGState()

// Waveform.
let heights: [CGFloat] = [44, 86, 62, 104, 54]
for (i, h) in heights.enumerated() {
    let x = 600 + CGFloat(i) * 30
    let bar = NSBezierPath(roundedRect: CGRect(x: x, y: 684 - h / 2, width: 16, height: h), xRadius: 8, yRadius: 8)
    NSColor(red: 1.0, green: 0.55 + CGFloat(i) * 0.06, blue: 0.6 + CGFloat(i) * 0.07, alpha: 1).setFill()
    bar.fill()
}
ctx.restoreGState()
image.unlockFocus()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: out)
