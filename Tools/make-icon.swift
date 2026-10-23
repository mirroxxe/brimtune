// Renders the app icon: a cream block "B" on a black squircle. Its counters are a tweeter and a
// woofer, and a notch is cut into its top edge. Run:
//   swift Tools/make-icon.swift icon_1024.png
// then build Resources/AppIcon.icns with sips + iconutil and copy sizes to site/assets.
import AppKit

let S: CGFloat = 1024
let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let cream = NSColor(red: 0.925, green: 0.906, blue: 0.871, alpha: 1)

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
NSGradient(colors: [NSColor(red: 0.09, green: 0.08, blue: 0.11, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)])!
    .draw(in: body, angle: -90)

// The "B": square on the left, rounded bowls on the right (the upper one narrower),
// a wedge between the bowls, and a notch in the top edge.
let b = NSBezierPath()
b.move(to: NSPoint(x: 262, y: 262))
b.line(to: NSPoint(x: 652, y: 262))
b.appendArc(withCenter: NSPoint(x: 652, y: 372), radius: 110, startAngle: -90, endAngle: 0)
b.line(to: NSPoint(x: 762, y: 482))
b.line(to: NSPoint(x: 608, y: 512))
b.line(to: NSPoint(x: 732, y: 542))
b.line(to: NSPoint(x: 732, y: 672))
b.appendArc(withCenter: NSPoint(x: 642, y: 672), radius: 90, startAngle: 0, endAngle: 90)
b.line(to: NSPoint(x: 584, y: 762))
b.line(to: NSPoint(x: 584, y: 744))
b.appendArc(withCenter: NSPoint(x: 560, y: 744), radius: 24, startAngle: 0, endAngle: -90, clockwise: true)
b.line(to: NSPoint(x: 464, y: 720))
b.appendArc(withCenter: NSPoint(x: 464, y: 744), radius: 24, startAngle: -90, endAngle: 180, clockwise: true)
b.line(to: NSPoint(x: 440, y: 762))
b.line(to: NSPoint(x: 262, y: 762))
b.close()

// Counters: the tweeter above, the woofer below.
let tweeter = NSPoint(x: 520, y: 620), woofer = NSPoint(x: 520, y: 388)
func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}
b.append(circle(tweeter, 52))
b.append(circle(woofer, 92))
b.windingRule = .evenOdd
cream.setFill(); b.fill()

// Dust caps: a cream dot in the tweeter, a rose one in the woofer.
cream.setFill(); circle(tweeter, 16).fill()
NSColor(red: 0.949, green: 0.392, blue: 0.557, alpha: 1).setFill(); circle(woofer, 30).fill()
ctx.restoreGState()
image.unlockFocus()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: out)
