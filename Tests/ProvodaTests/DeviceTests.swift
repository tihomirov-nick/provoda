import AppKit
import XCTest
@testable import Provoda
@testable import ProvodaCore

/// Registry properties turned into list rows. The USB dictionaries were taken from a Mac (ioreg -p IOUSB -l) with the
/// serial numbers replaced; the Thunderbolt router of the Mac itself too, the connected routers use the same keys.
/// No live hardware: `swift test` reads nothing from the registry. Texts are Russian, the tests run without en.lproj.
final class DeviceTests: XCTestCase {
    // MARK: Captured USB devices

    /// A USB-C Ethernet adapter behind a dongle's hub: the descriptor name has «/», the registry name «_».
    private let ethernet: [String: Any] = [
        "bDeviceClass": 0, "UsbLinkSpeed": 5_000_000_000, "bDeviceSubClass": 0, "iProduct": 2,
        "USB Vendor Name": "Realtek", "USBSpeed": 4, "bNumConfigurations": 2, "kUSBProductString": "USB 10/100/1000 LAN",
        "kUSBVendorString": "Realtek", "USB Product Name": "USB 10_100_1000 LAN", "kUSBHostDeviceEnableLPM": false,
        "iManufacturer": 1, "idVendor": 3034, "Device Speed": 3, "kUSBCurrentConfiguration": 2, "idProduct": 33107,
        "bcdDevice": 12797, "USB Address": 3, "kUSBPreferredConfiguration": 2, "USBPortType": 0,
        "UsbPowerSinkAllocation": 184, "bDeviceProtocol": 0, "locationID": 35_848_192, "kUSBAddress": 3, "bcdUSB": 800,
        "bMaxPacketSize0": 9, "kUSBSerialNumberString": "TEST000001", "USB Serial Number": "TEST000001",
    ]
    private let ethernetInterfaces = [USBInterface(2, 6, 0), USBInterface(10, 0, 0)]

    private let receiver: [String: Any] = [
        "bDeviceClass": 0, "UsbLinkSpeed": 12_000_000, "USBSpeed": 1, "Device Speed": 1, "USBPortType": 0,
        "kUSBProductString": "2.4G Wireless Receiver", "USB Product Name": "2.4G Wireless Receiver",
        "kUSBVendorString": "Compx", "USB Vendor Name": "Compx", "idVendor": 9639, "idProduct": 64124, "bcdUSB": 272,
    ]
    private let receiverInterfaces = [USBInterface(3, 1, 2), USBInterface(3, 1, 1)]

    private let hub: [String: Any] = [
        "bDeviceClass": 9, "bDeviceProtocol": 3, "UsbLinkSpeed": 10_000_000_000, "USBSpeed": 5, "Device Speed": 4,
        "kUSBProductString": "USB3.2 Hub", "USB Product Name": "USB3.2 Hub", "kUSBVendorString": "GenesysLogic",
        "USB Vendor Name": "GenesysLogic", "idVendor": 1507, "idProduct": 1573, "bcdUSB": 800, "USBPortType": 5,
        "kUSBWakePortCurrentLimit": 3000, "kUSBSleepPortCurrentLimit": 3000,
    ]

    private func usb(_ properties: [String: Any], _ interfaces: [USBInterface] = [], id: UInt64 = 1) -> ConnectedDevice {
        USBParser.device(id: id, properties: properties, interfaces: interfaces)
    }

    func testEthernetAdapter() {
        let device = usb(ethernet, ethernetInterfaces)
        XCTAssertEqual(device.name, "USB 10/100/1000 LAN")
        XCTAssertEqual(device.vendor, "Realtek")
        XCTAssertEqual(device.kind, .network)
        XCTAssertEqual(device.details, "Realtek · Сетевой адаптер")
        XCTAssertEqual(device.link?.label, "USB 3.2 Gen 1 · 5 Гбит/с")
        XCTAssertEqual(device.power?.label, "0,92 Вт")
        XCTAssertNil(device.power?.shortage)
        XCTAssertEqual(device.serial, "TEST000001")
        XCTAssertFalse(device.isHub)
        XCTAssertFalse(device.isInternal)
    }

    func testWirelessReceiver() {
        let device = usb(receiver, receiverInterfaces)
        XCTAssertEqual(device.kind, .receiver)
        XCTAssertEqual(device.link?.label, "USB 1.1 · 12 Мбит/с")
        XCTAssertNil(device.power)
        XCTAssertNil(device.serial)
    }

    func testHubsAreHubsAndHiddenByDefault() {
        let device = usb(hub, [USBInterface(9, 0, 0)])
        XCTAssertTrue(device.isHub)
        XCTAssertEqual(device.kind, .hub)
        XCTAssertEqual(device.link?.label, "USB 3.2 Gen 2 · 10 Гбит/с")
        XCTAssertTrue(DeviceList.visible([device], hideBuiltIn: true).isEmpty)
        XCTAssertEqual(DeviceList.visible([device], hideBuiltIn: false), [device])
    }

