import AppKit

let accent = NSColor(srgbRed: 0x7C/255, green: 0x5C/255, blue: 0xFF/255, alpha: 1)
let accentDeep = NSColor(srgbRed: 0x5B/255, green: 0x3F/255, blue: 0xF0/255, alpha: 1)
let accentSoft = NSColor(srgbRed: 0xA4/255, green: 0x8B/255, blue: 0xFF/255, alpha: 1)
let glassDark = NSColor(srgbRed: 0x19/255, green: 0x17/255, blue: 0x22/255, alpha: 1)

func render(pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let s = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: s)
    transform.concat()

    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

    let dropShadow = NSShadow()
    dropShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    dropShadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    dropShadow.shadowBlurRadius = 24 * s
    dropShadow.set()
    glassDark.setFill()
    platePath.fill()
    NSShadow().set()

    NSGraphicsContext.current?.saveGraphicsState()
    platePath.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.06), ending: NSColor.clear)!
        .draw(in: plate, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let key = NSRect(x: 232, y: 218, width: 560, height: 560)
    let keyPath = NSBezierPath(roundedRect: key, xRadius: 132, yRadius: 132)
    let glow = NSShadow()
    glow.shadowColor = accentDeep.withAlphaComponent(0.55)
    glow.shadowOffset = NSSize(width: 0, height: -26 * s)
    glow.shadowBlurRadius = 38 * s
    glow.set()
    accent.setFill()
    keyPath.fill()
    NSShadow().set()

    NSGraphicsContext.current?.saveGraphicsState()
    keyPath.addClip()
    NSGradient(colorsAndLocations: (accentSoft, 0.0), (accent, 0.35), (accentDeep, 1.0))!
        .draw(in: key, angle: -75)
    // Rim light disappears into noise below 64 px — skip it there.
    if pixels >= 64 {
        let rim = NSBezierPath(roundedRect: key.insetBy(dx: 5, dy: 5), xRadius: 127, yRadius: 127)
        rim.lineWidth = 10
        NSColor.white.withAlphaComponent(0.20).setStroke()
        rim.stroke()
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    let font = NSFont.monospacedSystemFont(ofSize: 420, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let glyph = "b"
    let size = glyph.size(withAttributes: attrs)
    glyph.draw(at: NSPoint(x: 512 - size.width/2, y: 512 - size.height/2), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: "/tmp/bopop-icon/AppIcon.iconset")
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, px) in sizes {
    render(pixels: px, to: out.appendingPathComponent("\(name).png"))
}
print("iconset done")
