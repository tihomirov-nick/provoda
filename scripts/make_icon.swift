// Renders the app icon: Resources/AppIcon.icon (the Icon Composer format, built into the app by scripts/build_app.sh
// with actool) and Resources/AppIcon-1024.png (a preview of the whole icon for the README).
// Usage: swift scripts/make_icon.swift
//
// Flat, black and white, like every icon of the family: a pure black body with the app's mark drawn on it in white.
// No gradients, glass, highlights or shadows. The body (a squircle with exponent 5, 100 px from the edges of 1024) is
// shared by the icons of all the family's apps. Only `drawMark` is the app's own.
import AppKit

let bodyColor: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0, 0, 0)

/// The mark, drawn with the current (white) colours in the flat drawing's coordinates: a 1024 square whose body is the
/// squircle at 100...924, y growing upwards. The USB trident of `ProvodaMark` (Sources/Provoda/AppParts.swift) in the
/// layout of the new utilities (Sources/Provoda/Glyph.swift): a 100 × 100 box, y down, the ink of the mark (`markBounds`)
/// scaled until its longer side is 80% of the body and centred on it, lines of 7.2 units that grow with the mark. The menu
/// bar icon draws the same mark (`MenuBarIcon.drawGlyph`). ProvodaTests checks that `markBounds`, the 80% and the 824 px of
/// the body are the numbers of `ProvodaMark.bounds` and Glyph.swift.
let markBounds = CGRect(x: 20.0, y: 4.3, width: 59.5, height: 89.2)
func drawMark(_ ctx: CGContext) {
    ctx.saveGState()
    let k = 0.8 * 824 / max(markBounds.width, markBounds.height)
    ctx.translateBy(x: 512 - markBounds.midX * k, y: 512 + markBounds.midY * k)
    ctx.scaleBy(x: k, y: -k)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let w: CGFloat = 7.2
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    func stroke(_ points: [CGPoint], _ width: CGFloat, closed: Bool = false) {
        ctx.setLineWidth(width)
        ctx.addLines(between: points)
        if closed { ctx.closePath() }
        ctx.strokePath()
    }
    func disc(_ c: CGPoint, _ r: CGFloat) {
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    let arrow = [p(50, 6), p(61, 23), p(39, 23)]
    ctx.addLines(between: arrow)
    ctx.closePath()
    ctx.fillPath()
    stroke(arrow, w * 0.4, closed: true)   // rounds the arrowhead's corners
    stroke([p(50, 22), p(50, 80)], w)
    disc(p(50, 83), 10.5)
    stroke([p(50, 70), p(27, 55), p(27, 40)], w)
    disc(p(27, 37), 7)
    stroke([p(50, 59), p(73, 44), p(73, 34)], w)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 66.5, y: 23.5, width: 13, height: 13), cornerWidth: 1.5, cornerHeight: 1.5,
                       transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - The icon files (the same in every app of the family)

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let white = CGColor(colorSpace: space, components: [1, 1, 1, 1])!

/// Apple-style continuous corners (superellipse).
func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// A transparent 1024 × 1024 image, drawn into with white as the colour.
func image(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(white)
    ctx.setStrokeColor(white)
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

// Resources/AppIcon.icon. In the Icon Composer format the 1024 canvas is the whole tile: the system cuts the squircle and
// leaves the margins itself. So the mark, laid out on the body of the flat drawing (824 of 1024 from 100), is scaled by
// 1024 / 824 to take the same part of the tile. One layer, the white mark on transparent; a solid fill in the body's
// colour; no glass, shadow, translucency or specular highlights, so the icon stays flat. On macOS 26 such an icon shows
// without the grey plate that the system puts around plain .icns icons.
let package = root.appendingPathComponent("Resources/AppIcon.icon")
try? FileManager.default.removeItem(at: package)
try FileManager.default.createDirectory(at: package.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try writePNG(image { ctx in
    ctx.scaleBy(x: 1024 / 824, y: 1024 / 824)
    ctx.translateBy(x: -100, y: -100)
    drawMark(ctx)
}, to: package.appendingPathComponent("Assets/mark.png"))
let fill = String(format: "srgb:%.5f,%.5f,%.5f,1.00000", bodyColor.red, bodyColor.green, bodyColor.blue)
try Data("""
{
  "fill" : {
    "solid" : "\(fill)"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : false,
          "image-name" : "mark.png",
          "name" : "mark"
        }
      ],
      "shadow" : {
        "kind" : "none",
        "opacity" : 0
      },
      "specular" : false,
      "translucency" : {
        "enabled" : false,
        "value" : 0
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

""".utf8).write(to: package.appendingPathComponent("icon.json"))

// Resources/AppIcon-1024.png: the whole icon, the body in the squircle with the mark, for the README.
try writePNG(image { ctx in
    ctx.addPath(squircle(CGRect(x: 100, y: 100, width: 824, height: 824)))
    ctx.setFillColor(CGColor(colorSpace: space, components: [bodyColor.red, bodyColor.green, bodyColor.blue, 1])!)
    ctx.fillPath()
    ctx.setFillColor(white)
    drawMark(ctx)
}, to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
print("Resources/AppIcon.icon and Resources/AppIcon-1024.png written")