    // MARK: Speed, power and the Mac's own devices

    func testSpeedCodesWithoutTheLinkSpeed() {
        // The old stack's code: kUSBDeviceSpeedLow … SuperPlusBy2.
        let codes = [0: "USB 1.1 · 1,5 Мбит/с", 1: "USB 1.1 · 12 Мбит/с", 2: "USB 2.0 · 480 Мбит/с",
                     3: "USB 3.2 Gen 1 · 5 Гбит/с", 4: "USB 3.2 Gen 2 · 10 Гбит/с", 5: "USB 3.2 Gen 2×2 · 20 Гбит/с"]
        for (code, label) in codes {
            XCTAssertEqual(usb(["Device Speed": code]).link?.label, label)
        }
        // The new stack's code alone: kIOUSBHostConnectionSpeedLow is 2, High is 3.
        XCTAssertEqual(usb(["USBSpeed": 2]).link?.label, "USB 1.1 · 1,5 Мбит/с")
        XCTAssertEqual(usb(["USBSpeed": 3]).link?.label, "USB 2.0 · 480 Мбит/с")
        XCTAssertEqual(usb(["USBSpeed": 6]).link?.label, "USB 3.2 Gen 2×2 · 20 Гбит/с")
        XCTAssertNil(usb(["kUSBProductString": "Mystery"]).link)
    }

    func testRefusedPower() {
        let device = usb(["kUSBProductString": "Big Drive", "UsbPowerSinkAllocation": 500, "kUSBFailedRequestedPower": 900],
                         [USBInterface(8, 6, 80)])
        XCTAssertEqual(device.kind, .storage)
        XCTAssertEqual(device.power?.label, "2,5 Вт")
        XCTAssertEqual(device.power?.shortage, "Просит 4,5 Вт, питания не хватает")
        XCTAssertEqual(usb(["UsbPowerSinkAllocation": 0]).power, nil)
    }

    func testTheMacsOwnDevicesAreHidden() {
        let keyboard = usb(["kUSBProductString": "Apple Internal Keyboard / Trackpad", "USBPortType": 2], [USBInterface(3, 1, 1)])
        XCTAssertTrue(keyboard.isInternal)
        XCTAssertEqual(keyboard.kind, .input)
        XCTAssertTrue(usb(["Built-In": true]).isInternal)
        XCTAssertTrue(usb(["non-removable": "yes"]).isInternal)
        // A captive port (a display's camera) is not the Mac's.
        XCTAssertFalse(usb(["USBPortType": 1]).isInternal)
        XCTAssertTrue(DeviceList.visible([keyboard], hideBuiltIn: true).isEmpty)
    }

    func testKinds() {
        XCTAssertEqual(usb(["kUSBProductString": "iPhone", "idVendor": 0x05AC], [USBInterface(6, 1, 1), USBInterface(0xFF, 0xFE, 2)]).kind, .phone)
        XCTAssertEqual(usb(["kUSBProductString": "Pixel 8"], [USBInterface(0xFF, 0x42, 1)]).kind, .phone)
        XCTAssertEqual(usb(["kUSBProductString": "USB Headphones"], [USBInterface(1, 1, 0), USBInterface(3, 0, 0)]).kind, .audio)
        XCTAssertEqual(usb(["kUSBProductString": "Studio Display"], [USBInterface(14, 1, 0), USBInterface(1, 1, 0)]).kind, .display)
        XCTAssertEqual(usb(["kUSBProductString": "HD Webcam"], [USBInterface(14, 1, 0)]).kind, .camera)
        XCTAssertEqual(usb(["kUSBProductString": "Keyboard K120"], [USBInterface(3, 1, 1)]).kind, .input)
        XCTAssertEqual(usb(["kUSBProductString": "Billboard Device"], [USBInterface(0x11, 0, 0)]).kind, .display)
        XCTAssertEqual(usb(["kUSBProductString": "Bluetooth Adapter"], [USBInterface(0xE0, 1, 1)]).kind, .receiver)
        XCTAssertEqual(usb([:]).name, "Устройство USB")
        XCTAssertEqual(usb([:]).kind, .other)
    }

    // MARK: Thunderbolt

    /// The Mac's own router, as the registry has it: depth 0, so not a device.
    private let macRouter: [String: Any] = [
        "Device Vendor ID": 1, "Device Vendor Name": "Apple Inc.", "Device Model Name": "iOS", "Upstream Port Number": 7,
        "Max Port Number": 7, "Thunderbolt Version": 64, "ROM Version": 0, "Device ID": 8206, "Revision ID": 0,
        "Route String": 0, "Device Model ID": 15, "Device Model Revision": 1, "EEPROM Revision": 0, "Router ID": 0,
        "Vendor ID": 1452, "Depth": 0,
    ]

