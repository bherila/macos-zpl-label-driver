import Foundation
import XCTest
@testable import LabelCore

final class PrinterProfileJSONTests: XCTestCase {
    private func completeProfile() throws -> PrinterProfile {
        let documented = CapabilityEvidence.documentedModel(sourceID: "R26")
        return try PrinterProfile(
            schemaVersion: 1,
            revision: 9,
            capabilities: PrinterCapabilities(
                model: "Test ZPL model",
                thermalTransfer: CapabilityFact(state: .supported, evidence: documented),
                cutter: CapabilityFact(state: .unsupported, evidence: documented),
                peeler: CapabilityFact(state: .unknown, evidence: .unobserved),
                rewind: CapabilityFact(state: .unknown, evidence: .unobserved),
                tracking: [
                    .gap: CapabilityFact(state: .supported, evidence: documented),
                    .blackMark: CapabilityFact(state: .supported, evidence: documented),
                ],
                printSpeedChoicesIps: [6, 2, 4],
                darkness: CapabilityFact(state: .supported, evidence: documented)
            ),
            installedHardware: InstalledHardware(
                transport: .rawTCP,
                selectedFinishing: .tearOff,
                cutter: CapabilityFact(state: .unsupported, evidence: .reportedInstallation),
                peeler: CapabilityFact(state: .unsupported, evidence: .reportedInstallation),
                observedSpeedIps: 4,
                observedDarkness: 12,
                observedTracking: .gap
            ),
            media: MediaConfiguration(
                form: .observed(.preCut, evidence: .reportedInstallation),
                nominalLabelFace: .observed(
                    PhysicalSize(
                        width: try Millimeters.inches(4),
                        height: try Millimeters.inches(6)
                    ),
                    evidence: .reportedInstallation
                ),
                configuredTracking: .observed(.gap, evidence: .reportedInstallation),
                calibration: .observed(
                    try MediaCalibration(
                        widthDots: 812, lengthDots: 1_218,
                        originXDot: -2, originYDot: 3
                    ),
                    evidence: .reportedInstallation
                )
            ),
            connection: ConnectionConfiguration(
                transport: .rawTCP,
                stableIdentity: .observed(
                    try StableConnectionIdentity(opaqueValue: "local-device-token"),
                    evidence: .reportedInstallation
                )
            )
        )
    }

    func testReferenceAndFullyObservedProfilesRoundTripDeterministically() throws {
        for profile in [try PrinterProfile.gc420dUSBReference(revision: 7), try completeProfile()] {
            let first = try PrinterProfileJSON.encode(profile)
            XCTAssertEqual(try PrinterProfileJSON.encode(profile), first)
            XCTAssertEqual(try PrinterProfileJSON.decode(first), profile)
            XCTAssertEqual(try PrinterProfileJSON.encode(PrinterProfileJSON.decode(first)), first)
        }
    }

    func testTrackingKeysAndSpeedsHaveCanonicalRepresentation() throws {
        let data = try PrinterProfileJSON.encode(completeProfile())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let capabilities = try XCTUnwrap(root["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["printSpeedChoicesIps"] as? [Int], [2, 4, 6])
        let tracking = try XCTUnwrap(capabilities["tracking"] as? [String: Any])
        XCTAssertEqual(Set(tracking.keys), ["gap", "blackMark", "continuous"])
        XCTAssertTrue(tracking["continuous"] is NSNull)
    }

    func testUnknownFieldsDuplicateSpeedsAndMalformedObservationsFailClosed() throws {
        let original = try PrinterProfileJSON.encode(completeProfile())
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: original) as? [String: Any])
        root["filterPath"] = "/tmp/filter"
        XCTAssertThrowsError(try PrinterProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) { XCTAssertEqual($0 as? PrinterProfileJSONError, .unknownField) }
        root.removeValue(forKey: "filterPath")

        var capabilities = try XCTUnwrap(root["capabilities"] as? [String: Any])
        capabilities["printSpeedChoicesIps"] = [2, 2]
        root["capabilities"] = capabilities
        XCTAssertThrowsError(try PrinterProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) { XCTAssertEqual($0 as? PrinterProfileJSONError, .invalidValue("printSpeedChoicesIps")) }

        root = try XCTUnwrap(try JSONSerialization.jsonObject(with: original) as? [String: Any])
        var connection = try XCTUnwrap(root["connection"] as? [String: Any])
        var identity = try XCTUnwrap(connection["stableIdentity"] as? [String: Any])
        identity["state"] = "unobserved"
        connection["stableIdentity"] = identity
        root["connection"] = connection
        XCTAssertThrowsError(try PrinterProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) { XCTAssertEqual($0 as? PrinterProfileJSONError, .invalidValue("observation")) }
    }

    func testWireInputAndOutputAreBoundedBeforeUse() throws {
        XCTAssertThrowsError(try PrinterProfileJSON.decode(
            Data(repeating: 0x20, count: PrinterProfileJSON.maximumBytes + 1)
        )) { XCTAssertEqual($0 as? PrinterProfileJSONError, .inputTooLarge) }
        XCTAssertThrowsError(try PrinterProfileJSON.encode(completeProfile(), maximumBytes: 1)) {
            XCTAssertEqual($0 as? PrinterProfileJSONError, .outputTooLarge)
        }
        XCTAssertThrowsError(try PrinterProfileJSON.decode(Data("{}".utf8), maximumBytes: 0)) {
            XCTAssertEqual($0 as? PrinterProfileJSONError, .invalidLimit)
        }
    }

    func testInvalidInternalEvidenceCannotProduceNonRoundTrippableBytes() throws {
        let base = try completeProfile()
        let invalid = try PrinterProfile(
            schemaVersion: base.schemaVersion,
            revision: base.revision,
            capabilities: base.capabilities,
            installedHardware: base.installedHardware,
            media: MediaConfiguration(
                form: .observed(.preCut, evidence: .unobserved),
                nominalLabelFace: base.media.nominalLabelFace,
                configuredTracking: base.media.configuredTracking,
                calibration: base.media.calibration
            ),
            connection: base.connection
        )
        XCTAssertThrowsError(try PrinterProfileJSON.encode(invalid)) {
            XCTAssertEqual($0 as? PrinterProfileJSONError, .invalidValue("observationEvidence"))
        }
    }
}
