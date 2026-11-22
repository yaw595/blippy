// Generates Blippy's icons (full-color glass icon + monochrome outline) as PNGs.
// Usage: swift Design/make_icons.swift <output-root>
//   <output-root> is the quickshare-mac folder; assets are written into the .xcassets folders,
//   and previews go to <output-root>/Design/previews/.
// All art is drawn in a 1024x1024 coordinate space and scaled to the requested pixel size.

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// MARK: - Helpers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
	CGColor(colorSpace: srgb, components: [r, g, b, a])!
}

func white(_ a: CGFloat) -> CGColor { color(1, 1, 1, a) }

func gradient(_ colors: [CGColor]) -> CGGradient {
	CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil)!
}

func makePNG(pixels: Int, background: CGColor? = nil, _ body: (CGContext) -> Void) -> Data {
	let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
						space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
	if let background {
		ctx.setFillColor(background)
		ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
	}
	ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
	ctx.interpolationQuality = .high
	ctx.setShouldAntialias(true)
	body(ctx)
	return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, to path: String) {
	let url = root.appendingPathComponent(path)
	try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	try! data.write(to: url)
	print("wrote \(path) (\(data.count) bytes)")
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
	CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Full-color icon

/// Glass squircle, two concentric discs, and a folder.
func drawFullIcon(_ cg: CGContext, margin: CGFloat, shadow: Bool) {
	let side = 1024 - margin * 2
	let body = CGRect(x: margin, y: margin, width: side, height: side)
	let k = side / 824 // scale relative to the standard macOS icon body
	let bodyPath = roundedRect(body, radius: side * 0.2237)
	let mid = CGPoint(x: body.midX, y: body.midY)

	// Body with drop shadow
	cg.saveGState()
	if shadow {
		cg.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 34 * k, color: color(0, 0, 0, 0.28))
	}
	cg.addPath(bodyPath)
	cg.setFillColor(color(0.25, 0.50, 0.95))
	cg.fillPath()
	cg.restoreGState()

	// Everything else is clipped to the body
	cg.saveGState()
	cg.addPath(bodyPath)
	cg.clip()

	// Base gradient: blue, lighter at the top (frosted glass)
	cg.drawLinearGradient(
		gradient([color(0.55, 0.74, 1.0), color(0.32, 0.58, 0.98), color(0.16, 0.40, 0.90)]),
		start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])

	// Soft light from the top-left
	cg.drawRadialGradient(
		gradient([white(0.45), white(0)]),
		startCenter: CGPoint(x: body.minX + side * 0.28, y: body.maxY - side * 0.12), startRadius: 0,
		endCenter: CGPoint(x: body.minX + side * 0.28, y: body.maxY - side * 0.12), endRadius: side * 0.75,
		options: [])
	cg.restoreGState()

	// Glass edge: a soft white glow that bleeds inward from the rim, plus a crisp hairline
	cg.saveGState()
	cg.addPath(bodyPath)
	cg.clip()
	cg.setShadow(offset: .zero, blur: 46 * k, color: white(0.40))
	cg.addPath(bodyPath)
	cg.setStrokeColor(white(0.7))
	cg.setLineWidth(10 * k)
	cg.strokePath()
	cg.restoreGState()
	cg.saveGState()
	cg.addPath(roundedRect(body.insetBy(dx: 2 * k, dy: 2 * k), radius: side * 0.2237 - 2 * k))
	cg.setStrokeColor(white(0.38))
	cg.setLineWidth(3 * k)
	cg.strokePath()
	cg.restoreGState()

	// Outer disc
	let outerR = side * 0.365
	cg.saveGState()
	cg.addEllipse(in: CGRect(x: mid.x - outerR, y: mid.y - outerR, width: outerR * 2, height: outerR * 2))
	cg.setFillColor(white(0.15))
	cg.fillPath()
	cg.addEllipse(in: CGRect(x: mid.x - outerR, y: mid.y - outerR, width: outerR * 2, height: outerR * 2))
	cg.setStrokeColor(white(0.30))
	cg.setLineWidth(4 * k)
	cg.strokePath()
	cg.restoreGState()

	// Inner disc (frosted)
	let innerR = side * 0.282
	let innerRect = CGRect(x: mid.x - innerR, y: mid.y - innerR, width: innerR * 2, height: innerR * 2)
	cg.saveGState()
	cg.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: color(0.04, 0.16, 0.55, 0.26))
	cg.addEllipse(in: innerRect)
	cg.setFillColor(white(0.3))
	cg.fillPath()
	cg.restoreGState()
	cg.saveGState()
	cg.addEllipse(in: innerRect)
	cg.clip()
	cg.drawLinearGradient(
		gradient([white(0.50), white(0.20)]),
		start: CGPoint(x: mid.x, y: innerRect.maxY), end: CGPoint(x: mid.x, y: innerRect.minY), options: [])
	cg.restoreGState()
	cg.saveGState()
	cg.addEllipse(in: innerRect)
	cg.setStrokeColor(white(0.55))
	cg.setLineWidth(3.5 * k)
	cg.strokePath()
	cg.restoreGState()

	// Folder: frosted-glass glyph with generously rounded corners.
	// Back panel + tab are filled opaque inside a transparency layer, then composited at one alpha,
	// so the tab joins the panel without a visible seam.
	let fw = 296 * k, fh = 206 * k
	let fx = mid.x - fw / 2
	let fy = mid.y - fh / 2 - 8 * k
	let corner = 42 * k
	let backRect = CGRect(x: fx, y: fy, width: fw, height: fh)
	let tabRect = CGRect(x: fx, y: fy + fh - 34 * k, width: 124 * k, height: 78 * k)

	cg.saveGState()
	cg.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 26 * k, color: color(0.04, 0.16, 0.55, 0.26))
	cg.setAlpha(0.8)
	cg.beginTransparencyLayer(auxiliaryInfo: nil)
	cg.setFillColor(white(1))
	cg.addPath(roundedRect(backRect, radius: corner))
	cg.fillPath()
	cg.addPath(roundedRect(tabRect, radius: 30 * k))
	cg.fillPath()
	cg.endTransparencyLayer()
	cg.restoreGState()

	// Front panel: brighter, with a soft top highlight and a faint glass rim
	let frontRect = CGRect(x: fx, y: fy, width: fw, height: fh * 0.70)
	let frontPath = roundedRect(frontRect, radius: corner)
	cg.saveGState()
	cg.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 22 * k, color: color(0.04, 0.16, 0.55, 0.24))
	cg.addPath(frontPath)
	cg.setFillColor(white(0.9))
	cg.fillPath()
	cg.restoreGState()
	cg.saveGState()
	cg.addPath(frontPath)
	cg.clip()
	cg.drawLinearGradient(
		gradient([white(1), white(0.82)]),
		start: CGPoint(x: fx, y: frontRect.maxY), end: CGPoint(x: fx, y: frontRect.minY), options: [])
	cg.restoreGState()
	cg.saveGState()
	cg.addPath(frontPath)
	cg.setStrokeColor(white(0.7))
	cg.setLineWidth(2.5 * k)
	cg.strokePath()
	cg.restoreGState()
}

