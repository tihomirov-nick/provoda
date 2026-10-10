import AppKit
import XCTest
@testable import Provoda

/// How the trident fills its room: the 22 pt menu bar canvas and the tile of the app icon. Both come from the mark's bounds,
/// the rectangle its ink covers in the glyph's box, so that rectangle must be what the drawing really covers.
@MainActor
final class GlyphTests: XCTestCase {
    /// The ink of `draw` in box units, from a bitmap of 8 pixels per unit.
    private func ink(_ draw: (CGContext) -> Void) throws -> CGRect {
        let ppu: CGFloat = 8, origin: CGFloat = 20, side = Int(140 * ppu)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: ppu, y: -ppu)
        ctx.translateBy(x: origin, y: origin)
        ctx.setFillColor(.black)
        ctx.setStrokeColor(.black)
        Glyph.prepare(ctx)
        draw(ctx)
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where data[y * ctx.bytesPerRow + x * 4 + 3] >= 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return CGRect(x: CGFloat(minX) / ppu - origin, y: CGFloat(minY) / ppu - origin,
                      width: CGFloat(maxX + 1 - minX) / ppu, height: CGFloat(maxY + 1 - minY) / ppu)
    }

    private func assertSame(_ a: CGRect, _ b: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.maxX, b.maxX), (a.maxY, b.maxY)] {
            XCTAssertEqual(x, y, accuracy: 0.3, message, file: file, line: line)
        }
    }

    func testTheBoundsAreTheInkOfTheMark() throws {
        assertSame(try ink { ProvodaMark.draw($0, line: Glyph.menuLine) }, ProvodaMark.bounds,
                   "bounds of the trident in AppParts.swift are out of date")
    }

    /// scripts/make_icon.swift carries its own copy of the bounds: the same numbers, and the same 80% of the 824 px body.
    func testTheIconScriptUsesTheSameBounds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/make_icon.swift"), encoding: .utf8)
        let b = ProvodaMark.bounds
        XCTAssertTrue(script.contains("let markBounds = CGRect(x: \(b.minX), y: \(b.minY), width: \(b.width), height: \(b.height))"),
                      "scripts/make_icon.swift has other bounds than ProvodaMark.bounds")
        XCTAssertTrue(script.contains("0.8 * 824"), "the mark is 80% of the body in scripts/make_icon.swift")
        XCTAssertEqual(Glyph.iconFill, 0.8)
        XCTAssertEqual(Glyph.iconBody, 824)
        // The icon's lines are thinner: its ink is inside the bounds.
        let icon = try ink { ProvodaMark.draw($0, line: Glyph.iconLine) }
        XCTAssertTrue(b.insetBy(dx: -0.3, dy: -0.3).contains(icon))
    }

    func testTheCanvasIs22PointsTallAndTheMarkIs20() throws {
        XCTAssertEqual(MenuBarIcon.canvas.height, 22)
        XCTAssertEqual(MenuBarIcon.canvas.width, Glyph.menuCanvas(for: ProvodaMark.bounds).width)
        XCTAssertEqual(Glyph.menuScale(for: ProvodaMark.bounds) * ProvodaMark.bounds.height, 20, accuracy: 0.001)
        let pictures: [(String, NSImage, Bool)] = [("plain", MenuBarIcon.image(), false), ("update", MenuBarIcon.image(badge: true), true)]
        for (name, image, badge) in pictures {
            let width = Int(image.size.width * 4), height = Int(image.size.height * 4)
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                     bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
            var rows = (min: height, max: -1), columns = (min: width, max: -1)
            for y in 0..<height {
                for x in 0..<width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    rows = (min(rows.min, y), max(rows.max, y)); columns = (min(columns.min, x), max(columns.max, x))
                }
            }
            // 1 pt (4 px) of room above and below, and the margin at the sides: nothing reaches an edge of the canvas.
            XCTAssertGreaterThanOrEqual(rows.min, badge ? 0 : 3, name)
            XCTAssertGreaterThanOrEqual(columns.min, 3, name)
            XCTAssertLessThanOrEqual(columns.max, width - (badge ? 1 : 4), name)   // the dot is 0.5 pt from the edge
            XCTAssertLessThanOrEqual(rows.max, height - 4, name)
            if !badge && !name.contains("\u{0}") {
                XCTAssertEqual(CGFloat(rows.max - rows.min + 1) / 4, 20, accuracy: 0.6, "the trident is 20 pt tall: \(name)")
            }
        }
    }

    func testTheMarkTakesEightyPercentOfTheTileAndStaysClearOfItsCorners() {
        for bounds in [ProvodaMark.bounds] {
            let long = max(bounds.width, bounds.height)
            XCTAssertEqual(Glyph.iconScale(for: bounds) * long, 0.8 * 824, accuracy: 0.001)
            // The corners of the ink's rectangle lie well inside the tile's rounded corners (the squircle of exponent 5).
            let half = 824 / 2 as CGFloat
            let w = Glyph.iconScale(for: bounds) * bounds.width / 2, h = Glyph.iconScale(for: bounds) * bounds.height / 2
            XCTAssertLessThan(pow(w / half, 5) + pow(h / half, 5), 0.7)
        }
    }
}
