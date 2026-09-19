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
    /// What the scan found where a serial number would be. Private, because a
    /// serial number is the one field here that names a *unit*: it must not
    /// reach a log, a diagnostic dump or a committed file. `LabelCore` keeps
    /// the payload internal to itself, so even inside this module the string
    /// cannot be read back out -- only handed to qualification.
    private let serialNumber: USBSerialNumberReading

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

    init(registryEntryID: UInt64, vendorID: UInt16, productID: UInt16, interfaceNumber: UInt8,
         serialNumber: USBSerialNumberReading = .absent) {
        id = UUID()
        self.registryEntryID = registryEntryID
        self.vendorID = vendorID
        self.productID = productID
        self.interfaceNumber = interfaceNumber
        self.serialNumber = serialNumber
    }

    /// Whether the scan read a serial-number string at all.
    ///
    /// This is a fact about the scan and nothing more. It is not an identity,
    /// it is not a qualification, and `true` here does not mean the string is
    /// usable -- `qualifiedIdentity(digest:)` decides that and says why not.
    public var serialNumberWasRead: Bool { serialNumber.isReported }

    /// Derives a stable identity from this observation, or throws the specific
    /// reason it cannot.
    ///
    /// There is no path here that turns an absent serial number into an
    /// identity. Vendor and product identifiers name a model, and a registry
    /// entry ID lasts only as long as this session, so neither can stand in.
    func qualifiedIdentity(digest: any StableIdentityDigest) throws -> QualifiedUSBDeviceIdentity {
        try USBIdentityQualification.qualify(
            vendorID: vendorID, productID: productID,
            serialNumber: serialNumber, digest: digest)
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

    /// The largest serial-number string this code will materialise a reading
    /// from. A USB string descriptor carries at most 126 UTF-16 code units, so
    /// anything beyond this cap is not a truncated serial number but a
    /// registry property that is not what this code is looking for. Lengths
    /// between the descriptor limit and this cap are passed through so that
    /// qualification can report `serialNumberTooLong` specifically.
    static let maximumSerialNumberCharacters = 4096

    /// Classifies a serial-number registry property without touching IOKit, so
    /// the classification is unit-testable on its own.
    ///
    /// Absent and unreadable stay distinct: no property at all is a different
    /// fact from a property of the wrong type, and neither is an empty serial.
    static func serialNumberReading(_ property: CFTypeRef?) -> USBSerialNumberReading {
        guard let property else { return .absent }
        guard CFGetTypeID(property) == CFStringGetTypeID(),
              let text = property as? NSString else { return .unreadable }
        let value = text as String
        guard value.count <= maximumSerialNumberCharacters else { return .unreadable }
        return .reported(value)
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
                     interfaceNumber: interfaceNumber,
                     serialNumber: USBRegistryDiscovery.serialNumberReading(
                        IORegistryEntryCreateCFProperty(
                            parent, Self.serialNumberPropertyKey as CFString,
                            kCFAllocatorDefault, 0)?.takeRetainedValue()))
    }

    /// `IOKit/usb/USBSpec.h` defines `kUSBSerialNumberString` as the literal
    /// `"USB Serial Number"`. It is spelled out here rather than referenced
    /// through the C constant because this file cannot be compiled on the
    /// authoring host, and the constant's Swift exposure is not guaranteed to
    /// be identical across SDK versions; the literal is fixed by the header.
    ///
    /// Reading it is a registry property read, exactly like the vendor and
    /// product identifiers already read from this same entry. The kernel
    /// populated the property during enumeration. Nothing here opens the
    /// device, claims an interface, or issues a control transfer.
    private static let serialNumberPropertyKey = "USB Serial Number"

    private func number(_ entry: io_object_t, _ key: String, maximum: UInt64) -> UInt64? {
        USBRegistryDiscovery.unsignedNumber(
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
            maximum: maximum)
    }
}
