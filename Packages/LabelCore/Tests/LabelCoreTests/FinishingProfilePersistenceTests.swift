import Foundation
import XCTest
@testable import LabelCore

final class FinishingProfilePersistenceTests: XCTestCase {
    private let fact = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-finishing-persistence"))
    private func configuration(_ base: PrinterProfile) -> FinishingProfileConfiguration {
        .init(finishing: .init(modes: [.tearOff: fact], enabledModes: [.tearOff],
            installed: .init(cutter: .observed(false, evidence: .reportedInstallation))),
            stock: .init(media: base.media, compatibleModes: [
                .tearOff: .observed(true, evidence: .reportedInstallation),
                .cut: .observed(false, evidence: .reportedInstallation), .peel: .unobserved]),
            schedules: .init(everyLabel: fact, batch: fact, endOfJob: fact, maximumBatchSize: 5))
    }
    private func profile(_ configuration: FinishingProfileConfiguration?, version: Int = 8) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference()
        return try .init(schemaVersion: version, revision: 11, capabilities: base.capabilities,
            installedHardware: base.installedHardware, media: base.media, connection: base.connection,
            finishingConfiguration: configuration)
    }
    func testStorageOnlyProfileCannotResolveOrEncodeThroughEitherOrdinaryEntryPath() throws {
        let base = try ThermalControlTestFixture.profile(method: .directThermal)
        let stored = try PrinterProfile(schemaVersion: 8, revision: base.revision,
            capabilities: base.capabilities, installedHardware: base.installedHardware,
            media: base.media, connection: base.connection, configuredDefaults: base.configuredDefaults,
            thermalMedia: base.thermalMedia)
        XCTAssertThrowsError(try stored.resolveControls(job: .init())) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        let valid = try base.resolveControls(job: .init())
        let forged = ResolvedPrinterControls(profileSchemaVersion: 8, profileRevision: valid.profileRevision,
            thermalMethod: valid.thermalMethod, finishing: valid.finishing, printSpeedIps: valid.printSpeedIps,
            feedSpeedIps: valid.feedSpeedIps, backfeedSpeedIps: valid.backfeedSpeedIps,
            darkness: valid.darkness, tracking: valid.tracking, mediaGeometry: valid.mediaGeometry, offsets: valid.offsets)
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        XCTAssertThrowsError(try ZPLControlEncoder().encode(forged)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: forged)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: stored)) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        XCTAssertNoThrow(try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: base))
    }

    func testCanonicalRoundTripPreservesEachDeclarationUnknownAndAbsentValue() throws {
        let base = try PrinterProfile.gc420dUSBReference()
        let original = try profile(configuration(base))
        let bytes = try PrinterProfileJSON.encode(original)
        let restored = try PrinterProfileJSON.decode(bytes)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(try PrinterProfileJSON.encode(restored), bytes)
        XCTAssertEqual(restored.finishingConfiguration?.stock.compatibleModes[.peel], .unobserved)
        XCTAssertNil(restored.finishingConfiguration?.stock.compatibleModes[.rewind])
        XCTAssertEqual(restored.finishingConfiguration?.schedules.maximumBatchSize, 5)
        XCTAssertThrowsError(try restored.validate(.init(finishing: .cut)))
        XCTAssertThrowsError(try profile(configuration(base), version: 7))
        let legacy = try PrinterProfileJSON.encode(base)
        XCTAssertEqual(try PrinterProfileJSON.encode(PrinterProfileJSON.decode(legacy)), legacy)
        XCTAssertNil(try PrinterProfileJSON.decode(legacy).finishingConfiguration)
        XCTAssertEqual(try PrinterProfileJSON.decode(PrinterProfileJSON.encode(profile(nil))), try profile(nil))
    }
    func testModelInventoryStockAndBatchDeclarationsCannotContradictBoundProfile() throws {
        let base = try PrinterProfile.gc420dUSBReference(), good = configuration(base)
        let changed = MediaConfiguration(form: .observed(.continuous, evidence: .reportedInstallation),
            nominalLabelFace: .unobserved, configuredTracking: .unobserved, calibration: .unobserved)
        XCTAssertThrowsError(try profile(.init(finishing: good.finishing,
            stock: .init(media: changed, compatibleModes: good.stock.compatibleModes))))
        XCTAssertThrowsError(try profile(.init(finishing: .init(modes: [.cut: fact]), stock: good.stock)))
        XCTAssertThrowsError(try profile(.init(finishing: .init(installed: .init(
            cutter: .observed(true, evidence: .reportedInstallation))), stock: good.stock)))
        XCTAssertThrowsError(try profile(.init(finishing: good.finishing,
            stock: .init(media: base.media, compatibleModes: [.tearOff: .unobserved]))))
        XCTAssertThrowsError(try profile(.init(finishing: good.finishing, stock: good.stock,
            schedules: .init(batch: fact))))
    }
    func testStrictKeysBooleanTypesEnabledSetAndRequiredVersionFields() throws {
        let base = try PrinterProfile.gc420dUSBReference()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:
            PrinterProfileJSON.encode(profile(configuration(base)))) as? [String: Any])
        for bad in [0 as Any, 1 as Any, "true" as Any, NSNull()] {
            var changed = root
            var config = try XCTUnwrap(changed["finishingConfiguration"] as? [String: Any])
            var installed = try XCTUnwrap(config["installed"] as? [String: Any])
            var cutter = try XCTUnwrap(installed["cutter"] as? [String: Any]); cutter["value"] = bad
            installed["cutter"] = cutter; config["installed"] = installed; changed["finishingConfiguration"] = config
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        for bad in [0 as Any, 1 as Any, "true" as Any, NSNull()] {
            var changed = root
            var config = try XCTUnwrap(changed["finishingConfiguration"] as? [String: Any])
            var stock = try XCTUnwrap(config["stock"] as? [String: Any])
            var modes = try XCTUnwrap(stock["compatibleModes"] as? [String: Any])
            var tear = try XCTUnwrap(modes["tearOff"] as? [String: Any]); tear["value"] = bad
            modes["tearOff"] = tear; stock["compatibleModes"] = modes
            config["stock"] = stock; changed["finishingConfiguration"] = config
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        for enabled in [["tearOff", "tearOff"], ["raw"], ["tearOff", "cut"]] {
            var changed = root, config = try XCTUnwrap(root["finishingConfiguration"] as? [String: Any])
            config["enabledModes"] = enabled; changed["finishingConfiguration"] = config
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        var changed = root; changed.removeValue(forKey: "finishingConfiguration")
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root; changed["schemaVersion"] = 7
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root; changed["schemaVersion"] = 9
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        changed = root
        var config = try XCTUnwrap(root["finishingConfiguration"] as? [String: Any]); config["rawCommand"] = "synthetic"
        changed["finishingConfiguration"] = config
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
    }
}
