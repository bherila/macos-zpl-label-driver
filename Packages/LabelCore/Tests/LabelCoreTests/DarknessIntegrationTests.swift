import XCTest
@testable import LabelCore

final class DarknessIntegrationTests: XCTestCase {
    private func profile(version: Int = 4, fact: CapabilityFact = .init(state: .supported,
        evidence: .documentedModel(sourceID: "R45")), defaults: PrinterControlDefaults = .init()) throws -> PrinterProfile {
        let b = try PrinterProfile.gc420dUSBReference()
        let c = b.capabilities
        return try PrinterProfile(schemaVersion: version, revision: 7,
            capabilities: .init(model: "synthetic-qualified-darkness", thermalTransfer: c.thermalTransfer,
                cutter: c.cutter, peeler: c.peeler, rewind: c.rewind, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: fact),
            installedHardware: b.installedHardware, media: b.media, connection: b.connection,
            configuredDefaults: defaults)
    }

    func testAbsoluteDarknessNormalizesRelativeAdjustmentAndPreservesSnapshot() throws {
        let p = try profile(defaults: .init(darkness: 10))
        let bitmap = try MonochromeBitmap(width: 1, height: 1, bytes: [0x80])
        let prepared = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: p,
            job: .init(darkness: 0), workflowDefaults: .init(darkness: 20))
        XCTAssertEqual(prepared.resolvedControls.darkness, .value(0))
        XCTAssertEqual(prepared.profileSnapshot.revision, 7)
        XCTAssertEqual(p.configuredDefaults.darkness, 10)
        let text = String(decoding: prepared.bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("^MD0\n~SD00\n"))
        for command in ["^JU", "~JC", "^JUF", "~JR"] { XCTAssertFalse(text.contains(command)) }
        XCTAssertEqual(try p.resolveControls(job: .init(), workflowDefaults: .init(darkness: 20)).darkness, .value(20))
        XCTAssertEqual(try p.resolveControls(job: .init()).darkness, .value(10))
    }

    func testAllIntegerValuesAndOutputBudget() throws {
        let p = try profile()
        for value in 0...30 {
            let controls = try p.resolveControls(job: .init(darkness: value))
            let expected = "^MMT\n^MD0\n~SD\(value < 10 ? "0" : "")\(value)\n"
            XCTAssertEqual(try ZPLControlEncoder().encode(controls), Data(expected.utf8))
            XCTAssertThrowsError(try ZPLControlEncoder(maxOutputBytes: expected.utf8.count - 1).encode(controls))
        }
        for value in [Int.min, -1, 31, Int.max] {
            XCTAssertThrowsError(try p.resolveControls(job: .init(darkness: value)))
        }
    }

    func testLegacyAndUnqualifiedProfilesRemainUnavailable() throws {
        for version in [1, 2, 3] {
            XCTAssertThrowsError(try profile(version: version).resolveControls(job: .init(darkness: 15)))
        }
        for fact in [CapabilityFact(state: .unknown, evidence: .unobserved),
                     .init(state: .unsupported, evidence: .documentedModel(sourceID: "synthetic-fixture")),
                     .init(state: .supported, evidence: .unobserved)] {
            XCTAssertThrowsError(try profile(fact: fact).resolveControls(job: .init(darkness: 15)))
        }
        let reference = try PrinterProfile.gc420dUSBReference()
        XCTAssertEqual(try reference.resolveControls(job: .init()).darkness, .leaveUnchanged)
        XCTAssertThrowsError(try reference.resolveControls(job: .init(darkness: 15)))
    }

    func testVersionFourProfileRoundTripsQualifiedDefaults() throws {
        let p = try profile(defaults: .init(darkness: 15))
        let data = try PrinterProfileJSON.encode(p)
        let decoded = try PrinterProfileJSON.decode(data)
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(try PrinterProfileJSON.encode(decoded), data)
        XCTAssertEqual(try ZPLControlEncoder().encode(decoded.resolveControls(job: .init())),
                       Data("^MMT\n^MD0\n~SD15\n".utf8))
    }
    func testVersionFourDefaultFieldFailsClosed() throws {
        let p = try profile(defaults: .init(darkness: 15))
        let bytes = try PrinterProfileJSON.encode(p)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for replacement: Any in [true, -1, 31, "15"] {
            var changed = root
            var defaults = try XCTUnwrap(root["configuredDefaults"] as? [String: Any])
            defaults["darkness"] = replacement; changed["configuredDefaults"] = defaults
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
        var changed = root
        var defaults = try XCTUnwrap(root["configuredDefaults"] as? [String: Any])
        defaults.removeValue(forKey: "darkness"); changed["configuredDefaults"] = defaults
        XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        for version in [1, 2, 3, 5] {
            changed = root; changed["schemaVersion"] = version
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testMixedPreparedDarknessCannotEnterSameJob() throws {
        let p = try profile()
        let bitmap = try MonochromeBitmap(width: 1, height: 1, bytes: [0x80])
        let a = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: p, job: .init(darkness: 10))
        let b = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: p, job: .init(darkness: 20))
        XCTAssertEqual(a.bytes.count, b.bytes.count)
        let outputs = [ResolvedOutputLabel(sourcePage: 1, regionID: "a"),
                       ResolvedOutputLabel(sourcePage: 1, regionID: "b")]
        XCTAssertThrowsError(try PreparedJobPayload(labels: [
            PreparedOutputLabel(output: outputs[0], prepared: a),
            PreparedOutputLabel(output: outputs[1], prepared: b)], expectedOutputLabels: outputs,
            monochromeConversion: .textAndBarcodeThreshold(cutoff: 128))) {
            XCTAssertEqual($0 as? PreparedJobPayload.Error, .controlsMismatch)
        }
    }

}