// MARK: - Monochrome outline (template image)

func folderOutline(x0: CGFloat, y0: CGFloat, w: CGFloat, h: CGFloat, tabW: CGFloat, tabH: CGFloat, r: CGFloat) -> CGPath {
	let x1 = x0 + w, yb = y0 + h, yt = yb + tabH
	let p = CGMutablePath()
	p.move(to: CGPoint(x: x0 + r, y: y0))
	p.addLine(to: CGPoint(x: x1 - r, y: y0))
	p.addQuadCurve(to: CGPoint(x: x1, y: y0 + r), control: CGPoint(x: x1, y: y0))
	p.addLine(to: CGPoint(x: x1, y: yb - r))
	p.addQuadCurve(to: CGPoint(x: x1 - r, y: yb), control: CGPoint(x: x1, y: yb))
	p.addLine(to: CGPoint(x: x0 + tabW + tabH * 0.7, y: yb))
	p.addLine(to: CGPoint(x: x0 + tabW, y: yt))
	p.addLine(to: CGPoint(x: x0 + r, y: yt))
	p.addQuadCurve(to: CGPoint(x: x0, y: yt - r), control: CGPoint(x: x0, y: yt))
	p.addLine(to: CGPoint(x: x0, y: y0 + r))
	p.addQuadCurve(to: CGPoint(x: x0 + r, y: y0), control: CGPoint(x: x0, y: y0))
	p.closeSubpath()
	return p
}

