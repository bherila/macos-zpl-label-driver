import Foundation
import XCTest
@testable import LabelCore

/// Explicit synthetic qualification; does not assert observed GC420d feed rates.
enum MotorSpeedTestFixture {
    static func profile(
        revision: Int = 7,
        defaults: PrinterControlDefaults = .init(printSpeedIps: 3, feedSpeedIps: 4, backfeedSpeedIps: 2),
        feed: QualifiedSpeedChoices = .init(
            fact: .init(state: .supported, evidence: .documentedModel(sourceID: "synthetic-speed-fixture")),
            choicesIps: [2, 4]),
        backfeed: QualifiedSpeedChoices = .init(
            fact: .init(state: .supported, evidence: .documentedModel(sourceID: "synthetic-speed-fixture")),
            choicesIps: [2, 3]), version: Int = 3
    ) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: revision)
        let c = base.capabilities
        return try PrinterProfile(schemaVersion: version, revision: revision,
            capabilities: PrinterCapabilities(model: "synthetic-qualified-speed-profile",
                thermalTransfer: c.thermalTransfer, cutter: c.cutter, peeler: c.peeler,
                rewind: c.rewind, tracking: c.tracking, printSpeedChoicesIps: c.printSpeedChoicesIps,
                darkness: c.darkness, feedSpeeds: feed, backfeedSpeeds: backfeed),
            installedHardware: base.installedHardware, media: base.media, connection: base.connection,
            configuredDefaults: defaults)
    }
}

