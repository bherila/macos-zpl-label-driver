import CoreFoundation
import Foundation
import IOKit
import XCTest
import LabelCore
@testable import LabelMac

final class USBRegistryDiscoveryTests: XCTestCase {
    func testRegistryObservationDumpHidesStoredIdentityAndPreservesExplicitFields() {
        let value = USBPrinterObservation(registryEntryID: 123456789,
            vendorID: 1234, productID: 5678, interfaceNumber: 42)
        var output = ""
        dump([value], to: &output)
        for secret in ["123456789", "1234", "5678", "42", value.id.uuidString] {
            XCTAssertFalse(output.contains(secret))
        }
        XCTAssertTrue(Mirror(reflecting: value).children.isEmpty)
        XCTAssertEqual(value.vendorID, 1234)
        XCTAssertEqual(value.productID, 5678)
        XCTAssertEqual(value.interfaceNumber, 42)
        XCTAssertEqual(value, value)
    }

    private final class Registry: USBInterfaceRegistryAccess {
        var iterator: io_iterator_t = 100
        var entries: [io_object_t] = []
        var classes: [io_object_t: UInt8] = [:]
        var released: [io_object_t] = []
        var observationsRequested: [io_object_t] = []
        var nextCalls = 0, validCalls = 0
        var valid = true, metadataFails = false, matchingFails = false
        func matchingInterfaces() throws -> io_iterator_t {
            if matchingFails { throw USBRegistryDiscovery.Error.unavailable }
            return iterator
        }
        func next(_ iterator: io_iterator_t) -> io_object_t {
            nextCalls += 1
            return entries.isEmpty ? 0 : entries.removeFirst()
        }
        func isValid(_ iterator: io_iterator_t) -> Bool { validCalls += 1; return valid }
        func release(_ object: io_object_t) { released.append(object) }
        func interfaceClass(_ interface: io_object_t) -> UInt8? { classes[interface] }
        func printerObservation(_ interface: io_object_t) throws -> USBPrinterObservation {
            observationsRequested.append(interface)
            if metadataFails { throw USBRegistryDiscovery.Error.unreadablePrinterMetadata }
            return .init(registryEntryID: 123, vendorID: 42, productID: 17, interfaceNumber: 0)
        }
    }

    func testSuccessfulNullIteratorIsEmptyWithoutIteratorCalls() throws {
        let access = Registry(); access.iterator = 0
        let result = try USBRegistryDiscovery.snapshot(access: access, maximumInterfaces: 4096)
        XCTAssertEqual(result.scannedInterfaces, 0)
        XCTAssertEqual(result.printers, [])
        XCTAssertEqual(access.nextCalls, 0)
        XCTAssertEqual(access.validCalls, 0)
        XCTAssertEqual(access.released, [])
    }

    func testOnlyPrinterClassGetsMetadataAndMissingClassRemainsUnknown() throws {
        let access = Registry(); access.entries = [1, 2, 3]; access.classes = [1: 7, 2: 8]
        let result = try USBRegistryDiscovery.snapshot(access: access, maximumInterfaces: 3)
        XCTAssertEqual(result.scannedInterfaces, 3)
        XCTAssertEqual(result.unreadableInterfaceClasses, 1)
        XCTAssertEqual(result.printers.count, 1)
        XCTAssertEqual(access.observationsRequested, [1])
        XCTAssertEqual(access.released, [1, 2, 3, 100])
        let observation = try XCTUnwrap(result.printers.first)
        XCTAssertEqual(observation.vendorID, 42)
        XCTAssertEqual(String(describing: observation), "USBPrinterObservation(redacted)")
        XCTAssertEqual(String(reflecting: observation), "USBPrinterObservation(redacted)")
    }

    func testLimitAndChangedScanRejectPartialResultsAndReleaseHandles() throws {
        let limited = Registry(); limited.entries = [1, 2]; limited.classes = [1: 7, 2: 7]
        XCTAssertThrowsError(try USBRegistryDiscovery.snapshot(access: limited, maximumInterfaces: 1)) {
            XCTAssertEqual($0 as? USBRegistryDiscovery.Error, .interfaceLimit)
        }
        XCTAssertEqual(limited.observationsRequested, [1])
        XCTAssertEqual(limited.released, [1, 2, 100])
        let changed = Registry(); changed.entries = [1]; changed.classes = [1: 7]; changed.valid = false
        XCTAssertThrowsError(try USBRegistryDiscovery.snapshot(access: changed, maximumInterfaces: 1)) {
            XCTAssertEqual($0 as? USBRegistryDiscovery.Error, .changed)
        }
        XCTAssertEqual(changed.released, [1, 100])
    }