/// Outline version of the icon: squircle, one ring, folder. Black on clear (use as a template image).
func drawOutline(_ cg: CGContext, ink: CGColor = color(0, 0, 0, 1), stroke: CGFloat = 66, ring: Bool = true) {
	cg.setStrokeColor(ink)
	cg.setLineCap(.round)
	cg.setLineJoin(.round)
	cg.setLineWidth(stroke)

	let inset: CGFloat = 70
	let side = 1024 - inset * 2
	cg.addPath(roundedRect(CGRect(x: inset, y: inset, width: side, height: side), radius: side * 0.2237))
	cg.strokePath()

	if ring {
		let ringR: CGFloat = 300
		cg.setLineWidth(stroke * 0.85)
		cg.addEllipse(in: CGRect(x: 512 - ringR, y: 512 - ringR, width: ringR * 2, height: ringR * 2))
		cg.strokePath()
		cg.setLineWidth(stroke * 0.85)
		cg.addPath(folderOutline(x0: 512 - 150, y0: 512 - 120, w: 300, h: 190, tabW: 120, tabH: 56, r: 60))
		cg.strokePath()
	} else {
		// Small sizes: just the squircle and a larger folder, so it stays legible at 18pt.
		cg.setLineWidth(stroke)
		cg.addPath(folderOutline(x0: 512 - 215, y0: 512 - 190, w: 430, h: 290, tabW: 170, tabH: 84, r: 86))
		cg.strokePath()
	}
}

// MARK: - Output

// App icon (macOS grid: 824pt body with 100pt margin and a drop shadow)
let appIconFiles: [(String, Int)] = [
	("16.png", 16), ("32.png", 32), ("32 1.png", 32), ("64.png", 64), ("128.png", 128),
	("256.png", 256), ("256 1.png", 256), ("512.png", 512), ("512 1.png", 512), ("1024.png", 1024),
]
for (name, px) in appIconFiles {
	write(makePNG(pixels: px) { drawFullIcon($0, margin: 100, shadow: true) },
		  to: "Blippy/Assets.xcassets/AppIcon.appiconset/\(name)")
}

// Menu bar / Finder-style outline (template): 18pt at 1x, 2x, 3x
for (name, px) in [("NearbyShare.png", 18), ("NearbyShare@2x.png", 36), ("NearbyShare@3x.png", 54)] {
	write(makePNG(pixels: px) { drawOutline($0, ring: false) }, to: "Blippy/Assets.xcassets/MenuBarIcon.imageset/\(name)")
}

// Share extension: same AppIcon (its own copy, so the Share menu shows it) + in-window glyph
for (name, px) in appIconFiles {
	write(makePNG(pixels: px) { drawFullIcon($0, margin: 100, shadow: true) },
		  to: "ShareExtension/Assets.xcassets/AppIcon.appiconset/\(name)")
}
for (name, px) in [("glass@1x.png", 64), ("glass@2x.png", 128), ("glass@3x.png", 192)] {
	write(makePNG(pixels: px) { drawFullIcon($0, margin: 24, shadow: false) },
		  to: "ShareExtension/Assets.xcassets/AppGlyph.imageset/\(name)")
}

// Previews for review (not part of the app)
write(makePNG(pixels: 1024) { drawFullIcon($0, margin: 100, shadow: true) }, to: "Design/previews/icon-full.png")
let gray = color(0.93, 0.93, 0.94)
write(makePNG(pixels: 512, background: gray) { drawOutline($0) }, to: "Design/previews/icon-outline-light.png")
write(makePNG(pixels: 512, background: color(0.12, 0.12, 0.13)) { drawOutline($0, ink: white(0.95)) }, to: "Design/previews/icon-outline-dark.png")
write(makePNG(pixels: 36, background: gray) { drawOutline($0, ring: false) }, to: "Design/previews/icon-outline-36px.png")
write(makePNG(pixels: 512, background: gray) { drawOutline($0, ring: false) }, to: "Design/previews/icon-outline-small-512.png")
