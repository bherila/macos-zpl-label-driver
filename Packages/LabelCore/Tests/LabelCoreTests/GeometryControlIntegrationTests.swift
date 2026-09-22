import Foundation
import XCTest
@testable import LabelCore

/// Supplied synthetic geometry qualification, not a supported physical unit row.
enum GeometryControlTestFixture {
    static let fact = CapabilityFact(state: .supported, evidence: .documentedModel(sourceID: "synthetic-geometry-fixture"))
    static func profile(defaults: PrinterControlDefaults? = nil) throws -> PrinterProfile {
        let b = try PrinterProfile.gc420dUSBReference(revision: 7)
        let c = b.capabilities
        func limit(_ value: Int) -> QualifiedDotLimit { .init(fact: fact, maximumDots: value) }
        let geometry = PhysicalGeometryQualification(width: limit(832), continuousLength: limit(1_500),
                                                      homeX: limit(100), homeY: limit(200))
        var tracking = c.tracking; tracking[.continuous] = fact
        return try PrinterProfile(schemaVersion: 5, revision: 7,
            capabilities: .init(model: "synthetic-geometry-profile", thermalTransfer: c.thermalTransfer,
                cutter: c.cutter, peeler: c.peeler, rewind: c.rewind, tracking: tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: fact, physicalGeometry: geometry),
            installedHardware: b.installedHardware, media: b.media, connection: b.connection,
            configuredDefaults: defaults ?? .init(printSpeedIps: 3, darkness: 15, tracking: .continuous,
                mediaGeometry: MediaGeometryRequest(widthDots: 20, lengthDots: 10, originXDot: 1, originYDot: 1)))
    }
}

