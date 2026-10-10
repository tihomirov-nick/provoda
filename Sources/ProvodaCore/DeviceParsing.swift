import Foundation

/// One interface of a USB device: what its function drivers see.
public struct USBInterface: Equatable, Sendable {
    public var interfaceClass: Int
    public var subclass: Int
    public var interfaceProtocol: Int

    public init(_ interfaceClass: Int, _ subclass: Int = 0, _ interfaceProtocol: Int = 0) {
        self.interfaceClass = interfaceClass
        self.subclass = subclass
        self.interfaceProtocol = interfaceProtocol
    }
}

/// An `IOUSBHostDevice` from its registry properties and the classes of its interfaces.
public enum USBParser {
    public static func device(id: UInt64, properties p: [String: Any], interfaces: [USBInterface] = []) -> ConnectedDevice {
        // «USB Product Name» is the registry name, with «/» turned into «_»; the descriptor's string comes first.
        let name = Props.string(p, "kUSBProductString") ?? Props.string(p, "USB Product Name") ?? L("Устройство USB")
        let vendor = (Props.string(p, "kUSBVendorString") ?? Props.string(p, "USB Vendor Name")).map(Props.vendor)
        let deviceClass = Props.int(p, "bDeviceClass") ?? 0
        let isHub = deviceClass == 9 || interfaces.contains { $0.interfaceClass == 9 }
        let allocated = Props.int(p, "UsbPowerSinkAllocation").flatMap { $0 > 0 ? $0 : nil }
        let refused = Props.int(p, "kUSBFailedRequestedPower").flatMap { $0 > 0 ? $0 : nil }
        return ConnectedDevice(
            id: id,
            name: name,
            vendor: vendor,
            kind: isHub ? .hub : kind(name: name, vendorID: Props.int(p, "idVendor") ?? 0, interfaces: interfaces),
            bus: .usb,
            link: speed(p).map { DeviceLink.usb(bitsPerSecond: $0) },
            power: allocated == nil && refused == nil ? nil : DevicePower(allocated: allocated, refused: refused),
            serial: Props.string(p, "kUSBSerialNumberString") ?? Props.string(p, "USB Serial Number"),
            isHub: isHub,
            isInternal: isInternal(p)
        )
    }

    /// The link speed in bits per second: «UsbLinkSpeed», else the speed codes of the old and the new USB stack.
    static func speed(_ p: [String: Any]) -> Double? {
        if let bps = Props.double(p, "UsbLinkSpeed"), bps > 0 { return bps }
        // kUSBDeviceSpeedLow … kUSBDeviceSpeedSuperPlusBy2
        let legacy: [Double] = [1.5e6, 12e6, 480e6, 5e9, 10e9, 20e9]
        if let code = Props.int(p, "Device Speed"), legacy.indices.contains(code) { return legacy[code] }
        // kIOUSBHostConnectionSpeedFull … kIOUSBHostConnectionSpeedSuperPlusBy2
        let host: [Int: Double] = [1: 12e6, 2: 1.5e6, 3: 480e6, 4: 5e9, 5: 10e9, 6: 20e9]
        return Props.int(p, "USBSpeed").flatMap { host[$0] }
    }

    /// On a port inside the Mac (kIOUSBHostPortTypeInternal), or marked built in.
    static func isInternal(_ p: [String: Any]) -> Bool {
        Props.int(p, "USBPortType") == 2 || (p["Built-In"] as? Bool) == true
            || Props.string(p, "non-removable")?.lowercased() == "yes"
    }

    static func kind(name: String, vendorID: Int, interfaces: [USBInterface]) -> DeviceKind {
        let classes = Set(interfaces.map(\.interfaceClass))
        let lower = name.lowercased()
        func named(_ words: String...) -> Bool { words.contains { lower.contains($0) } }

        // A display's own USB device carries its camera and speakers too: the name decides first.
        if named("display", "monitor") { return .display }
        if named("camera", "webcam", "facetime") || classes.contains(14) { return .camera }
        if vendorID == 0x05AC && named("iphone", "ipad", "ipod") { return .phone }
        // Before the phones: headphones have «phone» in the name.
        if classes.contains(1) { return .audio }
        // Still Image is how phones share photos (PTP, MTP); 0xFF/0x42 is Android's adb.
        if named("android", "phone") || classes.contains(6)
            || interfaces.contains(where: { $0.interfaceClass == 0xFF && $0.subclass == 0x42 }) {
            return .phone
        }
        if classes.contains(8) { return .storage }
        // A billboard device: a USB-C display in DisplayPort mode.
        if classes.contains(0x11) { return .display }
        if named("receiver", "dongle", "unifying", "wireless", "2.4g") || classes.contains(0xE0) { return .receiver }
        if classes.contains(3) { return .input }
        if named("lan", "ethernet", "network") || classes.contains(2) || classes.contains(10) { return .network }
        return .other
    }
}