    func testUnreadablePrinterAndUnavailableRegistryFailClosed() throws {
        let access = Registry(); access.entries = [1]; access.classes = [1: 7]; access.metadataFails = true
        XCTAssertThrowsError(try USBRegistryDiscovery.snapshot(access: access, maximumInterfaces: 1)) {
            XCTAssertEqual($0 as? USBRegistryDiscovery.Error, .unreadablePrinterMetadata)
        }
        XCTAssertEqual(access.released, [1, 100])
        access.matchingFails = true
        access.released = []
        XCTAssertThrowsError(try USBRegistryDiscovery.snapshot(access: access, maximumInterfaces: 1)) {
            XCTAssertEqual($0 as? USBRegistryDiscovery.Error, .unavailable)
        }
        XCTAssertEqual(access.released, [])
    }

    func testNumericPropertiesRejectBooleanFractionNegativeAndOutOfRange() {
        XCTAssertEqual(USBRegistryDiscovery.unsignedNumber(NSNumber(value: 65535), maximum: 65535), 65535)
        for property: CFTypeRef? in [nil, kCFBooleanTrue, "42" as CFString,
                                    NSNumber(value: -1), NSNumber(value: 1.5), NSNumber(value: 65536)] {
            XCTAssertNil(USBRegistryDiscovery.unsignedNumber(property, maximum: 65535))
        }
    }
}

@MainActor
final class USBRegistryDiscoveryModelTests: XCTestCase {
    func testObservationSelectionCannotQualifyReferenceOrAuthorizeInstallation() async throws {
        let observation = USBPrinterObservation(registryEntryID: 123, vendorID: 42, productID: 17, interfaceNumber: 0)
        let result = USBRegistryDiscoverySnapshot(scannedInterfaces: 1, unreadableInterfaceClasses: 0, printers: [observation])
        let discovery = USBRegistryDiscoveryModel(discover: { result })
        let setup = try ReferencePrinterSetupModel.gc420dUSB()
        let original = setup.profile
        setup.stockLoadedConfirmed = true; setup.tearOffConfirmed = true
        await discovery.refresh()
        discovery.selectedObservationID = observation.id
        XCTAssertEqual(setup.profile, original)
        XCTAssertFalse(setup.canInstallQueue)
        XCTAssertEqual(discovery.snapshot, result)
        await discovery.refresh()
        XCTAssertNil(discovery.selectedObservationID)
        XCTAssertFalse(discovery.isDiscovering)
        _ = USBRegistryDiscoveryView(model: discovery)
    }

    func testErrorKindsHaveDistinctPrivateSafeMessagesAndNoSnapshot() async {
        for error in [USBRegistryDiscovery.Error.unavailable, .changed, .interfaceLimit, .unreadablePrinterMetadata] {
            let model = USBRegistryDiscoveryModel(discover: { throw error })
            await model.refresh()
            XCTAssertNil(model.snapshot)
            XCTAssertNil(model.selectedObservationID)
            XCTAssertFalse(model.isDiscovering)
            XCTAssertNotNil(model.status)
        }
        let incomplete = USBRegistryDiscoveryModel(discover: {
            .init(scannedInterfaces: 1, unreadableInterfaceClasses: 1, printers: [])
        })
        await incomplete.refresh()
        XCTAssertTrue(incomplete.status?.contains("cannot establish printer absence") == true)
    }

    private actor Sequence {
        var first: CheckedContinuation<USBRegistryDiscoverySnapshot, any Error>?
        var calls = 0
        let started: XCTestExpectation
        init(started: XCTestExpectation) { self.started = started }
        func next() async throws -> USBRegistryDiscoverySnapshot {
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation {
                    first = $0
                    started.fulfill()
                }
            }
            return .init(scannedInterfaces: 2, unreadableInterfaceClasses: 0, printers: [])
        }
        func finishFirst() {
            first?.resume(returning: .init(scannedInterfaces: 1, unreadableInterfaceClasses: 0, printers: []))
            first = nil
        }
    }

    func testOlderCompletionCannotReplaceNewScanAndCancellationDoesNotInstallResult() async {
        let started = expectation(description: "first scan admitted")
        let sequence = Sequence(started: started)
        let model = USBRegistryDiscoveryModel(discover: { try await sequence.next() })
        let old = Task { await model.refresh() }
        await fulfillment(of: [started], timeout: 2)
        await model.refresh()
        await sequence.finishFirst()
        await old.value
        XCTAssertEqual(model.snapshot?.scannedInterfaces, 2)
        XCTAssertFalse(model.isDiscovering)
        let cancelled = Task { await model.refresh() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.status, "USB discovery cancelled.")
    }
}
