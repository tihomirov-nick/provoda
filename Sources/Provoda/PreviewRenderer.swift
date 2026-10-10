import AppKit
import SwiftUI

/// `--render-previews <folder>`: the menu bar icon, the panel under it and Settings drawn into one picture,
/// <folder>/preview.png, through hosting views in windows that are never shown. Nothing starts: no status item, no
/// updater, no login item.
@MainActor
enum PreviewRenderer {
    static func run(into folder: URL) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Provoda: made-up devices; the second panel is the same list with serial numbers and hubs shown.
        DeviceStore.shared.showDemo()
        guard let panel = snapshot(PanelView()), let settings = snapshot(SettingsWindow.makeWindow()) else {
            print("failed to draw the views")
            return
        }
        // The registration domain only: nothing is written to the preferences.
        UserDefaults.standard.register(defaults: [DeviceSettings.showSerialsKey: true, DeviceSettings.hideBuiltInKey: false])
        guard let second = snapshot(PanelView()) else {
            print("failed to draw the views")
            return
        }
        let margin: CGFloat = 24, bar: CGFloat = 24, zoom: CGFloat = 4
        let left = max(panel.size.width, 160)
        let width = margin + left + margin + second.size.width + margin + settings.size.width + margin
        let height = margin + max(bar + 6 + max(panel.size.height + margin + MenuBarIcon.canvas.height * zoom,
                                                second.size.height),
                                  settings.size.height) + margin
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.17, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        // A strip of menu bar with the icon at its real size, the panel under it.
        let top = height - margin
        let strip = NSRect(x: margin, y: top - bar, width: left, height: bar)
        NSColor(white: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: strip, xRadius: 6, yRadius: 6).fill()
        let icon = white(MenuBarIcon.image())
        let iconRect = NSRect(x: strip.midX - MenuBarIcon.canvas.width / 2, y: strip.midY - MenuBarIcon.canvas.height / 2,
                              width: MenuBarIcon.canvas.width, height: MenuBarIcon.canvas.height)
        icon.draw(in: iconRect)
        let panelRect = NSRect(x: strip.midX - panel.size.width / 2, y: strip.minY - 6 - panel.size.height,
                               width: panel.size.width, height: panel.size.height)
        NSGraphicsContext.current?.cgContext.draw(panel.image, in: panelRect)
        // The icon with the dot of an update, four times larger.
        let large = NSSize(width: MenuBarIcon.canvas.width * zoom, height: MenuBarIcon.canvas.height * zoom)
        white(MenuBarIcon.image(badge: true)).draw(in: NSRect(x: strip.midX - large.width / 2,
                                                              y: panelRect.minY - margin - large.height,
                                                              width: large.width, height: large.height))
        // The second panel next to the first.
        let secondRect = NSRect(x: margin + left + margin, y: strip.minY - 6 - second.size.height,
                                width: second.size.width, height: second.size.height)
        NSGraphicsContext.current?.cgContext.draw(second.image, in: secondRect)
        // Settings on the right.
        let settingsRect = NSRect(x: secondRect.maxX + margin, y: top - settings.size.height,
                                  width: settings.size.width, height: settings.size.height)
        NSGraphicsContext.current?.cgContext.draw(settings.image, in: settingsRect)
        NSGraphicsContext.restoreGraphicsState()

        let url = folder.appendingPathComponent("preview.png")
        if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil {
            print("wrote \(url.path)")
        } else {
            print("failed to write \(url.path)")
        }
    }

    /// The view as drawn by a real hosting view, at its own size.
    private static func snapshot<V: View>(_ view: V) -> (image: CGImage, size: NSSize)? {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.cgImage.map { ($0, size) }
    }

    /// A window with its title bar, never ordered on screen.
    private static func snapshot(_ window: NSWindow) -> (image: CGImage, size: NSSize)? {
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let frame = window.contentView?.superview else { return nil }
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return nil }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        return rep.cgImage.map { ($0, frame.bounds.size) }
    }

    /// A template image in white, as the dark menu bar shows it.
    private static func white(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
