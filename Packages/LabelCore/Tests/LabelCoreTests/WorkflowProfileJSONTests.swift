import Foundation
import XCTest
@testable import LabelCore

final class WorkflowProfileJSONTests: XCTestCase {
    func testMarginSchemaRoundtripLegacyBytesAndPlannedBinding() throws {
        let original = try profile()
        let legacy = try WorkflowProfileJSON.encode(original)
        XCTAssertFalse(String(decoding: legacy, as: UTF8.self).contains("outputMargins"))
        XCTAssertEqual(try WorkflowProfileJSON.encode(WorkflowProfileJSON.decode(legacy)), legacy)
        let margins = try OutputMargins(left: 1.5, top: 2, right: 2.5, bottom: 3)
        var draft = WorkflowProfileDraft(profile: original)
        try draft.setOutputMargins(margins)
        XCTAssertEqual(draft.profile.schemaVersion, 3)
        let bytes = try WorkflowProfileJSON.encode(draft.profile)
        XCTAssertEqual(try WorkflowProfileJSON.decode(bytes), draft.profile)
        let analyzed = try original.pageRules.sorted { $0.sourcePage < $1.sourcePage }.map { rule in
            try AnalyzedSourcePage(pageBox: PDFPageBox(originX: 0, originY: 0,
                width: rule.expectedInput.uprightPhysicalSize.width.value * 72 / 25.4,
                height: rule.expectedInput.uprightPhysicalSize.height.value * 72 / 25.4),
                anchors: rule.structuralAnchors.map { ObservedPageAnchor(kind: $0.kind, normalizedRect: $0.normalizedRect) })
        }
        let plan = try ExtractionPlanner.plan(analyzedPages: analyzed, profile: draft.profile)
        XCTAssertTrue(plan.outputLabels.allSatisfy { $0.outputMargins == margins })
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for value: Any in [true, -1.0, "1.5"] {
            root["outputMargins"] = ["left": value, "top": 2, "right": 2.5, "bottom": 3]
            XCTAssertThrowsError(try WorkflowProfileJSON.decode(JSONSerialization.data(withJSONObject: root)))
        }
        root["outputMargins"] = ["left": 1.5, "top": 2, "right": 2.5]
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(JSONSerialization.data(withJSONObject: root)))
        root["outputMargins"] = ["left": 1.5, "top": 2, "right": 2.5, "bottom": 3]
        root["schemaVersion"] = 2
        XCTAssertThrowsError(try WorkflowProfileJSON.decode(JSONSerialization.data(withJSONObject: root)))
    }

    func testExactIntegerIdentityAcrossLargeRevisionAndOrder() throws {
        let original = try profile()
        for value in [9_007_199_254_740_993, Int.max] {
            let expected = try WorkflowProfile(id: original.id, revision: value,
                outputStockID: original.outputStockID, outputStock: original.outputStock,
                pageRules: [try WorkflowPageRule(sourcePage: 1,
                    expectedInput: original.pageRules[0].expectedInput,
                    disposition: .extract([try ExtractionRegion(id: "large-order",
                        normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1), outputOrder: value)]))])
            XCTAssertEqual(try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(expected)), expected)
        }
        let template = String(decoding: try WorkflowProfileJSON.encode(original), as: UTF8.self)
        for token in ["9007199254740993.5", "7.000000000000000000000000001", "9223372036854775808", "true"] {
            XCTAssertThrowsError(try WorkflowProfileJSON.decode(Data(template.replacingOccurrences(
                of: "\"revision\":7", with: "\"revision\":" + token).utf8)))
        }
        for token in ["7.0", "7e0", "700e-2"] {
            XCTAssertEqual(try WorkflowProfileJSON.decode(Data(template.replacingOccurrences(
                of: "\"revision\":7", with: "\"revision\":" + token).utf8)), original)
        }
    }

    func testEditedFractionalCoordinatesPreserveExactIdentityAcrossReload() throws {
        let original = try profile()
        let fraction = 20.0 / (612.0 * 25.4 / 72.0)
        for x in [fraction, fraction.nextUp, fraction.nextDown, 0.0000000001, 0.49999999999999994] {
            let edited = try WorkflowProfile(id: original.id, revision: original.revision,
                outputStockID: original.outputStockID, outputStock: original.outputStock,
                monochromeConversion: original.monochromeConversion,
                pageRules: [try WorkflowPageRule(sourcePage: 1,
                    expectedInput: original.pageRules[0].expectedInput,
                    disposition: .extract([try ExtractionRegion(id: "edited-label",
                        normalizedRect: NormalizedRect(x: x, y: 0.1, width: 0.2, height: 0.2),
                        outputOrder: 0)]))])
            let bytes = try WorkflowProfileJSON.encode(edited)
            let loaded = try WorkflowProfileJSON.decode(bytes)
            XCTAssertEqual(loaded, edited)
            XCTAssertEqual(try WorkflowProfileJSON.encode(loaded), bytes)
        }
    }

    func testTypedPageRegionLimitMatchesImportAndBoundaryRoundTrip() throws {
        let original = try profile()
        let regions = try (0..<257).map { index in
            try ExtractionRegion(id: "region-\(index)",
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                outputOrder: index)
        }
        let boundaryRule = try WorkflowPageRule(sourcePage: 1,
            expectedInput: original.pageRules[0].expectedInput,
            disposition: .extract(Array(regions.prefix(256))))
        let boundary = try WorkflowProfile(id: "boundary-regions", revision: 1,
            outputStockID: original.outputStockID, outputStock: original.outputStock,
            pageRules: [boundaryRule])
        XCTAssertEqual(try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(boundary)), boundary)
        XCTAssertThrowsError(try WorkflowPageRule(sourcePage: 1,
            expectedInput: boundaryRule.expectedInput, disposition: .extract(regions))) {
            XCTAssertEqual($0 as? ExtractionPlanError, .invalidProfile)
        }
    }

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
