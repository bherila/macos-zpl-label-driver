import Foundation
import XCTest
@testable import LabelCore

final class WorkflowProfileJSONTests: XCTestCase {
    private func profile() throws -> WorkflowProfile {
        let letter = PhysicalSize(
            width: try Millimeters.inches(8.5), height: try Millimeters.inches(11)
        )
        let stock = PhysicalSize(
            width: try Millimeters.inches(4), height: try Millimeters.inches(6)
        )
        return try WorkflowProfile(
            id: "saved-letter", revision: 7,
            outputStockID: "gc420d-4x6-precut", outputStock: stock,
            monochromeConversion: .photographicOrderedDither4x4,
            pageRules: [
                try WorkflowPageRule(
                    sourcePage: 1,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: letter),
                    disposition: .extract([try ExtractionRegion(
                        id: "label-a",
                        normalizedRect: NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5),
                        rotation: .degrees90,
                        outputOrder: 0
                    )]),
                    structuralAnchors: [try StructuralAnchorExpectation(
                        id: "barcode-zone", kind: .barcodeLike,
                        normalizedRect: NormalizedRect(x: 0.2, y: 0.6, width: 0.3, height: 0.1)
                    )]
                ),
                try WorkflowPageRule(
                    sourcePage: 2,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: letter),
                    disposition: .skip(.instructions)
                ),
            ]
        )
    }

    func testExactWireFormatRoundTripsDeterministically() throws {
        let original = try profile()
        let first = try WorkflowProfileJSON.encode(original)
        XCTAssertEqual(try WorkflowProfileJSON.decode(first), original)
        XCTAssertEqual(try WorkflowProfileJSON.encode(original), first)
        XCTAssertEqual(
            try WorkflowProfileJSON.decode(first).monochromeConversion,
            .photographicOrderedDither4x4
        )
        XCTAssertLessThan(first.count, WorkflowProfileJSON.maximumBytes)
    }

    func testImagingPolicyIsRequiredAndRejectsInvalidParameters() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: WorkflowProfileJSON.encode(profile())
        ) as? [String: Any])
        root.removeValue(forKey: "monochromeConversion")
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual(
                $0 as? WorkflowProfileJSONError,
                .missingField("monochromeConversion")
            )
        }

        root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: WorkflowProfileJSON.encode(profile())
        ) as? [String: Any])
        root["monochromeConversion"] = [
            "mode": "textAndBarcodeThreshold", "cutoff": 256,
        ]
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual(
                $0 as? WorkflowProfileJSONError,
                .invalidValue("monochromeConversion")
            )
        }

        root["monochromeConversion"] = [
            "mode": "photographicOrderedDither4x4", "cutoff": 128,
        ]
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual(
                $0 as? WorkflowProfileJSONError,
                .invalidValue("monochromeConversion")
            )
        }
    }

    func testUnknownFieldsCannotCarryCommandsPathsOrDocuments() throws {
        let encoded = try WorkflowProfileJSON.encode(profile())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["rawZPL", "filePath", "embeddedDocument"] {
            root[key] = "untrusted"
            let data = try JSONSerialization.data(withJSONObject: root)
            XCTAssertThrowsError(try WorkflowProfileJSON.decode(data)) {
                XCTAssertEqual($0 as? WorkflowProfileJSONError, .unknownField)
            }
            root.removeValue(forKey: key)
        }

        var pages = try XCTUnwrap(root["pages"] as? [[String: Any]])
        pages[0]["filePath"] = "/private/input.pdf"
        root["pages"] = pages
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .unknownField)
        }
    }

    func testMalformedOversizedAndUnknownSchemaFail() throws {
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(Data("{".utf8))) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .malformedJSON)
        }
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            Data(repeating: 0x20, count: WorkflowProfileJSON.maximumBytes + 1)
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .inputTooLarge)
        }
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            WorkflowProfileJSON.encode(profile()),
            maximumBytes: WorkflowProfileJSON.maximumBytes + 1
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .invalidLimit)
        }
        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: WorkflowProfileJSON.encode(profile())
        ) as? [String: Any])
        root["schemaVersion"] = 1
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .unsupportedSchema)
        }
    }

    func testWrongTypesEnumsAndOutputBoundsFail() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: WorkflowProfileJSON.encode(profile())
        ) as? [String: Any])
        root["revision"] = true
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .invalidType("revision"))
        }
        root["revision"] = 1e30
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .invalidType("revision"))
        }

        root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: WorkflowProfileJSON.encode(profile())
        ) as? [String: Any])
        var pages = try XCTUnwrap(root["pages"] as? [[String: Any]])
        var disposition = try XCTUnwrap(pages[0]["disposition"] as? [String: Any])
        var regions = try XCTUnwrap(disposition["regions"] as? [[String: Any]])
        regions[0]["scalePolicy"] = "stretch"
        disposition["regions"] = regions
        pages[0]["disposition"] = disposition
        root["pages"] = pages
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(
            JSONSerialization.data(withJSONObject: root)
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .invalidValue("region"))
        }

        XCTAssertThrowsError(try WorkflowProfileJSON.encode(profile(), maximumBytes: 10)) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .outputTooLarge)
        }
        XCTAssertThrowsError(try WorkflowProfileJSON.encode(
            profile(), maximumBytes: WorkflowProfileJSON.maximumBytes + 1
        )) {
            XCTAssertEqual($0 as? WorkflowProfileJSONError, .invalidLimit)
        }
    }
}
