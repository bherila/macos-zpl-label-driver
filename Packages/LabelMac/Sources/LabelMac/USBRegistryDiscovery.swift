import Foundation
import IOKit
import IOKit.usb
import LabelCore

/// Session-only registry observation, never a stable transport/device capability.
public struct USBPrinterObservation: Equatable, Sendable, Identifiable,
    RedactedDiagnosticValue {
    public let id: UUID
    public let vendorID: UInt16
    public let productID: UInt16
    public let interfaceNumber: UInt8
    private let registryEntryID: UInt64

    /// Display text for the picker, built here so it is testable rather than
    /// inline in a view body.
    ///
    /// A vendor or product ID is an identifier, not a quantity. Interpolating
    /// the integers straight into a SwiftUI `Text` runs them through the
    /// viewer's locale number format, which rendered VID 0x0A5F as "2,655" --
    /// a thousands separator inside an identifier, and a value that matches
    /// nothing a USB tool prints. Interpolating an already-formatted `String`
    /// keeps the locale out of it, and hex is what `system_profiler` and the
    /// USB-IF registry use, so the value can be cross-checked as written.
    ///
    /// Deliberately not `description`: `RedactedDiagnosticValue` redacts that
    /// so these values never reach a log, and this text is for the screen the
    /// viewer is already looking at.
    public var interfaceLabel: String {
        String(format: "USB VID 0x%04X, PID 0x%04X, interface %u",
               UInt32(vendorID), UInt32(productID), UInt32(interfaceNumber))
    }

    init(registryEntryID: UInt64, vendorID: UInt16, productID: UInt16, interfaceNumber: UInt8) {
        id = UUID()
        self.registryEntryID = registryEntryID
        self.vendorID = vendorID
        self.productID = productID
        self.interfaceNumber = interfaceNumber
    }

}

public struct USBRegistryDiscoverySnapshot: Equatable, Sendable {
    public let scannedInterfaces: Int
    public let unreadableInterfaceClasses: Int
    public let printers: [USBPrinterObservation]
}

/// Read-only seams preserve native handle lifetime and permit deterministic faults.
protocol USBInterfaceRegistryAccess {
    func matchingInterfaces() throws -> io_iterator_t
    func next(_ iterator: io_iterator_t) -> io_object_t
    func isValid(_ iterator: io_iterator_t) -> Bool
    func release(_ object: io_object_t)
    func interfaceClass(_ interface: io_object_t) -> UInt8?
    func printerObservation(_ interface: io_object_t) throws -> USBPrinterObservation
}

public enum USBRegistryDiscovery {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unavailable
        case changed
        case interfaceLimit
        case unreadablePrinterMetadata
    }

    public static func snapshot() throws -> USBRegistryDiscoverySnapshot {
        try snapshot(access: NativeUSBInterfaceRegistryAccess(), maximumInterfaces: 4096)
    }

    static func snapshot(access: any USBInterfaceRegistryAccess,
                         maximumInterfaces: Int) throws -> USBRegistryDiscoverySnapshot {
        guard (1...4096).contains(maximumInterfaces) else { throw Error.interfaceLimit }
        try Task.checkCancellation()
        let iterator = try access.matchingInterfaces()
        // IOKitLib.h permits successful empty matching with a null iterator.
        guard iterator != 0 else {
            return .init(scannedInterfaces: 0, unreadableInterfaceClasses: 0, printers: [])
        }
        defer { access.release(iterator) }
        var scanned = 0, unreadable = 0
        var printers: [USBPrinterObservation] = []
        while true {
            try Task.checkCancellation()
            let entry = access.next(iterator)
            if entry == 0 { break }
            defer { access.release(entry) }
            guard scanned < maximumInterfaces else { throw Error.interfaceLimit }
            scanned += 1
            guard let interfaceClass = access.interfaceClass(entry) else {
                unreadable += 1
                continue
            }
            // USB printer interface class is an observation, not ZPL/model support.
            if interfaceClass == 7 { printers.append(try access.printerObservation(entry)) }
        }
        try Task.checkCancellation()
        guard access.isValid(iterator) else { throw Error.changed }
        return .init(scannedInterfaces: scanned, unreadableInterfaceClasses: unreadable, printers: printers)
    }

    static func unsignedNumber(_ property: CFTypeRef?, maximum: UInt64) -> UInt64? {
        guard let property, CFGetTypeID(property) == CFNumberGetTypeID(),
              let number = property as? NSNumber else { return nil }
        let signed = number.int64Value
        guard signed >= 0, number.doubleValue == Double(signed), UInt64(signed) <= maximum else { return nil }
        return UInt64(signed)
    }
}

private struct NativeUSBInterfaceRegistryAccess: USBInterfaceRegistryAccess {
    func matchingInterfaces() throws -> io_iterator_t {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(kIOUSBHostInterfaceClassName),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw USBRegistryDiscovery.Error.unavailable
        }
        return iterator
    }
    func next(_ iterator: io_iterator_t) -> io_object_t { IOIteratorNext(iterator) }
    func isValid(_ iterator: io_iterator_t) -> Bool { IOIteratorIsValid(iterator) != 0 }
    func release(_ object: io_object_t) { IOObjectRelease(object) }
    func interfaceClass(_ interface: io_object_t) -> UInt8? {
        number(interface, kUSBHostMatchingPropertyInterfaceClass, maximum: 255).map(UInt8.init)
    }

    func printerObservation(_ interface: io_object_t) throws -> USBPrinterObservation {
        guard let interfaceNumber = number(interface, kUSBHostMatchingPropertyInterfaceNumber, maximum: 255) else {
            throw USBRegistryDiscovery.Error.unreadablePrinterMetadata
        }
        return try deviceObservation(parentOf: interface, interfaceNumber: UInt8(interfaceNumber), remaining: 8)
    }

    private func deviceObservation(parentOf entry: io_object_t, interfaceNumber: UInt8,
                                   remaining: Int) throws -> USBPrinterObservation {
        guard remaining > 0 else { throw USBRegistryDiscovery.Error.unreadablePrinterMetadata }
        try Task.checkCancellation()
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS, parent != 0 else {
            throw USBRegistryDiscovery.Error.unreadablePrinterMetadata
        }
        defer { IOObjectRelease(parent) }
        if IOObjectConformsTo(parent, kIOUSBHostDeviceClassName) == 0 {
            return try deviceObservation(parentOf: parent, interfaceNumber: interfaceNumber, remaining: remaining - 1)
        }
        var registryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(parent, &registryID) == KERN_SUCCESS,
              let vendor = number(parent, kUSBHostMatchingPropertyVendorID, maximum: 65535),
              let product = number(parent, kUSBHostMatchingPropertyProductID, maximum: 65535) else {
            throw USBRegistryDiscovery.Error.unreadablePrinterMetadata
        }
        return .init(registryEntryID: registryID, vendorID: UInt16(vendor), productID: UInt16(product),
                     interfaceNumber: interfaceNumber)
    }

    private func number(_ entry: io_object_t, _ key: String, maximum: UInt64) -> UInt64? {
        USBRegistryDiscovery.unsignedNumber(
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
            maximum: maximum)
    }
}
