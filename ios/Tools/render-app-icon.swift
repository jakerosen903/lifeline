// Renders the Lifeline app icon (a timeline: an olive path with three ochre moments) at
// 1024 px in light, dark and tinted appearances. Run: swift ios/Tools/render-app-icon.swift <out dir>
import AppKit

struct Palette {
    var background: NSColor?, disc: NSColor, path: NSColor, moment: NSColor, ring: NSColor
}
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let light = Palette(background: rgb(0xF4EDE1), disc: rgb(0xEADDC6), path: rgb(0x5F7046), moment: rgb(0xC8893F), ring: rgb(0xF4EDE1))
let dark = Palette(background: rgb(0x2B2117), disc: rgb(0x3F3226), path: rgb(0x93A77B), moment: rgb(0xD1A05A), ring: rgb(0x2B2117))
// Tinted: iOS colors the opaque pixels itself; shape carries value only, background stays clear.
let tinted = Palette(background: nil, disc: rgb(0xFFFFFF, 0.18), path: rgb(0xFFFFFF, 0.75), moment: rgb(0xFFFFFF, 1), ring: rgb(0x000000, 0.35))

let size: CGFloat = 1024
let p0 = CGPoint(x: 92, y: 164), p1 = CGPoint(x: 330, y: 150), p2 = CGPoint(x: 694, y: 874), p3 = CGPoint(x: 932, y: 860)
func bezier(_ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let x = u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x
    let y = u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
    return CGPoint(x: x, y: y)
}

func render(_ palette: Palette, to url: URL) throws {
    let opaque = palette.background != nil
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: alpha.rawValue) else { return }
    if let background = palette.background {
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    ctx.setFillColor(palette.disc.cgColor)
    ctx.fillEllipse(in: CGRect(x: 512 - 196 - 36, y: 512 - 196 - 24, width: 392, height: 392))

    let path = CGMutablePath()
    path.move(to: p0)
    path.addCurve(to: p3, control1: p1, control2: p2)
    ctx.setStrokeColor(palette.path.cgColor)
    ctx.setLineWidth(68)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.strokePath()

    for (t, radius) in [(0.21, 46.0), (0.5, 74.0), (0.79, 46.0)] {
        let c = bezier(CGFloat(t))
        let ring: CGFloat = 16
        ctx.setFillColor(palette.ring.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - radius - ring, y: c.y - radius - ring, width: 2 * (radius + ring), height: 2 * (radius + ring)))
        ctx.setFillColor(palette.moment.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
    }
    guard let image = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try png.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try render(light, to: out.appendingPathComponent("AppIcon-light.png"))
try render(dark, to: out.appendingPathComponent("AppIcon-dark.png"))
try render(tinted, to: out.appendingPathComponent("AppIcon-tinted.png"))
print("wrote 3 icons to \(out.path)")
