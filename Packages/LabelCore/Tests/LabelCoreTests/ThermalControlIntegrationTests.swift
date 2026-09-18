import Foundation
import XCTest
@testable import LabelCore

enum ThermalControlTestFixture {
    static func profile(method: ThermalMethod = .thermalTransfer, configured: Bool = true,
                        media: ThermalMediaConfiguration? = nil, revision: Int = 7) throws -> PrinterProfile {
        let base = try OffsetControlTestFixture.profile()
        let c = base.capabilities
        let fact = CapabilityFact(state: .supported, evidence: .documentedModel(sourceID: "synthetic-thermal-fixture"))
        var defaults = base.configuredDefaults
        defaults.thermalMethod = configured ? method : nil
        return try PrinterProfile(schemaVersion: 7, revision: revision,
            capabilities: .init(model: "synthetic-thermal-model", thermalTransfer: fact,
                cutter: c.cutter, peeler: c.peeler, rewind: c.rewind, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: c.darkness,
                feedSpeeds: c.feedSpeeds, backfeedSpeeds: c.backfeedSpeeds,
                physicalGeometry: c.physicalGeometry, offsets: c.offsets, directThermal: fact),
            installedHardware: base.installedHardware, media: base.media, connection: base.connection,
            configuredDefaults: defaults,
            thermalMedia: media ?? .init(method: .observed(method, evidence: .reportedInstallation),
                ribbonPresent: .observed(method == .thermalTransfer, evidence: .reportedInstallation)))
    }
}

final class ThermalControlIntegrationTests: XCTestCase {
    func testBothThermalMethodsBindBeforeGraphicsAlongsideGeometryDarknessAndOffsets() throws {
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            let profile = try ThermalControlTestFixture.profile(method: method)
            let prepared = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: profile,
                job: .init(offsets: .init(labelTopDots: 2)))
            XCTAssertEqual(prepared.resolvedControls.thermalMethod, .value(method))
            XCTAssertEqual(prepared.profileSnapshot, JobProfileSnapshot(profile: profile))
            XCTAssertEqual(prepared.profileSnapshot.thermalMedia, profile.thermalMedia)
            let text = String(decoding: prepared.bytes, as: UTF8.self)
            XCTAssertTrue(text.hasPrefix(method == .thermalTransfer ? "^XA\n^MTT\n^MMT\n" : "^XA\n^MTD\n^MMT\n"))
            XCTAssertTrue(text.contains("^MD0\n~SD15\n"))
            XCTAssertTrue(text.contains("^MNN\n^LL10\n^PW20\n^LH1,1\n^LS0\n^LT2\n"))
            XCTAssertEqual(try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: profile.resolveControls(
                job: .init(offsets: .init(labelTopDots: 2)))), prepared.bytes)
            XCTAssertEqual(profile.configuredDefaults.offsets?.labelTopDots, 0)
            XCTAssertEqual(try ThermalControlTestFixture.profile(method: method, revision: 8).revision, 8)
            XCTAssertEqual(prepared.profileSnapshot.revision, 7)
        }
    }

    func testHigherPriorityIncompatibleMethodIsRejectedRatherThanFallingBack() throws {
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        for method in [ThermalMethod.directThermal, .thermalTransfer] {
            let other: ThermalMethod = method == .directThermal ? .thermalTransfer : .directThermal
            let profile = try ThermalControlTestFixture.profile(method: method)
            XCTAssertThrowsError(try profile.resolveControls(job: .init(thermalMethod: other)))
            XCTAssertThrowsError(try profile.resolveControls(job: .init(), workflowDefaults: .init(thermalMethod: other)))
            XCTAssertNoThrow(try profile.resolveControls(job: .init(thermalMethod: method),
                workflowDefaults: .init(thermalMethod: other)))
            XCTAssertThrowsError(try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: profile,
                job: .init(thermalMethod: other)))
            XCTAssertThrowsError(try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: profile.resolveControls(
                job: .init(thermalMethod: other))))
        }
    }

    func testNoImplicitThermalMethodOrUnknownConsumableSubstitutionInNewSchema() throws {
        let profile = try ThermalControlTestFixture.profile(configured: false)
        XCTAssertThrowsError(try profile.resolveControls(job: .init())) {
            XCTAssertEqual($0 as? ThermalControlQualification.Error, .explicitMethodRequired)
        }
        XCTAssertEqual(try profile.resolveControls(job: .init(thermalMethod: .thermalTransfer)).thermalMethod,
            .value(.thermalTransfer))
        let unknown = try ThermalControlTestFixture.profile(configured: false, media: .unobserved)
        XCTAssertThrowsError(try unknown.resolveControls(job: .init(thermalMethod: .thermalTransfer)))
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: unknown,
            job: .init(thermalMethod: .thermalTransfer)))
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: unknown.resolveControls(
            job: .init(thermalMethod: .thermalTransfer))))
        let legacy = try PrinterProfile.gc420dUSBReference()
        let bytes = try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: legacy.resolveControls(job: .init()))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("^MT"))
        XCTAssertThrowsError(try legacy.resolveControls(job: .init(thermalMethod: .thermalTransfer)))
    }
}
