// Renders Support/AppIcon.icns and docs/icon.png. Run: swift scripts/make-icon.swift
// ONAIR "Test Card": seven colour bars over a black field, the name set under them.
import AppKit
import CoreText

CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Support/Fonts/ArchivoBlack.ttf") as CFURL, .process, nil)

func c(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
let bars: [UInt32] = [0xF2F0EA, 0xF5D90A, 0x25D6E5, 0x2BD44E, 0xE83CC8, 0xE8332A, 0x2A3BE8]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s)
    let clip = NSBezierPath(roundedRect: body, xRadius: 185*s, yRadius: 185*s)
    clip.addClip()
    c(0x0E0E10).setFill(); body.fill()

    // Bars: top 62% of the tile.
    let top = body.maxY, barH = body.height * 0.62, w = body.width / 7
    for (i, hex) in bars.enumerated() {
        c(hex).setFill()
        NSRect(x: body.minX + CGFloat(i) * w, y: top - barH, width: w + 0.5, height: barH).fill()
    }
    // Reversed strip, as on a real card.
    let stripH = body.height * 0.06
    for i in 0..<7 where i % 2 == 0 {
        c(bars[6 - i]).setFill()
        NSRect(x: body.minX + CGFloat(i) * w, y: top - barH - stripH, width: w + 0.5, height: stripH).fill()
    }

    // Name, only where it can be read.
    if px >= 64 {
        let font = NSFont(name: "ArchivoBlack-Regular", size: 150*s) ?? .systemFont(ofSize: 150*s, weight: .black)
        let str = NSAttributedString(string: "ONAIR", attributes: [.font: font, .foregroundColor: c(0xF2F0EA), .kern: -3*s])
        let size = str.size()
        str.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.minY + 56*s))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base*2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: "docs/icon.png"))
