import Foundation
import XCTest
@testable import LabelCore

enum OffsetControlTestFixture {
    static let fact = CapabilityFact(state: .supported, evidence: .documentedModel(sourceID: "synthetic-offset-fixture"))
    static func profile(defaults: PrinterControlDefaults? = nil) throws -> PrinterProfile {
        let b = try GeometryControlTestFixture.profile()
        let c = b.capabilities
        var tracking = c.tracking; tracking[.blackMark] = fact
        return try PrinterProfile(schemaVersion: 6, revision: b.revision,
            capabilities: .init(model: "synthetic-offset-profile", thermalTransfer: c.thermalTransfer, cutter: c.cutter,
                peeler: c.peeler, rewind: c.rewind, tracking: tracking, printSpeedChoicesIps: c.printSpeedChoicesIps,
                darkness: c.darkness, physicalGeometry: c.physicalGeometry,
                offsets: .init(blackMark: .init(fact: fact, range: -10...20), shiftLeft: .init(fact: fact, range: -30...40),
                               labelTop: .init(fact: fact, range: -5...6))),
            installedHardware: b.installedHardware, media: b.media, connection: b.connection,
            configuredDefaults: defaults ?? .init(printSpeedIps: 3, darkness: 15, tracking: .continuous,
                mediaGeometry: b.configuredDefaults.mediaGeometry, offsets: .init(shiftLeftDots: 0, labelTopDots: 0)))
    }
}

final class OffsetControlIntegrationTests: XCTestCase {
    func testOffsetFieldsResolveIndependentlyAndBindBeforeOriginalGraphics() throws {
        let profile = try OffsetControlTestFixture.profile()
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        let job = PrinterControlRequest(offsets: .init(labelTopDots: 2))
        let workflow = PrinterControlDefaults(offsets: .init(shiftLeftDots: 1))
        let prepared = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: profile, job: job, workflowDefaults: workflow)
        XCTAssertEqual(prepared.resolvedControls.offsets, .value(.init(shiftLeftDots: 1, labelTopDots: 2)))
        XCTAssertEqual(profile.configuredDefaults.offsets, .init(shiftLeftDots: 0, labelTopDots: 0))
        let text = String(decoding: prepared.bytes, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("^XA\n^MMT\n^PR3\n^MD0\n~SD15\n^MNN\n^LL10\n^PW20\n^LH1,1\n^LS1\n^LT2\n"))
        XCTAssertEqual(prepared.profileSnapshot.schemaVersion, 6)
    }

    func testSignedOffsetsRejectKnownClippingAtBothEncodingEntryPoints() throws {
        let profile = try OffsetControlTestFixture.profile()
        let bitmap = try MonochromeBitmap(width: 8, height: 4, bytes: [0x80, 0x80, 0x80, 0x80])
        for offsets in [OffsetControlRequest(shiftLeftDots: 2), .init(shiftLeftDots: -12), .init(labelTopDots: -2), .init(labelTopDots: 6)] {
            let request = PrinterControlRequest(offsets: offsets)
            let resolved = try profile.resolveControls(job: request)
            let encoder = try ZPLPreparedLabelEncoder()
            XCTAssertThrowsError(try encoder.prepare(bitmap: bitmap, profile: profile, job: request))
            XCTAssertThrowsError(try encoder.encode(bitmap: bitmap, controls: resolved))
        }
        // A positive left shift offsets the known home, rather than adding to it.
        let request = PrinterControlRequest(mediaGeometry: try .init(widthDots: 8), offsets: .init(shiftLeftDots: 1))
        XCTAssertNoThrow(try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: profile, job: request))
    }

    func testCanonicalProfileSixAndEveryOffsetFieldFailsClosed() throws {
        let profile = try OffsetControlTestFixture.profile()
        let bytes = try PrinterProfileJSON.encode(profile)
        XCTAssertEqual(try PrinterProfileJSON.decode(bytes), profile)
        XCTAssertEqual(try PrinterProfileJSON.encode(PrinterProfileJSON.decode(bytes)), bytes)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["blackMarkOffsetDots", "shiftLeftDots", "labelTopDots"] {
            for value: Any in [true, "0", 0.5, 10_000] {
                var changed = root
                var defaults = try XCTUnwrap(root["configuredDefaults"] as? [String: Any])
                var offsets = try XCTUnwrap(defaults["offsets"] as? [String: Any])
                offsets[key] = value; defaults["offsets"] = offsets; changed["configuredDefaults"] = defaults
                XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
                offsets.removeValue(forKey: key); defaults["offsets"] = offsets; changed["configuredDefaults"] = defaults
                XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
            }
        }
        for key in ["blackMark", "shiftLeft", "labelTop"] {
            for pair: (Any, Any) in [(NSNull(), 0), (2, 1), (true, 0), (-10_000, 10_000)] {
                var changed = root
                var caps = try XCTUnwrap(root["capabilities"] as? [String: Any])
                var offsets = try XCTUnwrap(caps["offsets"] as? [String: Any])
                var range = try XCTUnwrap(offsets[key] as? [String: Any])
                range["minimumDots"] = pair.0; range["maximumDots"] = pair.1
                offsets[key] = range; caps["offsets"] = offsets; changed["capabilities"] = caps
                XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
            }
        }
        for version in [1, 2, 3, 4, 5, 7] {
            var changed = root; changed["schemaVersion"] = version
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testBlackMarkMappingRequiresQualifiedOffsetAndRejectsIncompatibleLength() throws {
        let profile = try OffsetControlTestFixture.profile(defaults: .init(tracking: .blackMark,
            mediaGeometry: MediaGeometryRequest(widthDots: 20, originXDot: 1, originYDot: 1),
            offsets: .init(blackMarkOffsetDots: 0, shiftLeftDots: 0, labelTopDots: 0)))
        XCTAssertEqual(try ZPLControlEncoder().encode(profile.resolveControls(job: .init())), Data("^MMT\n^PW20\n^LH1,1\n^MNM,0\n^LS0\n^LT0\n".utf8))
        XCTAssertThrowsError(try profile.resolveControls(job: .init(tracking: .gap)))
        XCTAssertThrowsError(try profile.resolveControls(job: .init(mediaGeometry: MediaGeometryRequest(lengthDots: 10))))
        XCTAssertThrowsError(try PrinterProfile.gc420dUSBReference().resolveControls(job: .init(offsets: .init(shiftLeftDots: 0))))
    }

    func testPreparedJobsCannotMixSameLengthOffsetValues() throws {
        let profile = try OffsetControlTestFixture.profile()
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        let encoder = try ZPLPreparedLabelEncoder()
        let a = try encoder.prepare(bitmap: bitmap, profile: profile)
        let b = try encoder.prepare(bitmap: bitmap, profile: profile, job: .init(offsets: .init(labelTopDots: 1)))
        XCTAssertEqual(a.bytes.count, b.bytes.count)
        let outputs = [ResolvedOutputLabel(sourcePage: 1, regionID: "a"), ResolvedOutputLabel(sourcePage: 1, regionID: "b")]
        XCTAssertThrowsError(try PreparedJobPayload(labels: [.init(output: outputs[0], prepared: a), .init(output: outputs[1], prepared: b)],
            expectedOutputLabels: outputs, monochromeConversion: .textAndBarcodeThreshold(cutoff: 128)))
    }
}