    private func router(_ name: String, vendor: String, version: Int, routerVendor: Int) -> [String: Any] {
        ["Device Model Name": name, "Device Vendor Name": vendor, "Thunderbolt Version": version, "Vendor ID": routerVendor,
         "Depth": 1, "Route String": 1, "Upstream Port Number": 1]
    }

    private func port(speed: Int, width: Int) -> [String: Any] {
        ["Description": "Thunderbolt Port", "Current Link Speed": speed, "Current Link Width": width,
         "Supported Link Speed": 14, "Supported Link Width": 2, "Port Number": 1]
    }

    func testTheMacsOwnRouterIsNotADevice() {
        XCTAssertNil(ThunderboltParser.device(id: 1, switchProperties: macRouter, port: port(speed: 0, width: 0)))
    }

    func testThunderboltDevices() throws {
        let dock = try XCTUnwrap(ThunderboltParser.device(
            id: 7, switchProperties: router("TS4", vendor: "CalDigit, Inc.", version: 0x20, routerVendor: 0x8086),
            port: port(speed: 4, width: 2)))
        XCTAssertEqual(dock.link?.label, "Thunderbolt 4 · 40 Гбит/с")
        XCTAssertEqual(dock.vendor, "CalDigit")
        XCTAssertEqual(dock.bus, .thunderbolt)
        XCTAssertNil(dock.serial)

        let five = ThunderboltParser.device(id: 8, switchProperties: router("Thunderbolt 5 Dock", vendor: "Example", version: 0x40,
                                                                          routerVendor: 0x8086),
                                            port: port(speed: 2, width: 2))
        XCTAssertEqual(five?.link?.label, "Thunderbolt 5 · 80 Гбит/с")
        XCTAssertEqual(five?.kind, .dock)
        let asymmetric = ThunderboltParser.device(id: 9, switchProperties: router("Pro Display", vendor: "Example", version: 0x40,
                                                                                routerVendor: 0x05AC),
                                                  port: port(speed: 2, width: 4))
        XCTAssertEqual(asymmetric?.link?.label, "Thunderbolt 5 · 120 Гбит/с")
        XCTAssertEqual(asymmetric?.kind, .display)

        let three = ThunderboltParser.device(id: 10, switchProperties: router("Studio", vendor: "Example", version: 3, routerVendor: 0x8086),
                                             port: port(speed: 4, width: 2))
        XCTAssertEqual(three?.link?.label, "Thunderbolt 3 · 40 Гбит/с")
        // ASMedia's USB4 controller in an SSD enclosure; the link is down for a moment.
        let ssd = ThunderboltParser.device(id: 11, switchProperties: router("USB4 NVMe SSD", vendor: "Example", version: 0x20,
                                                                          routerVendor: 0x174C),
                                           port: port(speed: 0, width: 0))
        XCTAssertEqual(ssd?.link?.label, "USB4")
        XCTAssertEqual(ssd?.kind, .storage)
    }

    // MARK: The list

    func testOrderAndSearch() {
        let tb = ThunderboltParser.device(id: 20, switchProperties: router("Zeta Dock", vendor: "Example", version: 0x20,
                                                                         routerVendor: 0x8086),
                                          port: port(speed: 4, width: 2))!
        let all = [usb(ethernet, ethernetInterfaces, id: 2), usb(hub, id: 3), usb(receiver, receiverInterfaces, id: 4), tb]
        let shown = DeviceList.visible(all, hideBuiltIn: true)
        XCTAssertEqual(shown.map(\.id), [20, 4, 2])
        XCTAssertEqual(DeviceList.search(shown, query: "realtek", showSerials: false).map(\.id), [2])
        XCTAssertEqual(DeviceList.search(shown, query: "5 гбит", showSerials: false).map(\.id), [2])
        XCTAssertEqual(DeviceList.search(shown, query: "приёмник", showSerials: false).map(\.id), [4])
        XCTAssertEqual(DeviceList.search(shown, query: "  ", showSerials: false).count, 3)
        // The serial number is searched only while it is shown.
        XCTAssertTrue(DeviceList.search(shown, query: "TEST000001", showSerials: false).isEmpty)
        XCTAssertEqual(DeviceList.search(shown, query: "TEST000001", showSerials: true).map(\.id), [2])
    }

    func testMaskedSerialShowsNoCharacters() {
        let masked = usb(ethernet).maskedSerial ?? ""
        XCTAssertFalse(masked.contains("T"))
        XCTAssertEqual(Set(masked), ["•"])
    }

    func testEveryKindHasASymbol() {
        for kind in DeviceKind.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil), kind.symbol)
        }
    }

    @MainActor
    func testTheDemoHasAHiddenHub() {
        XCTAssertEqual(DeviceList.visible(DemoDevices.all, hideBuiltIn: true).count, DemoDevices.all.count - 1)
    }
}
