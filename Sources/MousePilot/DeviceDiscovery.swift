import Foundation
import IOKit.hid

struct MouseDevice: Identifiable, Sendable {
    let id: String
    let name: String
    let transport: String
}

enum DeviceDiscovery {
    /// Enumerates HID metadata without opening, seizing, or reading input from a device.
    static func mice() -> [MouseDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Int] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        var seen = Set<String>()
        return devices.compactMap { device in
            let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "HID 마우스"
            if name.localizedCaseInsensitiveContains("trackpad") { return nil }
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "HID"
            let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let id = "\(vendor):\(product):\(location):\(name)"
            guard seen.insert(id).inserted else { return nil }
            return .init(id: id, name: name, transport: transport)
        }.sorted { $0.name < $1.name }
    }
}
