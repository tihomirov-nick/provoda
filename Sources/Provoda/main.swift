import AppKit
import ProvodaCore

Localization.apply()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments
    // Draws the panel, Settings and the icon into one picture without showing anything on screen, then quits.
    if let i = arguments.firstIndex(of: "--render-previews"), i + 1 < arguments.count {
        app.setActivationPolicy(.prohibited)
        PreviewRenderer.run(into: URL(fileURLWithPath: arguments[i + 1], isDirectory: true))
        exit(0)
    }
    // Prints the attached devices from the I/O Registry, serial numbers masked, then quits.
    if arguments.contains("--list-devices") {
        DeviceListing.run()
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
