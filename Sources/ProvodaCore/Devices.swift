import Foundation

/// How a device is attached to the Mac.
public enum DeviceBus: String, Sendable {
    case usb
    case thunderbolt
}

/// What a device is: its icon and its type in the list.
public enum DeviceKind: String, CaseIterable, Sendable {
    case phone, display, storage, receiver, hub, dock, input, audio, camera, network, other

    public var title: String {
        switch self {
        case .phone: return L("Телефон")
        case .display: return L("Монитор")
        case .storage: return L("Накопитель")
        case .receiver: return L("Приёмник")
        case .hub: return L("Хаб")
        case .dock: return L("Док-станция")
        case .input: return L("Клавиатура или мышь")
        case .audio: return L("Аудио")
        case .camera: return L("Камера")
        case .network: return L("Сетевой адаптер")
        case .other: return L("Устройство")
        }
    }

    /// The SF Symbol of the kind.
    public var symbol: String {
        switch self {
        case .phone: return "iphone"
        case .display: return "display"
        case .storage: return "externaldrive"
        case .receiver: return "dot.radiowaves.left.and.right"
        case .hub: return "point.3.connected.trianglepath.dotted"
        case .dock: return "dock.rectangle"
        case .input: return "keyboard"
        case .audio: return "headphones"
        case .camera: return "web.camera"
        case .network: return "network"
        case .other: return "cable.connector"
        }
    }
}

/// The link a device works over: the protocol and, when known, the speed it runs at now.
public struct DeviceLink: Equatable, Sendable {
    /// «USB 2.0», «USB 3.2 Gen 2», «Thunderbolt 4».
    public var name: String
    public var bitsPerSecond: Double?

    public init(name: String, bitsPerSecond: Double?) {
        self.name = name
        self.bitsPerSecond = bitsPerSecond
    }

    /// The USB generation that runs at this speed.
    public static func usb(bitsPerSecond bps: Double) -> DeviceLink {
        let name: String
        switch bps {
        case ..<100e6: name = "USB 1.1"
        case ..<1e9: name = "USB 2.0"
        case ..<7e9: name = "USB 3.2 Gen 1"
        case ..<15e9: name = "USB 3.2 Gen 2"
        case ..<30e9: name = "USB 3.2 Gen 2×2"
        default: name = "USB4"
        }
        return DeviceLink(name: name, bitsPerSecond: bps)
    }

    /// «USB 3.2 Gen 2 · 10 Гбит/с», or the protocol alone.
    public var label: String {
        guard let bps = bitsPerSecond else { return name }
        return "\(name) · \(Format.speed(bps))"
    }
}

/// The power a USB device takes from the 5 V bus, in mA, as the I/O Registry reports it.
public struct DevicePower: Equatable, Sendable {
    /// What the Mac gave the device («UsbPowerSinkAllocation»).
    public var allocated: Int?
    /// What the device asked for and did not get («kUSBFailedRequestedPower»).
    public var refused: Int?

    public init(allocated: Int? = nil, refused: Int? = nil) {
        self.allocated = allocated
        self.refused = refused
    }

    /// «0,92 Вт».
    public var label: String? {
        allocated.map { Format.watts(milliamps: $0) }
    }

    /// A warning when the device wanted more than the port could give.
    public var shortage: String? {
        refused.map { L("Просит %@, питания не хватает", Format.watts(milliamps: $0)) }
    }
}

/// One device in the list.
public struct ConnectedDevice: Identifiable, Equatable, Sendable {
    /// The registry entry ID: new for every connection.
    public var id: UInt64
    public var name: String
    public var vendor: String?
    public var kind: DeviceKind
    public var bus: DeviceBus
    public var link: DeviceLink?
    public var power: DevicePower?
    public var serial: String?
    /// A hub chip: in a dongle, a display, a dock or a hub of its own. The devices behind it are listed by themselves.
    public var isHub: Bool
    /// One of the Mac's own devices, on a port inside it.
    public var isInternal: Bool

    public init(id: UInt64, name: String, vendor: String? = nil, kind: DeviceKind, bus: DeviceBus = .usb,
                link: DeviceLink? = nil, power: DevicePower? = nil, serial: String? = nil, isHub: Bool = false,
                isInternal: Bool = false) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.kind = kind
        self.bus = bus
        self.link = link
        self.power = power
        self.serial = serial
        self.isHub = isHub
        self.isInternal = isInternal
    }

    /// «Realtek · Сетевой адаптер».
    public var details: String {
        [vendor, kind.title].compactMap { $0 }.joined(separator: " · ")
    }

    /// The serial number with every character hidden, for printing.
    public var maskedSerial: String? {
        serial.map { String(repeating: "•", count: min(max($0.count, 4), 12)) }
    }
}

/// What the list shows.
public enum DeviceList {
    /// Without hubs and the Mac's own devices when `hideBuiltIn` is on; Thunderbolt first, then by name.
    public static func visible(_ devices: [ConnectedDevice], hideBuiltIn: Bool) -> [ConnectedDevice] {
        devices
            .filter { !hideBuiltIn || !($0.isHub || $0.isInternal) }
            .sorted {
                if $0.bus != $1.bus { return $0.bus == .thunderbolt }
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }

    /// The devices whose name, maker, type or link has every word of `query`; the serial number counts when it is shown.
    public static func search(_ devices: [ConnectedDevice], query: String, showSerials: Bool) -> [ConnectedDevice] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return devices }
        return devices.filter { device in
            let text = [device.name, device.vendor, device.kind.title, device.link?.label, showSerials ? device.serial : nil]
                .compactMap { $0 }.joined(separator: " ")
            return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

/// Numbers in the interface language: «1,5 Мбит/с» in Russian, «1.5 Mbit/s» in English.
public enum Format {
    public static func speed(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1e9 ? L("%@ Гбит/с", number(bitsPerSecond / 1e9)) : L("%@ Мбит/с", number(bitsPerSecond / 1e6))
    }

    /// The power of a current from the 5 V USB bus.
    public static func watts(milliamps: Int) -> String {
        L("%@ Вт", number(Double(milliamps) * 5 / 1000))
    }

    /// Up to two decimals, without trailing zeros.
    static func number(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return Localization.current == "ru" ? text.replacingOccurrences(of: ".", with: ",") : text
    }
}
