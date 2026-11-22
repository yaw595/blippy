// SPDX-License-Identifier: Apache-2.0
// Draws the background of the installer disk image (660x400 points, saved at 2x).
// Usage: swift Design/make_dmg_background.swift Design/dmg-background.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let size = NSSize(width: 660, height: 400)
let scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
						   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
						   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size // 2x pixels at 1x points, so Finder renders it sharp on Retina

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(srgbRed: 0.965, green: 0.965, blue: 0.975, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func draw(_ text: String, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, center: NSPoint, width: CGFloat = 560) {
	let paragraph = NSMutableParagraphStyle()
	paragraph.alignment = .center
	let attributed = NSAttributedString(string: text, attributes: [
		.font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph,
	])
	let box = attributed.boundingRect(with: NSSize(width: width, height: 200), options: [.usesLineFragmentOrigin])
	attributed.draw(in: NSRect(x: center.x - width / 2, y: center.y - box.height / 2, width: width, height: box.height))
}

draw("Drag Blippy to Applications", size: 22, weight: .semibold, color: NSColor(white: 0.12, alpha: 1), center: NSPoint(x: 330, y: 338))

// Arrow between the two icons (app on the left at x=180, Applications on the right at x=480; y is flipped in Finder)
let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 262, y: 200))
arrow.line(to: NSPoint(x: 398, y: 200))
arrow.move(to: NSPoint(x: 378, y: 220))
arrow.line(to: NSPoint(x: 398, y: 200))
arrow.line(to: NSPoint(x: 378, y: 180))
NSColor(srgbRed: 0.24, green: 0.49, blue: 0.95, alpha: 1).setStroke()
arrow.stroke()

draw("First time opening it? macOS asks you to confirm once:\nSystem Settings → Privacy & Security → Open Anyway.", size: 12.5, weight: .regular,
	 color: NSColor(white: 0.38, alpha: 1), center: NSPoint(x: 330, y: 62))
draw("Free and open source. No data collected.", size: 11, weight: .regular, color: NSColor(white: 0.55, alpha: 1), center: NSPoint(x: 330, y: 24))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
