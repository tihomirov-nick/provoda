import AppKit
import ProvodaCore
import UserNotifications

/// The app's settings in UserDefaults, read by the views through @AppStorage with the same defaults.
enum DeviceSettings {
    static let showSerialsKey = "showSerialNumbers"
    static let hideBuiltInKey = "hideBuiltInHubs"
    static let notifyKey = "notifyOnConnect"

    static var hideBuiltIn: Bool { UserDefaults.standard.object(forKey: hideBuiltInKey) as? Bool ?? true }
    static var notify: Bool { UserDefaults.standard.bool(forKey: notifyKey) }
}

/// The attached devices, read again a moment after anything is plugged in or out.
@MainActor
final class DeviceStore: ObservableObject {
    static let shared = DeviceStore()

    @Published private(set) var devices: [ConnectedDevice] = []
    private var monitor: DeviceMonitor?
    private var scanPending = false
    private var scannedOnce = false
    private var demo = false

    /// Called at launch: from then on the list follows the ports, and new devices are announced when that is on.
    func start() {
        guard monitor == nil, !demo else { return }
        let monitor = DeviceMonitor { [weak self] in
            // DeviceMonitor calls on the main queue.
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        monitor.start()
        self.monitor = monitor
        ConnectNotice.install()
        rescan()
    }

    /// The made-up devices of the preview sheet; the registry is not read.
    func showDemo() {
        demo = true
        devices = DemoDevices.all
    }

    /// A device appears in parts (its interfaces, its strings): one scan after the burst of notifications settles.
    private func scheduleScan() {
        guard !scanPending else { return }
        scanPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.scanPending = false
            self?.rescan()
        }
    }

    private func rescan() {
        let fresh = DeviceRegistry.scan()
        let known = Set(devices.map(\.id))
        if fresh != devices { devices = fresh }
        defer { scannedOnce = true }
        guard scannedOnce, DeviceSettings.notify else { return }
        for device in DeviceList.visible(fresh, hideBuiltIn: DeviceSettings.hideBuiltIn) where !known.contains(device.id) {
            ConnectNotice.post(device)
        }
    }
}

/// «Уведомлять о подключении»: a notification with the device's name and link.
@MainActor
enum ConnectNotice {
    private static let delegate = Delegate()

    /// Only an app bundle can post notifications: not `swift run`, not the tests.
    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func install() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Asked when the switch is turned on.
    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ device: ConnectedDevice) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Подключено: %@", device.name)
        content.body = [device.link?.label, device.details].compactMap { $0 }.joined(separator: "\n")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "device-\(device.id)", content: content,
                                                                     trigger: nil))
    }

    /// Shown also while the panel is open.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list])
        }
    }
}

/// `--list-devices`: one pass over the I/O Registry printed to the terminal, serial numbers masked. No windows.
enum DeviceListing {
    static func run() {
        let all = DeviceRegistry.scan()
        let shown = Set(DeviceList.visible(all, hideBuiltIn: true).map(\.id))
        for device in DeviceList.visible(all, hideBuiltIn: false) {
            var parts = [device.details]
            if let link = device.link { parts.append(link.label) }
            if let power = device.power?.label { parts.append(power) }
            if let shortage = device.power?.shortage { parts.append(shortage) }
            if let serial = device.maskedSerial { parts.append("S/N \(serial)") }
            let mark = shown.contains(device.id) ? "  " : "- "
            print("\(mark)[\(device.bus.rawValue)] \(device.name) — \(parts.joined(separator: " | "))")
        }
        print("\(shown.count) shown, \(all.count - shown.count) hidden (hubs and the Mac's own devices, marked -)")
    }
}

/// Made-up devices for the preview sheet.
enum DemoDevices {
    static let all: [ConnectedDevice] = [
        ConnectedDevice(id: 1, name: "Harbor Dock 4", vendor: "Northwind", kind: .dock, bus: .thunderbolt,
                        link: DeviceLink(name: "Thunderbolt 4", bitsPerSecond: 40e9)),
        ConnectedDevice(id: 2, name: "Kestrel SSD", vendor: "Fjordline", kind: .storage,
                        link: .usb(bitsPerSecond: 20e9), power: DevicePower(allocated: 896), serial: "KS0921-7741"),
        ConnectedDevice(id: 3, name: "Lumen 27", vendor: "Northwind", kind: .display, link: .usb(bitsPerSecond: 480e6),
                        serial: "LM27-55120"),
        ConnectedDevice(id: 4, name: "Orbis One", vendor: "Orbis", kind: .phone, link: .usb(bitsPerSecond: 480e6),
                        power: DevicePower(allocated: 500), serial: "ORB1X2Q9"),
        ConnectedDevice(id: 5, name: "Nano Receiver", vendor: "Tallis", kind: .receiver, link: .usb(bitsPerSecond: 12e6)),
        ConnectedDevice(id: 6, name: "Hub 3.2", vendor: "Northwind", kind: .hub, link: .usb(bitsPerSecond: 10e9),
                        isHub: true),
    ]
}
