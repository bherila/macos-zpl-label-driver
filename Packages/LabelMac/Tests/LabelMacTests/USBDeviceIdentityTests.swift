import CoreFoundation
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

/// Identity qualification as the setup flow sees it.
///
/// Every observation below is synthetic. No USB device is opened, claimed or
/// written to, nothing is installed, and no printer is contacted. The serial
/// numbers are invented strings, not values read from any real unit.
@MainActor
final class USBDeviceIdentityTests: XCTestCase {
    private let gc420dVendorID: UInt16 = 0x0A5F
    private let gc420dProductID: UInt16 = 0x00D1

    private func observation(serial: USBSerialNumberReading,
                             productID: UInt16? = nil) -> USBPrinterObservation {
        USBPrinterObservation(registryEntryID: 4_294_967_296,
                              vendorID: gc420dVendorID,
                              productID: productID ?? gc420dProductID,
                              interfaceNumber: 0, serialNumber: serial)
    }

    private func readyModel() throws -> ReferencePrinterSetupModel {
        let model = try ReferencePrinterSetupModel.gc420dUSB()
        model.stockLoadedConfirmed = true
        model.tearOffConfirmed = true
        return model
    }

    func testCryptoKitDigestMatchesThePublishedSHA256Vector() {
        // FIPS 180-4 / NIST CAVP one-block message "abc".
        XCTAssertEqual(CryptoKitStableIdentityDigest().hexDigest(Array("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(CryptoKitStableIdentityDigest().hexDigest([]).count, 64)
    }

    func testAUnitReportingASerialNumberQualifiesAndUnblocksTheInstallationGate() throws {
        let model = try readyModel()
        XCTAssertFalse(model.canInstallQueue)
        XCTAssertEqual(model.identityQualification, .notAttempted)
        let before = model.profile

        XCTAssertEqual(model.qualifyIdentity(from: observation(serial: .reported("36J153900185"))),
                       .qualified)
        guard case .observed(_, let evidence) = model.profile.connection.stableIdentity else {
            return XCTFail("qualification did not produce an observed identity")
        }
        XCTAssertEqual(evidence, .reportedInstallation)
        XCTAssertEqual(model.profile.revision, before.revision + 1)
        XCTAssertEqual(model.facts.first { $0.id == "identity" }?.status, .configured)
        XCTAssertEqual(model.facts.first { $0.id == "transport" }?.status, .configured)

        // Qualification withdrew the confirmations, which were made about
        // whatever printer was there before this unit was identified.
        XCTAssertFalse(model.stockLoadedConfirmed)
        XCTAssertFalse(model.tearOffConfirmed)
        XCTAssertFalse(model.canInstallQueue)
        model.stockLoadedConfirmed = true
        XCTAssertFalse(model.canInstallQueue)
        model.tearOffConfirmed = true
        XCTAssertTrue(model.canInstallQueue)
        XCTAssertEqual(model.installationReadinessMessage, "Ready for queue installation")
    }

    func testAUnitWithoutASerialNumberNeverQualifiesAndSaysWhy() throws {
        let unqualifiable: [(USBSerialNumberReading, USBIdentityQualification.Failure)] = [
            (.absent, .serialNumberAbsent),
            (.unreadable, .serialNumberUnreadable),
            (.reported(""), .serialNumberEmpty),
            (.reported("00000000"), .serialNumberNotUnitDistinct),
            (.reported("36J15390\u{0007}185"), .serialNumberUnprintable),
        ]
        for (reading, expected) in unqualifiable {
            let model = try readyModel()
            let before = model.profile
            XCTAssertEqual(model.qualifyIdentity(from: observation(serial: reading)),
                           .refused(expected))
            // Nothing became observed, nothing became a new revision, and the
            // gate did not move.
            XCTAssertEqual(model.profile, before)
            XCTAssertEqual(model.profile.connection.stableIdentity, .unobserved)
            XCTAssertFalse(model.canInstallQueue)
            XCTAssertTrue(model.stockLoadedConfirmed)
            XCTAssertTrue(model.tearOffConfirmed)

            // The reason reaches the person as a sentence, not a case name.
            let message = model.installationReadinessMessage
            XCTAssertEqual(message, expected.setupMessage)
            XCTAssertEqual(model.facts.first { $0.id == "identity" }?.value, message)
            XCTAssertEqual(model.facts.first { $0.id == "identity" }?.status, .unknown)
            XCTAssertFalse(message.contains("serialNumber"), message)
            XCTAssertFalse(message.contains("USBIdentityQualification"), message)
            XCTAssertTrue(message.hasSuffix("."), message)
        }
    }

    func testEveryRefusalReasonHasItsOwnSentence() {
        let failures: [USBIdentityQualification.Failure] = [
            .serialNumberAbsent, .serialNumberUnreadable, .serialNumberEmpty,
            .serialNumberUnprintable, .serialNumberTooLong, .serialNumberNotUnitDistinct,
        ]
        XCTAssertEqual(Set(failures.map(\.setupMessage)).count, failures.count)
        for failure in failures + [.digestMalformed, .identityRejected] {
            XCTAssertFalse(failure.setupMessage.isEmpty)
            XCTAssertTrue(failure.setupMessage.contains("installation"), failure.setupMessage)
        }
    }

    func testTwoIdenticalModelsWithDifferentSerialsAreNotTheSameDevice() throws {
        let first = try readyModel()
        let second = try readyModel()
        XCTAssertEqual(first.qualifyIdentity(from: observation(serial: .reported("36J153900185"))),
                       .qualified)
        XCTAssertEqual(second.qualifyIdentity(from: observation(serial: .reported("36J153900186"))),
                       .qualified)
        // Same vendor, same product, same interface: only the serial differs.
        XCTAssertNotEqual(first.profile.connection.stableIdentity,
                          second.profile.connection.stableIdentity)
    }

    func testTheSameUnitQualifiesToTheSameIdentityOnASecondPass() throws {
        let model = try readyModel()
        XCTAssertEqual(model.qualifyIdentity(from: observation(serial: .reported("36J153900185"))),
                       .qualified)
        let afterFirst = model.profile
        model.stockLoadedConfirmed = true
        model.tearOffConfirmed = true

        // A second scan of the same printer produces a fresh observation with a
        // fresh session identifier; the identity it qualifies to is the same.
        XCTAssertEqual(model.qualifyIdentity(from: observation(serial: .reported("36J153900185"))),
                       .qualified)
        XCTAssertEqual(model.profile, afterFirst)
        XCTAssertEqual(model.profile.revision, afterFirst.revision)
        // Re-qualifying the unit already adopted is not a change of device, so
        // it does not withdraw what was confirmed about that device.
        XCTAssertTrue(model.stockLoadedConfirmed)
        XCTAssertTrue(model.tearOffConfirmed)
        XCTAssertTrue(model.canInstallQueue)

        // A different unit is a different device: confirmations are withdrawn.
        XCTAssertEqual(model.qualifyIdentity(from: observation(serial: .reported("36J153900999"))),
                       .qualified)
        XCTAssertNotEqual(model.profile.connection.stableIdentity,
                          afterFirst.connection.stableIdentity)
        XCTAssertFalse(model.stockLoadedConfirmed)
        XCTAssertFalse(model.tearOffConfirmed)
        XCTAssertFalse(model.canInstallQueue)
    }

    func testNothingOnTheQualifiedPathCarriesTheSerialNumber() throws {
        let serial = "36J153900185"
        let model = try readyModel()
        XCTAssertEqual(model.qualifyIdentity(from: observation(serial: .reported(serial))),
                       .qualified)
        model.stockLoadedConfirmed = true
        model.tearOffConfirmed = true

        let encoded = String(decoding: try PrinterProfileJSON.encode(model.profile), as: UTF8.self)
        XCTAssertFalse(encoded.contains(serial))
        let surfaces = model.facts.map(\.value) + model.facts.map(\.label)
            + [model.installationReadinessMessage]
        for surface in surfaces {
            XCTAssertFalse(surface.contains(serial), surface)
            XCTAssertFalse(surface.contains("StableConnectionIdentity"), surface)
        }
        // The connection is not itself a redacted value -- it names the
        // identity type -- but the identity inside it still reveals nothing.
        var dumped = ""
        dump(model.profile.connection, to: &dumped)
        XCTAssertFalse(dumped.contains(serial))
        XCTAssertFalse(String(describing: model.profile.connection).contains(serial))
    }

    func testAnObservationStaysRedactedAndWillNotHandBackItsSerial() {
        let serial = "36J153900185"
        let value = observation(serial: .reported(serial))
        var dumped = ""
        dump([value], to: &dumped)
        for secret in [serial, "4294967296", value.id.uuidString] {
            XCTAssertFalse(dumped.contains(secret), secret)
        }
        XCTAssertEqual(String(describing: value), "USBPrinterObservation(redacted)")
        XCTAssertEqual(String(reflecting: value), "USBPrinterObservation(redacted)")
        XCTAssertTrue(Mirror(reflecting: value).children.isEmpty)
        // Whether a string was read is a fact about the scan, and is not secret.
        XCTAssertTrue(value.serialNumberWasRead)
        XCTAssertFalse(observation(serial: .absent).serialNumberWasRead)
        XCTAssertFalse(observation(serial: .unreadable).serialNumberWasRead)
        // An observation that reads a placeholder still read a string; only
        // qualification decides it is unusable.
        XCTAssertTrue(observation(serial: .reported("0")).serialNumberWasRead)
        // The label the picker shows is unchanged by any of this.
        XCTAssertEqual(value.interfaceLabel, "USB VID 0x0A5F, PID 0x00D1, interface 0")
    }

    func testAnObservationDefaultsToNoSerialSoItFailsClosed() throws {
        let bare = USBPrinterObservation(registryEntryID: 1, vendorID: gc420dVendorID,
                                         productID: gc420dProductID, interfaceNumber: 0)
        XCTAssertFalse(bare.serialNumberWasRead)
        let model = try readyModel()
        XCTAssertEqual(model.qualifyIdentity(from: bare), .refused(.serialNumberAbsent))
        XCTAssertFalse(model.canInstallQueue)
    }

    func testSerialNumberPropertiesAreClassifiedWithoutCollapsingAbsentIntoEmpty() {
        XCTAssertEqual(USBRegistryDiscovery.serialNumberReading(nil), .absent)
        for property: CFTypeRef? in [kCFBooleanTrue, NSNumber(value: 42), NSNumber(value: 1.5)] {
            XCTAssertEqual(USBRegistryDiscovery.serialNumberReading(property), .unreadable)
        }
        XCTAssertEqual(USBRegistryDiscovery.serialNumberReading("36J153900185" as CFString),
                       .reported("36J153900185"))
        XCTAssertEqual(USBRegistryDiscovery.serialNumberReading("" as CFString), .reported(""))
        let capped = String(repeating: "A",
                            count: USBRegistryDiscovery.maximumSerialNumberCharacters)
        XCTAssertEqual(USBRegistryDiscovery.serialNumberReading(capped as CFString),
                       .reported(capped))
        XCTAssertEqual(USBRegistryDiscovery.serialNumberReading((capped + "A") as CFString),
                       .unreadable)
    }

    func testWithdrawingAnIdentityReturnsTheGateToBlocked() throws {
        let model = try readyModel()
        XCTAssertEqual(model.qualifyIdentity(from: observation(serial: .reported("36J153900185"))),
                       .qualified)
        model.stockLoadedConfirmed = true
        model.tearOffConfirmed = true
        XCTAssertTrue(model.canInstallQueue)
        let adopted = model.profile

        try model.withdrawQualifiedIdentity()
        XCTAssertEqual(model.profile.connection.stableIdentity, .unobserved)
        XCTAssertEqual(model.profile.revision, adopted.revision + 1)
        XCTAssertEqual(model.identityQualification, .notAttempted)
        XCTAssertFalse(model.stockLoadedConfirmed)
        XCTAssertFalse(model.tearOffConfirmed)
        XCTAssertFalse(model.canInstallQueue)
        XCTAssertEqual(model.facts.first { $0.id == "transport" }?.status, .unknown)
        // Withdrawing again is a no-op, not a revision.
        try model.withdrawQualifiedIdentity()
        XCTAssertEqual(model.profile.revision, adopted.revision + 1)
    }

    func testQualificationInstallsNothingAndLeavesEveryOtherGateWhereItWas() throws {
        let model = try ReferencePrinterSetupModel.gc420dUSB()
        let before = model.profile
        XCTAssertEqual(model.qualifyIdentity(from: observation(serial: .reported("36J153900185"))),
                       .qualified)
        // Identity is the only thing that changed.
        XCTAssertEqual(model.profile.capabilities, before.capabilities)
        XCTAssertEqual(model.profile.installedHardware, before.installedHardware)
        XCTAssertEqual(model.profile.media, before.media)
        XCTAssertEqual(model.profile.configuredDefaults, before.configuredDefaults)
        XCTAssertEqual(model.profile.thermalMedia, before.thermalMedia)
        // The confirmations were never asserted, and qualification did not
        // assert them. Installation stays blocked on them.
        XCTAssertFalse(model.stockLoadedConfirmed)
        XCTAssertFalse(model.tearOffConfirmed)
        XCTAssertFalse(model.canInstallQueue)
        XCTAssertEqual(model.installationReadinessMessage,
                       "Confirm the actual stock and tear-off configuration before queue installation")
        // Unqualified capabilities stay unqualified: identifying a unit tells
        // this Mac which printer it is looking at, not what that printer can do.
        XCTAssertEqual(model.facts.first { $0.id == "cutter" }?.status, .unavailable)
        XCTAssertEqual(model.facts.first { $0.id == "peeler" }?.status, .unknown)
        XCTAssertEqual(model.facts.first { $0.id == "darkness" }?.status, .unknown)
    }

    func testPickerSelectionStaysInertAndQualificationIsASeparateAction() async throws {
        let printer = observation(serial: .reported("36J153900185"))
        let snapshot = USBRegistryDiscoverySnapshot(
            scannedInterfaces: 1, unreadableInterfaceClasses: 0, printers: [printer])
        let discovery = USBRegistryDiscoveryModel(discover: { snapshot })
        let setup = try readyModel()
        let before = setup.profile
        await discovery.refresh()
        discovery.selectedObservationID = printer.id
        // Naming a row is still not acting on it.
        XCTAssertEqual(setup.profile, before)
        XCTAssertEqual(setup.identityQualification, .notAttempted)
        XCTAssertFalse(setup.canInstallQueue)

        let selected = try XCTUnwrap(discovery.selectedObservation)
        XCTAssertEqual(selected, printer)
        XCTAssertEqual(setup.qualifyIdentity(from: selected), .qualified)
        XCTAssertNotEqual(setup.profile, before)
        _ = USBRegistryDiscoveryView(model: discovery, setup: setup)
        _ = USBRegistryDiscoveryView(model: discovery)

        discovery.selectedObservationID = UUID()
        XCTAssertNil(discovery.selectedObservation)
    }
}