/// A Thunderbolt or USB4 device from its `IOThunderboltSwitch` and the port it hangs off.
public enum ThunderboltParser {
    /// nil for the Mac's own controllers (depth 0).
    public static func device(id: UInt64, switchProperties p: [String: Any], port: [String: Any]?) -> ConnectedDevice? {
        guard (Props.int(p, "Depth") ?? 0) > 0 else { return nil }
        let name = Props.string(p, "Device Model Name") ?? L("Устройство Thunderbolt")
        let bps = port.flatMap(linkSpeed)
        let link = DeviceLink(name: generation(version: Props.int(p, "Thunderbolt Version") ?? 0,
                                               routerVendor: Props.int(p, "Vendor ID") ?? 0),
                              bitsPerSecond: bps)
        return ConnectedDevice(id: id, name: name, vendor: Props.string(p, "Device Vendor Name").map(Props.vendor),
                               kind: kind(name: name), bus: .thunderbolt, link: link)
    }

    /// The lane adapter's «Current Link Speed» (per lane: 8 — 10, 4 — 20, 2 — 40 Gbit/s) times its «Current Link Width»
    /// (1 and 2 lanes; 4 and 8 are the asymmetric links of USB4 v2, three lanes one way).
    static func linkSpeed(_ port: [String: Any]) -> Double? {
        let perLane: [Int: Double] = [8: 10e9, 4: 20e9, 2: 40e9]
        let lanes: [Int: Double] = [1: 1, 2: 2, 4: 3, 8: 3]
        guard let speed = Props.int(port, "Current Link Speed").flatMap({ perLane[$0] }),
              let width = Props.int(port, "Current Link Width").flatMap({ lanes[$0] }) else { return nil }
        return speed * width
    }

    /// «Thunderbolt Version» is the router's version byte: 1–3 for Thunderbolt 1–3, the USB4 major version in bits 7–5
    /// for USB4 routers. Intel's and Apple's USB4 routers are Thunderbolt 4 and 5, the rest plain USB4.
    static func generation(version: Int, routerVendor: Int) -> String {
        let thunderbolt = routerVendor == 0x8086 || routerVendor == 0x05AC
        switch version {
        case 1: return "Thunderbolt"
        case 2, 3: return "Thunderbolt \(version)"
        default:
            switch version >> 5 {
            case 1: return thunderbolt ? "Thunderbolt 4" : "USB4"
            case 2...: return thunderbolt ? "Thunderbolt 5" : "USB4 v2"
            default: return "Thunderbolt"
            }
        }
    }

    static func kind(name: String) -> DeviceKind {
        let lower = name.lowercased()
        func named(_ words: String...) -> Bool { words.contains { lower.contains($0) } }
        if named("display", "monitor", "xdr", "ultrafine") { return .display }
        if named("ssd", "drive", "disk", "raid", "nvme", "storage") { return .storage }
        if named("dock", "hub", "station") { return .dock }
        return .other
    }
}

/// Reading registry values, which come as NSNumber and NSString.
enum Props {
    static func int(_ p: [String: Any], _ key: String) -> Int? {
        (p[key] as? NSNumber)?.intValue
    }

    static func double(_ p: [String: Any], _ key: String) -> Double? {
        (p[key] as? NSNumber)?.doubleValue
    }

    static func string(_ p: [String: Any], _ key: String) -> String? {
        guard let text = (p[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    /// The maker without its legal form: «CalDigit, Inc.» is CalDigit.
    static func vendor(_ name: String) -> String {
        var name = name
        for suffix in [", Inc.", " Inc.", ", Inc", " Inc", " Co., Ltd.", " Co.,Ltd.", ", Ltd.", " Ltd.", " Corporation",
                       " Corp.", " GmbH", ", LLC", " LLC"] where name.hasSuffix(suffix) && name.count > suffix.count {
            name.removeLast(suffix.count)
            break
        }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }
}