final class GeometryControlIntegrationTests: XCTestCase {
    func testPerFieldPrecedencePreservesIndependentGeometryAndOriginalSnapshot() throws {
        let p = try GeometryControlTestFixture.profile()
        let job = PrinterControlRequest(mediaGeometry: try .init(originYDot: 3))
        let workflow = PrinterControlDefaults(mediaGeometry: try .init(widthDots: 30, lengthDots: 20, originXDot: 2))
        let resolved = try p.resolveControls(job: job, workflowDefaults: workflow)
        XCTAssertEqual(resolved.mediaGeometry, .value(try .init(widthDots: 30, lengthDots: 20, originXDot: 2, originYDot: 3)))
        XCTAssertEqual(try ZPLControlEncoder().encode(resolved), Data("^MMT\n^PR3\n^MD0\n~SD15\n^MNN\n^LL20\n^PW30\n^LH2,3\n".utf8))
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        let prepared = try ZPLPreparedLabelEncoder().prepare(bitmap: bitmap, profile: p, job: job, workflowDefaults: workflow)
        XCTAssertEqual(prepared.resolvedControls, resolved)
        XCTAssertEqual(prepared.profileSnapshot.schemaVersion, 5)
        XCTAssertEqual(p.configuredDefaults.mediaGeometry?.widthDots, 20)
        let text = String(decoding: prepared.bytes, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("^XA\n^MMT\n^PR3\n^MD0\n~SD15\n^MNN\n^LL20\n^PW30\n^LH2,3\n"))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "^LL20")) .lowerBound,
                          try XCTUnwrap(text.range(of: "^FS")) .lowerBound)
    }

    func testProfileFiveCanonicalDefaultsAndAllMalformedFields() throws {
        let p = try GeometryControlTestFixture.profile()
        let bytes = try PrinterProfileJSON.encode(p)
        XCTAssertEqual(try PrinterProfileJSON.decode(bytes), p)
        XCTAssertEqual(try PrinterProfileJSON.encode(PrinterProfileJSON.decode(bytes)), bytes)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["widthDots", "lengthDots", "originXDot", "originYDot"] {
            for replacement: Any in [true, 32_001, "1"] {
                var changed = root
                var defaults = try XCTUnwrap(root["configuredDefaults"] as? [String: Any])
                var geometry = try XCTUnwrap(defaults["mediaGeometry"] as? [String: Any])
                geometry[key] = replacement; defaults["mediaGeometry"] = geometry; changed["configuredDefaults"] = defaults
                XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
                geometry.removeValue(forKey: key); defaults["mediaGeometry"] = geometry; changed["configuredDefaults"] = defaults
                XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
            }
        }
        for version in [1, 2, 3, 4, 6] {
            var changed = root; changed["schemaVersion"] = version
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testEveryGeometryDeclarationRequiresItsOwnBound() throws {
        let bytes = try PrinterProfileJSON.encode(GeometryControlTestFixture.profile())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["width", "continuousLength", "homeX", "homeY"] {
            var changed = root
            var caps = try XCTUnwrap(root["capabilities"] as? [String: Any])
            var geometry = try XCTUnwrap(caps["physicalGeometry"] as? [String: Any])
            var limit = try XCTUnwrap(geometry[key] as? [String: Any])
            limit["maximumDots"] = NSNull(); geometry[key] = limit; caps["physicalGeometry"] = geometry; changed["capabilities"] = caps
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
            limit["maximumDots"] = true; geometry[key] = limit; caps["physicalGeometry"] = geometry; changed["capabilities"] = caps
            XCTAssertThrowsError(try PrinterProfileJSON.decode(JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testConflictingModeAndLengthCannotBeSilentlyDropped() throws {
        let p = try GeometryControlTestFixture.profile()
        XCTAssertThrowsError(try p.resolveControls(job: .init(tracking: .gap))) {
            XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .continuousModeRequired)
        }
        // This fixture is schema 5 and its black-mark capability fact is
        // supported and documented, so the refusal is about the record's
        // version and must not be reported as a limitation of the printer.
        XCTAssertEqual(p.schemaVersion, 5)
        XCTAssertEqual(p.capabilities.tracking[.blackMark]?.state, .supported)
        XCTAssertThrowsError(try p.resolveControls(job: .init(tracking: .blackMark))) {
            XCTAssertEqual($0 as? PrinterProfileError,
                           .controlRequiresSchemaVersion(.tracking(.blackMark), required: 6, profileVersion: 5))
        }
        let gap = try GeometryControlTestFixture.profile(defaults: .init(tracking: .gap,
            mediaGeometry: MediaGeometryRequest(widthDots: 20, originXDot: 1, originYDot: 1)))
        XCTAssertEqual(try ZPLControlEncoder().encode(gap.resolveControls(job: .init())), Data("^MMT\n^MNY\n^PW20\n^LH1,1\n".utf8))
        XCTAssertThrowsError(try gap.resolveControls(job: .init(tracking: .continuous)))
        let reference = try PrinterProfile.gc420dUSBReference()
        XCTAssertThrowsError(try reference.resolveControls(job: .init(mediaGeometry: MediaGeometryRequest(widthDots: 20))))
    }

    func testPrepareAndDirectEncodeBothRejectKnownRasterClipping() throws {
        let p = try GeometryControlTestFixture.profile()
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        let request = PrinterControlRequest(mediaGeometry: try .init(widthDots: 8))
        let resolved = try p.resolveControls(job: request)
        let encoder = try ZPLPreparedLabelEncoder()
        XCTAssertThrowsError(try encoder.prepare(bitmap: bitmap, profile: p, job: request)) {
            XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .rasterExceedsWidth)
        }
        XCTAssertThrowsError(try encoder.encode(bitmap: bitmap, controls: resolved)) {
            XCTAssertEqual($0 as? PhysicalGeometryQualification.Error, .rasterExceedsWidth)
        }
    }

    func testSameLengthPreparedLabelsCannotMixGeometrySettings() throws {
        let p = try GeometryControlTestFixture.profile()
        let bitmap = try MonochromeBitmap(width: 8, height: 2, bytes: [0x80, 0x80])
        let encoder = try ZPLPreparedLabelEncoder()
        let a = try encoder.prepare(bitmap: bitmap, profile: p)
        let b = try encoder.prepare(bitmap: bitmap, profile: p, job: .init(mediaGeometry: MediaGeometryRequest(widthDots: 21)))
        XCTAssertEqual(a.bytes.count, b.bytes.count)
        let outputs = [ResolvedOutputLabel(sourcePage: 1, regionID: "a"), ResolvedOutputLabel(sourcePage: 1, regionID: "b")]
        XCTAssertThrowsError(try PreparedJobPayload(labels: [.init(output: outputs[0], prepared: a), .init(output: outputs[1], prepared: b)],
            expectedOutputLabels: outputs, monochromeConversion: .textAndBarcodeThreshold(cutoff: 128))) {
            XCTAssertEqual($0 as? PreparedJobPayload.Error, .controlsMismatch)
        }
    }
}
