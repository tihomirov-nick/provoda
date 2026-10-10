import Foundation
import IOKit

/// Reads what is attached from the I/O Registry: every `IOUSBHostDevice` and every Thunderbolt or USB4 router
/// (`IOThunderboltSwitch`) that is not the Mac's own.
public enum DeviceRegistry {
    public static func scan() -> [ConnectedDevice] {
        var devices: [ConnectedDevice] = []
        forEachService(of: "IOUSBHostDevice") { service in
            guard let properties = properties(of: service) else { return }
            devices.append(USBParser.device(id: entryID(service), properties: properties, interfaces: interfaces(of: service)))
        }
        forEachService(of: "IOThunderboltSwitch") { service in
            guard let properties = properties(of: service),
                  let device = ThunderboltParser.device(id: entryID(service), switchProperties: properties,
                                                        port: linkPort(of: service, properties: properties)) else { return }
            devices.append(device)
        }
        return devices
    }

    /// The interfaces of a USB device: its `IOUSBHostInterface` children.
    static func interfaces(of device: io_service_t) -> [USBInterface] {
        children(of: device).compactMap { child in
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOUSBHostInterface") != 0,
                  let interfaceClass = number(child, "bInterfaceClass") else { return nil }
            return USBInterface(interfaceClass, number(child, "bInterfaceSubClass") ?? 0, number(child, "bInterfaceProtocol") ?? 0)
        }
    }

    /// The lane adapter the router hangs off (its parent in the service plane), else the router's own upstream port.
    static func linkPort(of router: io_service_t, properties: [String: Any]) -> [String: Any]? {
        var parent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(router, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer { IOObjectRelease(parent) }
            if IOObjectConformsTo(parent, "IOThunderboltPort") != 0, let port = self.properties(of: parent),
               ThunderboltParser.linkSpeed(port) != nil {
                return port
            }
        }
        let upstream = Props.int(properties, "Upstream Port Number")
        var found: [String: Any]?
        for child in children(of: router) {
            defer { IOObjectRelease(child) }
            guard found == nil, IOObjectConformsTo(child, "IOThunderboltPort") != 0,
                  let port = self.properties(of: child), Props.int(port, "Port Number") == upstream else { continue }
            found = port
        }
        return found
    }

    // MARK: I/O Kit plumbing

    static func forEachService(of className: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            body(service)
            IOObjectRelease(service)
        }
    }

    /// The children in the service plane; the caller releases them.
    static func children(of entry: io_registry_entry_t) -> [io_registry_entry_t] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [io_registry_entry_t] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            result.append(child)
        }
        return result
    }

    static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var dictionary: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &dictionary, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return dictionary?.takeRetainedValue() as? [String: Any]
    }

    static func number(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
    }

    static func entryID(_ entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }
}

/// Calls `changed` on the main queue after a USB device or a Thunderbolt router appears or goes away.
public final class DeviceMonitor {
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private let changed: () -> Void

    public init(changed: @escaping () -> Void) {
        self.changed = changed
    }

    deinit {
        stop()
    }

    public func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            DeviceMonitor.drain(iterator)
            guard let context else { return }
            Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue().changed()
        }
        for className in ["IOUSBHostDevice", "IOThunderboltSwitch"] {
            for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var iterator: io_iterator_t = 0
                guard IOServiceAddMatchingNotification(port, type, IOServiceMatching(className), callback, context,
                                                       &iterator) == KERN_SUCCESS else { continue }
                // Emptying the iterator arms the notification; what is attached already comes from the first scan.
                Self.drain(iterator)
                iterators.append(iterator)
            }
        }
    }

    public func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let object = IOIteratorNext(iterator), object != 0 {
            IOObjectRelease(object)
        }
    }
}
