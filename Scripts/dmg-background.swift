// Draws the installer window's background: an arrow from the app to Applications and a line
// saying what to do. make-dmg.sh runs it at 1x and 2x and joins them into one TIFF.
//
//   swift Scripts/dmg-background.swift <output.png> <scale>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let scale = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: dmg-background.swift <output.png> <scale>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])

// Matches the window and icon positions in make-dmg.sh.
let size = CGSize(width: 600, height: 400)
let appCenter = CGPoint(x: 160, y: 190)
let applicationsCenter = CGPoint(x: 440, y: 190)
let accent = NSColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

// Finder's coordinates start at the top; AppKit's at the bottom.
func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: size.height - point.y) }

// A soft light background, so Finder's icon labels stay readable.
NSGradient(colors: [
    NSColor(red: 0.985, green: 0.98, blue: 1, alpha: 1),
    NSColor(red: 0.93, green: 0.91, blue: 0.99, alpha: 1),
])?.draw(in: CGRect(origin: .zero, size: size), angle: -90)

// The arrow, between the two icons (each about 128 points wide).
let start = flipped(CGPoint(x: appCenter.x + 78, y: appCenter.y))
let end = flipped(CGPoint(x: applicationsCenter.x - 78, y: applicationsCenter.y))
let shaft = NSBezierPath()
shaft.move(to: start)
shaft.curve(to: CGPoint(x: end.x - 20, y: end.y),
            controlPoint1: CGPoint(x: start.x + 30, y: start.y + 26),
            controlPoint2: CGPoint(x: end.x - 44, y: end.y + 26))
shaft.lineWidth = 5
shaft.lineCapStyle = .round
let dash: [CGFloat] = [2, 11]
shaft.setLineDash(dash, count: dash.count, phase: 0)
accent.withAlphaComponent(0.85).setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: CGPoint(x: end.x + 4, y: end.y))
head.line(to: CGPoint(x: end.x - 16, y: end.y + 12))
head.line(to: CGPoint(x: end.x - 16, y: end.y - 12))
head.close()
accent.setFill()
head.fill()

// What to do, under the icons.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let title = NSAttributedString(string: "Drag Dynamic Ledge into Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
    .foregroundColor: NSColor(white: 0.13, alpha: 1),
    .paragraphStyle: paragraph,
])
title.draw(in: CGRect(x: 0, y: 72, width: size.width, height: 24))
let detail = NSAttributedString(string: "Then open it from your Applications folder", attributes: [
    .font: NSFont.systemFont(ofSize: 13),
    .foregroundColor: NSColor(white: 0.4, alpha: 1),
    .paragraphStyle: paragraph,
])
detail.draw(in: CGRect(x: 0, y: 50, width: size.width, height: 20))

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
