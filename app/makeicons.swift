// makeicons.swift — draws AppIcon.iconset, menubarTemplate.png and a preview.
// Run: swiftc makeicons.swift -o /tmp/mkicons && (cd app && /tmp/mkicons)

import Cocoa

func makeContext(_ px: Int) -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

func savePNG(_ ctx: CGContext, _ path: String) {
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

func roundedRect(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

// Bird "sitting", facing right. foot — anchor point, beak — beak color.
func birdShape(_ c: CGContext, foot: CGPoint, s: CGFloat, body: CGColor, beak: CGColor) {
    let p = CGMutablePath()
    let bx = foot.x, by = foot.y + s * 0.42
    p.addEllipse(in: CGRect(x: bx - s * 0.42, y: by - s * 0.40, width: s * 0.84, height: s * 0.80))
    let hx = bx + s * 0.30, hy = by + s * 0.34
    p.addEllipse(in: CGRect(x: hx - s * 0.26, y: hy - s * 0.26, width: s * 0.52, height: s * 0.52))
    p.move(to: CGPoint(x: bx - s * 0.30, y: by + s * 0.12))
    p.addLine(to: CGPoint(x: bx - s * 0.80, y: by + s * 0.32))
    p.addLine(to: CGPoint(x: bx - s * 0.32, y: by - s * 0.14))
    p.closeSubpath()
    c.addPath(p); c.setFillColor(body); c.fillPath()
    let bp = CGMutablePath()
    bp.move(to: CGPoint(x: hx + s * 0.24, y: hy + s * 0.06))
    bp.addLine(to: CGPoint(x: hx + s * 0.48, y: hy - s * 0.02))
    bp.addLine(to: CGPoint(x: hx + s * 0.24, y: hy - s * 0.10))
    bp.closeSubpath()
    c.addPath(bp); c.setFillColor(beak); c.fillPath()
}

func drawAppIcon(_ ctx: CGContext, _ S: CGFloat) {
    ctx.saveGState()
    ctx.addPath(roundedRect(CGRect(x: 0, y: 0, width: S, height: S), S * 0.2237))
    ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.33, green: 0.62, blue: 1.00, alpha: 1),
        CGColor(red: 0.04, green: 0.36, blue: 0.87, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()
    let blueBot = CGColor(red: 0.04, green: 0.36, blue: 0.87, alpha: 1)

    // perch
    ctx.setFillColor(.white)
    ctx.addPath(roundedRect(CGRect(x: S * 0.22, y: S * 0.475, width: S * 0.56, height: S * 0.055), S * 0.0275))
    ctx.fillPath()
    // file list
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
    let lw = S * 0.5, lh = S * 0.05, lx = S * 0.25
    ctx.addPath(roundedRect(CGRect(x: lx, y: S * 0.35, width: lw, height: lh), lh / 2))
    ctx.addPath(roundedRect(CGRect(x: lx, y: S * 0.25, width: lw * 0.7, height: lh), lh / 2))
    ctx.fillPath()
    // feet
    ctx.setStrokeColor(.white); ctx.setLineWidth(S * 0.022); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: S * 0.475, y: S * 0.555)); ctx.addLine(to: CGPoint(x: S * 0.475, y: S * 0.53))
    ctx.move(to: CGPoint(x: S * 0.525, y: S * 0.555)); ctx.addLine(to: CGPoint(x: S * 0.525, y: S * 0.53))
    ctx.strokePath()
    // bird
    birdShape(ctx, foot: CGPoint(x: S * 0.50, y: S * 0.56), s: S * 0.33,
              body: .white, beak: CGColor(red: 1.0, green: 0.66, blue: 0.16, alpha: 1))
    // eye (blue "slit")
    let bx = S * 0.50, by = S * 0.56 + S * 0.33 * 0.42
    let hx = bx + S * 0.33 * 0.30, hy = by + S * 0.33 * 0.34
    ctx.setFillColor(blueBot)
    ctx.fillEllipse(in: CGRect(x: hx + S * 0.33 * 0.02, y: hy + S * 0.33 * 0.04, width: S * 0.33 * 0.13, height: S * 0.33 * 0.13))
}

// Monochrome tray glyph: black bird on a perch, transparent background.
func drawGlyph(_ ctx: CGContext, _ S: CGFloat) {
    ctx.setFillColor(.black)
    ctx.addPath(roundedRect(CGRect(x: S * 0.14, y: S * 0.24, width: S * 0.72, height: S * 0.08), S * 0.04))
    ctx.fillPath()
    birdShape(ctx, foot: CGPoint(x: S * 0.50, y: S * 0.34), s: S * 0.44, body: .black, beak: .black)
}

// app iconset
let iconset = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let ctx = makeContext(px)
    drawAppIcon(ctx, CGFloat(px))
    savePNG(ctx, "\(iconset)/\(name).png")
}

// menu bar template (18pt @2x = 36px)
let g = makeContext(36)
drawGlyph(g, 36)
savePNG(g, "menubarTemplate.png")

// 512px preview
let prev = makeContext(512)
drawAppIcon(prev, 512)
savePNG(prev, "icon_preview.png")

print("icons generated: \(iconset)/, menubarTemplate.png, icon_preview.png")
