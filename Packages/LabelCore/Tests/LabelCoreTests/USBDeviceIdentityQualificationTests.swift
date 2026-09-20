import XCTest
@testable import LabelCore

/// An injective stand-in for SHA-256.
///
/// The policy under test is "what qualifies, and what an identity may reveal",
/// and that policy has to hold for any injective digest. Using a synthetic one
/// here keeps these tests running on a host without CryptoKit and keeps them
/// from asserting a particular vendor's hash output. The real CryptoKit
/// conformance is exercised by the LabelMac tests, which need a Mac.
private struct SyntheticDigest: StableIdentityDigest {
    func hexDigest(_ bytes: [UInt8]) -> String {
        // FNV-1a over the preimage, widened to 64 hex characters by repetition
        // of four independently seeded passes. Injectivity is not claimed for
        // arbitrary inputs; distinctness is asserted only for the specific
        // fixtures below, where it is checked rather than assumed.
        var out = ""
        for seed in [UInt64(0xcbf2_9ce4_8422_2325), 0x0000_0000_0100_0193,
                     0x1234_5678_9abc_def0, 0x0fed_cba9_8765_4321] {
            var hash = seed
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            let digits = String(hash, radix: 16)
            out += String(repeating: "0", count: 16 - digits.count) + digits
        }
        return out
    }
}

private struct FixedDigest: StableIdentityDigest {
    let value: String
    func hexDigest(_ bytes: [UInt8]) -> String { value }
}

final class USBDeviceIdentityQualificationTests: XCTestCase {
    private let digest = SyntheticDigest()

    private func qualify(vendorID: UInt16 = 0x0A5F, productID: UInt16 = 0x00D1,
                         serial: USBSerialNumberReading) throws -> QualifiedUSBDeviceIdentity {
        try USBIdentityQualification.qualify(
            vendorID: vendorID, productID: productID, serialNumber: serial, digest: digest)
    }

    func testUnitWithSerialNumberQualifiesAndCarriesModelIdentifiers() throws {
        let qualified = try qualify(serial: .reported("36J153900185"))
        XCTAssertEqual(qualified.vendorID, 0x0A5F)
        XCTAssertEqual(qualified.productID, 0x00D1)
        let opaque = qualified.identity.privateProfileValue
        XCTAssertTrue(opaque.hasPrefix(USBIdentityQualification.opaqueValuePrefix))
        XCTAssertEqual(opaque.count, USBIdentityQualification.opaqueValuePrefix.count + 64)
    }

    func testUnitWithoutSerialNumberDoesNotQualifyAndReportsWhichWayItFailed() {
        // Absent, unreadable and empty are three different facts. Collapsing
        // them into one "no" is how an unknown becomes a false.
        let cases: [(USBSerialNumberReading, USBIdentityQualification.Failure)] = [
            (.absent, .serialNumberAbsent),
            (.unreadable, .serialNumberUnreadable),
            (.reported(""), .serialNumberEmpty),
            (.reported("   \t "), .serialNumberEmpty),
            (.reported("36J15\u{0000}900185"), .serialNumberUnprintable),
            (.reported("36J1539\u{00E9}0185"), .serialNumberUnprintable),
            (.reported(String(repeating: "A", count: 127)), .serialNumberTooLong),
            (.reported("0"), .serialNumberNotUnitDistinct),
            (.reported("00000000"), .serialNumberNotUnitDistinct),
            (.reported("FFFFFFFFFFFF"), .serialNumberNotUnitDistinct),
        ]
        for (reading, expected) in cases {
            XCTAssertThrowsError(try qualify(serial: reading), "\(expected)") {
                XCTAssertEqual($0 as? USBIdentityQualification.Failure, expected)
            }
        }
    }

    func testTwoUnitsOfOneModelProduceDifferentIdentities() throws {
        // The entire point: identical VID/PID, different units.
        let first = try qualify(serial: .reported("36J153900185"))
        let second = try qualify(serial: .reported("36J153900186"))
        XCTAssertEqual(first.vendorID, second.vendorID)
        XCTAssertEqual(first.productID, second.productID)
        XCTAssertNotEqual(first.identity, second.identity)
    }

    func testDifferentModelsWithTheSameSerialProduceDifferentIdentities() throws {
        let first = try qualify(productID: 0x00D1, serial: .reported("SHARED-SERIAL"))
        let second = try qualify(productID: 0x00D2, serial: .reported("SHARED-SERIAL"))
        XCTAssertNotEqual(first.identity, second.identity)
        let otherVendor = try qualify(vendorID: 0x0A60, serial: .reported("SHARED-SERIAL"))
        XCTAssertNotEqual(first.identity, otherVendor.identity)
    }

    func testSameUnitProducesTheSameIdentityOnASecondDiscoveryPass() throws {
        let first = try qualify(serial: .reported("36J153900185"))
        let second = try qualify(serial: .reported("36J153900185"))
        XCTAssertEqual(first.identity, second.identity)
        XCTAssertEqual(first, second)
        // Descriptor padding is a property of the read, not of the printer, so
        // it must not fork the identity of one physical unit.
        let padded = try qualify(serial: .reported("  36J153900185\n"))
        XCTAssertEqual(padded.identity, first.identity)
    }

    func testIdentityNeverCarriesTheSerialNumberAndStaysRedacted() throws {
        let serial = "36J153900185"
        let qualified = try qualify(serial: .reported(serial))
        XCTAssertFalse(qualified.identity.privateProfileValue.contains(serial))
        var dumped = ""
        dump([qualified, qualified], to: &dumped)
        for secret in [serial, qualified.identity.privateProfileValue, "0A5F", "2655"] {
            XCTAssertFalse(dumped.contains(secret), secret)
        }
        XCTAssertEqual(String(describing: qualified), "QualifiedUSBDeviceIdentity(redacted)")
        XCTAssertEqual(String(reflecting: qualified), "QualifiedUSBDeviceIdentity(redacted)")
        XCTAssertTrue(Mirror(reflecting: qualified).children.isEmpty)
    }