final class MotorSpeedIntegrationTests: XCTestCase {
    func testIndependentPrecedenceAndExactPreparedSnapshot() throws {
        let profile = try MotorSpeedTestFixture.profile()
        let controls = try profile.resolveControls(job: .init(printSpeedIps: 4, feedSpeedIps: 2),
            workflowDefaults: .init(printSpeedIps: 2, feedSpeedIps: 4, backfeedSpeedIps: 3))
        XCTAssertEqual(controls.printSpeedIps, .value(4))
        XCTAssertEqual(controls.feedSpeedIps, .value(2))
        XCTAssertEqual(controls.backfeedSpeedIps, .value(3))
        XCTAssertEqual(try ZPLControlEncoder().encode(controls), Data("^MMT\n^PR4,2,3\n".utf8))
        let bitmap = try MonochromeBitmap(width: 1, height: 1, bytes: [0x80])
        let prepared = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: profile,
            job: .init(feedSpeedIps: 2))
        let edited = try MotorSpeedTestFixture.profile(revision: 8,
            defaults: .init(printSpeedIps: 4, feedSpeedIps: 4, backfeedSpeedIps: 3))
        XCTAssertEqual(prepared.profileSnapshot.revision, 7)
        XCTAssertEqual(prepared.profileSnapshot.schemaVersion, 3)
        XCTAssertEqual(prepared.resolvedControls.feedSpeedIps, .value(2))
        XCTAssertEqual(prepared.resolvedControls.backfeedSpeedIps, .value(2))
        XCTAssertNotEqual(prepared.resolvedControls, try edited.resolveControls(job: .init()))
        XCTAssertTrue(String(decoding: prepared.bytes, as: UTF8.self).contains("^PR3,2,2\n"))
        XCTAssertThrowsError(try ZPLControlEncoder(maxOutputBytes: 4).encode(controls)) {
            XCTAssertEqual($0 as? ZPLControlEncodingError, .outputLimit)
        }
    }

    func testUnknownUnsupportedAndIncompleteRemainDistinct() throws {
        let request = PrinterControlRequest(printSpeedIps: 3, feedSpeedIps: 4, backfeedSpeedIps: 2)
        let reference = try PrinterProfile.gc420dUSBReference()
        XCTAssertThrowsError(try reference.resolveControls(job: request)) {
            XCTAssertEqual($0 as? PrinterProfileError, .unavailableFeedSpeed(.unknown))
        }
        let unsupported = QualifiedSpeedChoices(fact: .init(state: .unsupported,
            evidence: .documentedModel(sourceID: "synthetic-speed-fixture")), choicesIps: [])
        let profile = try MotorSpeedTestFixture.profile(defaults: .init(), feed: unsupported)
        XCTAssertThrowsError(try profile.resolveControls(job: request)) {
            XCTAssertEqual($0 as? PrinterProfileError, .unavailableFeedSpeed(.unsupported))
        }
        let unset = try MotorSpeedTestFixture.profile(defaults: .init())
        XCTAssertEqual(try unset.resolveControls(job: .init()).feedSpeedIps, .notExplicitlyControlled)
        XCTAssertEqual(try unset.resolveControls(job: .init()).backfeedSpeedIps, .notExplicitlyControlled)
        XCTAssertThrowsError(try unset.resolveControls(job: .init(printSpeedIps: 3, feedSpeedIps: 4))) {
            XCTAssertEqual($0 as? PrinterProfileError, .incompleteMotorSpeeds)
        }
        for request in [PrinterControlRequest(feedSpeedIps: 3), .init(backfeedSpeedIps: 4)] {
            XCTAssertThrowsError(try MotorSpeedTestFixture.profile().resolveControls(job: request))
        }
    }

    func testInvalidQualifiedCapabilitiesAndLegacyVersionsFail() throws {
        for choices in [QualifiedSpeedChoices(fact: .init(state: .supported, evidence: .unobserved), choicesIps: [2]),
                        .init(fact: .init(state: .supported, evidence: .reportedInstallation), choicesIps: []),
                        .init(fact: .init(state: .unknown, evidence: .unobserved), choicesIps: [2]),
                        .init(fact: .init(state: .unsupported, evidence: .reportedInstallation), choicesIps: [2]),
                        .init(fact: .init(state: .supported, evidence: .reportedInstallation), choicesIps: [1]),
                        .init(fact: .init(state: .supported, evidence: .reportedInstallation), choicesIps: [13])] {
            XCTAssertThrowsError(try MotorSpeedTestFixture.profile(defaults: .init(), feed: choices)) {
                XCTAssertEqual($0 as? PrinterProfileError, .invalidMotorSpeedCapability)
            }
            XCTAssertThrowsError(try MotorSpeedTestFixture.profile(defaults: .init(), backfeed: choices))
        }
        XCTAssertThrowsError(try MotorSpeedTestFixture.profile(version: 2))
        XCTAssertThrowsError(try MotorSpeedTestFixture.profile(defaults: .init(feedSpeedIps: 4)))
    }

    func testVersionThreePrivateProfileRoundTripAndStrictFields() throws {
        let profile = try MotorSpeedTestFixture.profile()
        let bytes = try PrinterProfileJSON.encode(profile)
        XCTAssertEqual(try PrinterProfileJSON.decode(bytes), profile)
        XCTAssertEqual(try PrinterProfileJSON.encode(PrinterProfileJSON.decode(bytes)), bytes)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["feedSpeedIps", "backfeedSpeedIps"] {
            var changed = root
            var defaults = try XCTUnwrap(changed["configuredDefaults"] as? [String: Any])
            defaults.removeValue(forKey: key); changed["configuredDefaults"] = defaults
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
            defaults[key] = true; changed["configuredDefaults"] = defaults
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        for key in ["feedSpeeds", "backfeedSpeeds"] {
            for choices: [Any] in [[2, 2], [true], [Int.max]] {
                var changed = root
                var caps = try XCTUnwrap(changed["capabilities"] as? [String: Any])
                var fact = try XCTUnwrap(caps[key] as? [String: Any])
                fact["choicesIps"] = choices; caps[key] = fact; changed["capabilities"] = caps
                XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
            }
            var changed = root
            var caps = try XCTUnwrap(changed["capabilities"] as? [String: Any])
            caps.removeValue(forKey: key); changed["capabilities"] = caps
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        for version in [1, 2] {
            var changed = root; changed["schemaVersion"] = version
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testLegacyControlBytesAndProfileRoundTripRemainUnchanged() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let bytes = try PrinterProfileJSON.encode(profile)
        XCTAssertEqual(try PrinterProfileJSON.decode(bytes), profile)
        XCTAssertEqual(try ZPLControlEncoder().encode(profile.resolveControls(job: .init(printSpeedIps: 3))),
            Data("^MMT\n^PR3\n".utf8))
        XCTAssertEqual(profile.capabilities.feedSpeeds, .unverified)
        XCTAssertEqual(profile.capabilities.backfeedSpeeds, .unverified)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var changed = root
        var caps = try XCTUnwrap(changed["capabilities"] as? [String: Any])
        caps["feedSpeeds"] = ["choicesIps": [2]]; changed["capabilities"] = caps
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
    }
    func testCompleteJobRejectsMixedMotorSettingsOnOneProfileRevision() throws {
        let profile = try MotorSpeedTestFixture.profile()
        let bitmap = try MonochromeBitmap(width: 1, height: 1, bytes: [0x80])
        let encoder = try ZPLPreparedLabelEncoder()
        let first = try encoder.prepare(bitmap: bitmap, profile: profile, job: .init(feedSpeedIps: 2))
        let other = try encoder.prepare(bitmap: bitmap, profile: profile, job: .init(feedSpeedIps: 4))
        let outputs = [ResolvedOutputLabel(sourcePage: 1, regionID: "a"),
                       ResolvedOutputLabel(sourcePage: 1, regionID: "b")]
        XCTAssertEqual(first.bytes.count, other.bytes.count)
        XCTAssertEqual(first.profileSnapshot, other.profileSnapshot)
        XCTAssertThrowsError(try PreparedJobPayload(labels: [
            PreparedOutputLabel(output: outputs[0], prepared: first),
            PreparedOutputLabel(output: outputs[1], prepared: other)],
            expectedOutputLabels: outputs, monochromeConversion: .textAndBarcodeThreshold(cutoff: 128))) {
            XCTAssertEqual($0 as? PreparedJobPayload.Error, .controlsMismatch)
        }
        let job = try PreparedJobPayload(labels: [
            PreparedOutputLabel(output: outputs[0], prepared: first),
            PreparedOutputLabel(output: outputs[1], prepared: first)],
            expectedOutputLabels: outputs, monochromeConversion: .textAndBarcodeThreshold(cutoff: 128))
        XCTAssertEqual(job.resolvedControls.feedSpeedIps, .value(2))
        XCTAssertEqual(job.resolvedControls.backfeedSpeedIps, .value(2))
        XCTAssertEqual(job.bytes, first.bytes + first.bytes)
        XCTAssertEqual(job.labelCount, 2)
    }

    func testLegacyPrintRateDoesNotPromiseSecondarySpeedsUnchanged() throws {
        let controls = try PrinterProfile.gc420dUSBReference().resolveControls(job: .init(printSpeedIps: 3))
        XCTAssertEqual(controls.feedSpeedIps, .notExplicitlyControlled)
        XCTAssertEqual(controls.backfeedSpeedIps, .notExplicitlyControlled)
        XCTAssertEqual(try ZPLControlEncoder().encode(controls), Data("^MMT\n^PR3\n".utf8))
    }

}
