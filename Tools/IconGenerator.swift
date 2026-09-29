import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: a) }
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) { fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }

// Clean utility-style mark: white canvas, a folder behind an archive box.
rounded(NSRect(x: 32, y: 32, width: 960, height: 960), 230, c(0.985, 0.985, 0.98))

// Soft grounding shadow.
rounded(NSRect(x: 145, y: 142, width: 734, height: 84), 42, c(0.05, 0.08, 0.14, 0.12))

// Folder layer (classic Finder blue).
let tab = NSBezierPath(roundedRect: NSRect(x: 166, y: 560, width: 344, height: 205), xRadius: 62, yRadius: 62)
NSGradient(starting: c(0.39, 0.73, 1.0), ending: c(0.12, 0.42, 0.88))?.draw(in: tab, angle: 90)
let folder = NSBezierPath(roundedRect: NSRect(x: 130, y: 248, width: 764, height: 480), xRadius: 88, yRadius: 88)
NSGradient(starting: c(0.32, 0.68, 1.0), ending: c(0.08, 0.35, 0.78))?.draw(in: folder, angle: 90)

// Archive box layer (front-most, neutral graphite-blue).
let box = NSBezierPath(roundedRect: NSRect(x: 210, y: 210, width: 604, height: 392), xRadius: 72, yRadius: 72)
NSGradient(starting: c(0.31, 0.39, 0.52), ending: c(0.12, 0.18, 0.28))?.draw(in: box, angle: 90)
rounded(NSRect(x: 210, y: 520, width: 604, height: 82), 40, c(0.16, 0.25, 0.38))

// Compression bands / archive clasp.
rounded(NSRect(x: 460, y: 270, width: 104, height: 250), 22, c(0.95, 0.97, 1.0, 0.92))
rounded(NSRect(x: 481, y: 292, width: 62, height: 40), 12, c(0.16, 0.28, 0.46))
rounded(NSRect(x: 481, y: 368, width: 62, height: 40), 12, c(0.16, 0.28, 0.46))
rounded(NSRect(x: 481, y: 444, width: 62, height: 40), 12, c(0.16, 0.28, 0.46))

// Small “peek” lens, deliberately secondary to the folder/archive silhouette.
let lens = NSBezierPath(ovalIn: NSRect(x: 662, y: 160, width: 160, height: 160))
c(0.08, 0.40, 0.90).setFill(); lens.fill()
let ring = NSBezierPath(ovalIn: NSRect(x: 692, y: 190, width: 100, height: 100))
c(1, 1, 1).setStroke(); ring.lineWidth = 16; ring.stroke()
let handle = NSBezierPath(); handle.move(to: NSPoint(x: 780, y: 200)); handle.line(to: NSPoint(x: 856, y: 124)); c(0.08, 0.40, 0.90).setStroke(); handle.lineWidth = 28; handle.lineCapStyle = .round; handle.stroke()

image.unlockFocus()
let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