    func testAReadingNeitherPrintsNorHandsBackTheSerialItHolds() {
        let reading = USBSerialNumberReading.reported("36J153900185")
        var dumped = ""
        dump(reading, to: &dumped)
        XCTAssertFalse(dumped.contains("36J153900185"))
        XCTAssertEqual(String(describing: reading), "USBSerialNumberReading(redacted)")
        XCTAssertTrue(reading.isReported)
        XCTAssertFalse(USBSerialNumberReading.absent.isReported)
        XCTAssertFalse(USBSerialNumberReading.unreadable.isReported)
        XCTAssertNotEqual(USBSerialNumberReading.absent, .unreadable)
    }

    func testCanonicalPreimageSeparatesItsFieldsUnambiguously() {
        let preimage = USBIdentityQualification.canonicalPreimage(
            vendorID: 0x0A5F, productID: 0x00D1, serialNumber: "36J153900185")
        XCTAssertEqual(String(decoding: preimage, as: UTF8.self),
                       "LABEL_USB_STABLE_IDENTITY_V1\nusb\n0A5F\n00D1\n36J153900185\n")
        // Without fixed-width fields and separators these two would collide.
        XCTAssertNotEqual(
            USBIdentityQualification.canonicalPreimage(
                vendorID: 0x0A5F, productID: 0x00D1, serialNumber: "2X"),
            USBIdentityQualification.canonicalPreimage(
                vendorID: 0x0A5F, productID: 0x00D1, serialNumber: "X"))
        XCTAssertEqual(USBIdentityQualification.hex4(0), "0000")
        XCTAssertEqual(USBIdentityQualification.hex4(.max), "FFFF")
    }

    func testAMalformedDigestFailsClosedRatherThanBecomingAnIdentity() {
        let bad = ["", "not-hexadecimal", String(repeating: "a", count: 63),
                   String(repeating: "a", count: 65),
                   String(repeating: "A", count: 64),
                   String(repeating: "g", count: 64)]
        for value in bad {
            XCTAssertThrowsError(try USBIdentityQualification.qualify(
                vendorID: 1, productID: 2, serialNumber: .reported("UNIT-1"),
                digest: FixedDigest(value: value)), value) {
                XCTAssertEqual($0 as? USBIdentityQualification.Failure, .digestMalformed)
            }
        }
        XCTAssertNoThrow(try USBIdentityQualification.qualify(
            vendorID: 1, productID: 2, serialNumber: .reported("UNIT-1"),
            digest: FixedDigest(value: String(repeating: "0", count: 64))))
    }

    func testAdoptingAnIdentityAdvancesTheRevisionAndChangesNothingElse() throws {
        let base = try PrinterProfile.gc420dUSBReference(revision: 3)
        XCTAssertEqual(base.connection.stableIdentity, .unobserved)
        let identity = try qualify(serial: .reported("36J153900185")).identity
        let adopted = try base.adoptingStableIdentity(identity)
        XCTAssertEqual(adopted.revision, 4)
        // Since #131 a registry-derived identity records that this host read
        // it, not that a person reported it. The distinction is the point: a
        // value read out of the I/O Registry and a value someone typed are
        // different strengths of evidence.
        XCTAssertEqual(adopted.connection.stableIdentity,
                       .observed(identity, evidence: .observedByHost(method: .ioRegistryProperty)))
        XCTAssertEqual(adopted.connection.transport, base.connection.transport)
        XCTAssertEqual(adopted.schemaVersion, base.schemaVersion)
        XCTAssertEqual(adopted.capabilities, base.capabilities)
        XCTAssertEqual(adopted.installedHardware, base.installedHardware)
        XCTAssertEqual(adopted.media, base.media)
        XCTAssertEqual(adopted.configuredDefaults, base.configuredDefaults)
        XCTAssertEqual(adopted.thermalMedia, base.thermalMedia)
        XCTAssertEqual(adopted.finishingConfiguration, base.finishingConfiguration)
        // Adoption returns a new value; the original revision is untouched.
        XCTAssertEqual(base.revision, 3)
        XCTAssertNotEqual(adopted, base)
    }

    func testAdoptionRefusesUnobservedEvidenceAndAnUnrepresentableRevision() throws {
        let identity = try qualify(serial: .reported("36J153900185")).identity
        let base = try PrinterProfile.gc420dUSBReference()
        XCTAssertThrowsError(try base.adoptingStableIdentity(identity, evidence: .unobserved)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidObservationEvidence)
        }
        let limit = try PrinterProfile.gc420dUSBReference(revision: 9_007_199_254_740_991)
        XCTAssertThrowsError(try limit.adoptingStableIdentity(identity)) {
            XCTAssertEqual($0 as? PrinterProfileError, .unrepresentableProfileRevision)
        }
    }

    func testAnAdoptedIdentitySurvivesTheProfileCodecWithoutRevealingItself() throws {
        let serial = "36J153900185"
        let identity = try qualify(serial: .reported(serial)).identity
        let adopted = try PrinterProfile.gc420dUSBReference().adoptingStableIdentity(identity)
        let encoded = try PrinterProfileJSON.encode(adopted)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(serial))
        XCTAssertEqual(try PrinterProfileJSON.decode(encoded), adopted)
    }
}
