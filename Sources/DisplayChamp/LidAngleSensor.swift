import AppKit
import Foundation
import IOKit
import IOKit.hid

final class LidAngleSensor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private(set) var useFallback = false

    init() {
        setupHID()
    }

    private func setupHID() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else {
            useFallback = true
            return
        }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDDeviceUsagePageKey as String: 0x20,
            kIOHIDDeviceUsageKey as String: 0x8A,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) != kIOReturnSuccess {
            useFallback = true
            return
        }

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
           let first = devices.first {
            device = first
        } else {
            useFallback = true
        }

        // Verify we can actually read
        if !useFallback && readHIDAngle() == nil {
            useFallback = true
        }
    }

    func readAngle() -> Double? {
        if useFallback {
            return readFallbackAngle()
        }
        return readHIDAngle() ?? readFallbackAngle()
    }

    private func readHIDAngle() -> Double? {
        guard let device = device else { return nil }

        var report = [UInt8](repeating: 0, count: 64)
        var reportLength = report.count
        report[0] = 1

        let result = IOHIDDeviceGetReport(
            device, kIOHIDReportTypeFeature, 1, &report, &reportLength
        )
        guard result == kIOReturnSuccess else { return nil }

        let raw = Int(report[1]) | (Int(report[2]) << 8)
        let signed = raw > 32767 ? raw - 65536 : raw
        let degrees = Double(signed)

        guard degrees >= 0 && degrees <= 180 else { return nil }
        return degrees
    }

    private func readFallbackAngle() -> Double? {
        let screenHeight = NSScreen.main?.frame.height ?? 900.0
        let mouseY = NSEvent.mouseLocation.y
        let normalized = max(0.0, min(1.0, mouseY / screenHeight))
        return 80.0 + normalized * 50.0
    }

    deinit {
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
