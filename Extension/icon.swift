// Renders the lofi compass icon: swift icon.swift <out.png> <pixels> [full]
// "full" draws edge to edge (for the extension manifest); default is the macOS app icon grid.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let out = args[1], px = Int(args[2])!, full = args.count > 3
let s = CGFloat(px) / 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: s, y: s)

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
let cream = rgb(0xF2E3CC), ink = rgb(0x3B3A50), teal = rgb(0x6F9A92), coral = rgb(0xE07A5F), paper = rgb(0xFBF4E8)

// Body
let body = full ? CGRect(x: 0, y: 0, width: 1024, height: 1024) : CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = full ? 220 : 185
let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
if !full {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.25))
    ctx.addPath(bodyPath); ctx.setFillColor(cream); ctx.fillPath()
    ctx.restoreGState()
}
ctx.addPath(bodyPath); ctx.setFillColor(cream); ctx.fillPath()
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()

// Soft sun behind the dial
ctx.setFillColor(rgb(0xF4C9A0, 0.55))
ctx.fillEllipse(in: CGRect(x: 560, y: 560, width: 330, height: 330))

// Dial
let c = CGPoint(x: 512, y: 500), r: CGFloat = 270
ctx.setFillColor(rgb(0x000000, 0.08))
ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r - 16, width: 2 * r, height: 2 * r))
ctx.setFillColor(paper)
ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
ctx.setStrokeColor(teal); ctx.setLineWidth(44)
ctx.strokeEllipse(in: CGRect(x: c.x - r + 22, y: c.y - r + 22, width: 2 * r - 44, height: 2 * r - 44))

// Ticks
ctx.setStrokeColor(ink); ctx.setLineCap(.round); ctx.setLineWidth(18)
for i in 0..<4 {
    let a = CGFloat(i) * .pi / 2
    ctx.move(to: CGPoint(x: c.x + cos(a) * 180, y: c.y + sin(a) * 180))
    ctx.addLine(to: CGPoint(x: c.x + cos(a) * 205, y: c.y + sin(a) * 205))
}
ctx.strokePath()

// Needle, tilted like Safari's
ctx.saveGState()
ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: -.pi / 4)
func half(_ tip: CGFloat, _ color: CGColor) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: tip)); ctx.addLine(to: CGPoint(x: 46, y: 0)); ctx.addLine(to: CGPoint(x: -46, y: 0))
    ctx.closePath(); ctx.setFillColor(color); ctx.fillPath()
}
half(175, coral); half(-175, ink)
ctx.restoreGState()
ctx.setFillColor(paper); ctx.fillEllipse(in: CGRect(x: c.x - 20, y: c.y - 20, width: 40, height: 40))

// Grain
var rng = SystemRandomNumberGenerator()
let step: CGFloat = 1024 / CGFloat(px) * 2
var y: CGFloat = 0
while y < 1024 {
    var x: CGFloat = 0
    while x < 1024 {
        let v = CGFloat.random(in: 0...1, using: &rng)
        if v < 0.5 {
            ctx.setFillColor(v < 0.25 ? rgb(0x000000, 0.05) : rgb(0xFFFFFF, 0.06))
            ctx.fill(CGRect(x: x, y: y, width: step, height: step))
        }
        x += step
    }
    y += step
}
ctx.restoreGState()

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
