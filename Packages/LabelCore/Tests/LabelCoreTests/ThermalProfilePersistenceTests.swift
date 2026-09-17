import CoreFoundation
import Foundation
import XCTest
@testable import LabelCore

final class ThermalProfilePersistenceTests: XCTestCase {
    private let supported = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-thermal-fixture"))

    private func profile(_ method: ThermalMethod? = .thermalTransfer,
                         media: ThermalMediaConfiguration? = nil, version: Int = 7) throws -> PrinterProfile {
        let base = try OffsetControlTestFixture.profile()
        let c = base.capabilities
        var defaults = base.configuredDefaults
        defaults.thermalMethod = method
        return try PrinterProfile(schemaVersion: version, revision: 8,
            capabilities: .init(model: "synthetic-thermal-model", thermalTransfer: supported,
                cutter: c.cutter, peeler: c.peeler, rewind: c.rewind, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: c.darkness,
                feedSpeeds: c.feedSpeeds, backfeedSpeeds: c.backfeedSpeeds,
                physicalGeometry: c.physicalGeometry, offsets: c.offsets, directThermal: supported),
            installedHardware: base.installedHardware, media: base.media, connection: base.connection,
            configuredDefaults: defaults,
            thermalMedia: media ?? .init(method: .observed(method ?? .directThermal, evidence: .reportedInstallation),
                ribbonPresent: .observed(method == .thermalTransfer, evidence: .reportedInstallation)))
    }

    func testExactCanonicalThermalProfilePreservesIndependentGeometryAndOffsetDefaults() throws {
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            let original = try profile(method)
            let bytes = try PrinterProfileJSON.encode(original)
            let restored = try PrinterProfileJSON.decode(bytes)
            XCTAssertEqual(restored, original)
            XCTAssertEqual(try PrinterProfileJSON.encode(restored), bytes)
            XCTAssertEqual(restored.configuredDefaults.offsets, .init(shiftLeftDots: 0, labelTopDots: 0))
            XCTAssertEqual(restored.capabilities.physicalGeometry, original.capabilities.physicalGeometry)
            XCTAssertNoThrow(try restored.validate(.init(thermalMethod: method)))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let consumables = try XCTUnwrap(root["thermalMedia"] as? [String: Any])
            let ribbon = try XCTUnwrap(consumables["ribbonPresent"] as? [String: Any])
            let number = try XCTUnwrap(ribbon["value"] as? NSNumber)
            XCTAssertEqual(CFGetTypeID(number), CFBooleanGetTypeID())
            XCTAssertEqual(number.boolValue, method == .thermalTransfer)
        }
    }

    func testUnknownConsumablesSurvivePersistenceAndCannotBecomeObservedAbsence() throws {
        let original = try profile(nil, media: .unobserved)
        let restored = try PrinterProfileJSON.decode(PrinterProfileJSON.encode(original))
        XCTAssertEqual(restored.thermalMedia, .unobserved)
        XCTAssertThrowsError(try restored.validate(.init(thermalMethod: .directThermal)))
        XCTAssertThrowsError(try restored.validate(.init(thermalMethod: .thermalTransfer)))
        XCTAssertNoThrow(try restored.validate(.init()))
    }

    func testConfiguredThermalDefaultsRequireMatchingInstallationObservations() throws {
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            XCTAssertThrowsError(try profile(method, media: .unobserved))
            XCTAssertThrowsError(try profile(method, media: .init(
                method: .observed(method, evidence: .reportedInstallation),
                ribbonPresent: .observed(method != .thermalTransfer, evidence: .reportedInstallation))))
            XCTAssertThrowsError(try profile(method, media: .init(
                method: .observed(method, evidence: .documentedModel(sourceID: "synthetic-thermal-fixture")),
                ribbonPresent: .observed(method == .thermalTransfer, evidence: .reportedInstallation))))
        }
        XCTAssertThrowsError(try profile(.directThermal, version: 6))
    }

    func testStrictSchemaRejectsNumericRibbonAndMissingUnknownOrDowngradedFields() throws {
        let bytes = try PrinterProfileJSON.encode(profile())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for bad in [0 as Any, 1 as Any, "true" as Any, NSNull()] {
            var changed = root
            var media = try XCTUnwrap(changed["thermalMedia"] as? [String: Any])
            var ribbon = try XCTUnwrap(media["ribbonPresent"] as? [String: Any])
            ribbon["value"] = bad; media["ribbonPresent"] = ribbon; changed["thermalMedia"] = media
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        var changed = root; changed.removeValue(forKey: "thermalMedia")
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root; changed["extra"] = false
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root; changed["schemaVersion"] = 6
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root; changed["schemaVersion"] = 8
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root
        var caps = try XCTUnwrap(changed["capabilities"] as? [String: Any]); caps.removeValue(forKey: "directThermal")
        changed["capabilities"] = caps
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
    }

    func testLegacyCanonicalProfilesRetainExactSchemaAndDoNotAcquireThermalFacts() throws {
        let profiles = [try PrinterProfile.gc420dUSBReference(), try OffsetControlTestFixture.profile()]
        for original in profiles {
            let bytes = try PrinterProfileJSON.encode(original)
            let restored = try PrinterProfileJSON.decode(bytes)
            XCTAssertEqual(restored, original)
            XCTAssertEqual(try PrinterProfileJSON.encode(restored), bytes)
            XCTAssertEqual(restored.thermalMedia, .unobserved)
            XCTAssertEqual(restored.capabilities.directThermal, .init(state: .unknown, evidence: .unobserved))
            XCTAssertThrowsError(try restored.validate(.init(thermalMethod: .thermalTransfer)))
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertNil(root["thermalMedia"])
        }
    }
    func testNewProfileReferenceDoesNotWidenLegacyQueueAdmission() throws {
        let profile = try profile(.directThermal)
        let reference = try ImmutableProfileReference(id: "synthetic-printer", schemaVersion: 7,
            revision: profile.revision, sha256: String(repeating: "0", count: 64))
        XCTAssertEqual(reference.schemaVersion, 7)
        XCTAssertThrowsError(try VirtualQueueDefinition(schemaVersion: 5, id: "synthetic-queue", revision: 1,
            displayName: "Synthetic queue", physicalDevice: .init(sha256: String(repeating: "1", count: 64)),
            workflowProfile: .init(id: "synthetic-workflow", revision: 1, sha256: String(repeating: "2", count: 64)),
            printerProfile: reference, workflowDefaults: .init(thermalMethod: .directThermal, finishing: .tearOff),
            validatingAgainst: profile)) {
                XCTAssertEqual($0 as? VirtualQueueError, .invalidDefaults)
            }
    }

}
