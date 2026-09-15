import XCTest
@testable import LabelCore

final class StructuralMatchingTests: XCTestCase {
    private let letter = try! PhysicalSize(width: Millimeters.inches(8.5), height: Millimeters.inches(11))
    private let stock = try! PhysicalSize(width: Millimeters.inches(4), height: Millimeters.inches(6))
    private let anchorRect = try! NormalizedRect(x: 0.1, y: 0.7, width: 0.5, height: 0.1)

    private func page() throws -> PDFPageBox {
        try PDFPageBox(originX: 18, originY: 24, width: 612, height: 792)
    }

    private func profile() throws -> WorkflowProfile {
        let anchor = try StructuralAnchorExpectation(
            id: "barcode-zone", kind: .barcodeLike, normalizedRect: anchorRect,
            maximumCoordinateDeviation: 0.01
        )
        return try WorkflowProfile(
            id: "anchored-letter", revision: 2,
            outputStockID: "gc420d-4x6-precut", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: letter),
                disposition: .extract([try ExtractionRegion(
                    id: "label", normalizedRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5),
                    outputOrder: 0
                )]),
                structuralAnchors: [anchor]
            )]
        )
    }

    func testMatchingAnalysisApprovesOriginalPageGeometryOnly() throws {
        let source = try page()
        let analyzed = try AnalyzedSourcePage(
            pageBox: source,
            anchors: [.init(kind: .barcodeLike, normalizedRect: anchorRect)]
        )
        let plan = try ExtractionPlanner.plan(analyzedPages: [analyzed], profile: profile())
        XCTAssertEqual(plan.outputLabels[0].sourceRect, source.sourceRect(for: try NormalizedRect(
            x: 0, y: 0, width: 0.5, height: 0.5
        )))
    }

    func testRequiredAnalysisIsDistinctFromObservedNoMatch() throws {
        XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages: [page()], profile: profile())) {
            XCTAssertEqual($0 as? ExtractionPlanError, .analysisRequired(page: 1))
        }
        let analyzed = try AnalyzedSourcePage(pageBox: page(), anchors: [])
        XCTAssertThrowsError(try ExtractionPlanner.plan(analyzedPages: [analyzed], profile: profile())) {
            XCTAssertEqual($0 as? ExtractionPlanError, .missingAnchor(page: 1, anchorID: "barcode-zone"))
        }
    }

    func testChangedAndAmbiguousLayoutsFailBeforeAnyPlan() throws {
        let shifted = try ObservedPageAnchor(
            kind: .barcodeLike,
            normalizedRect: NormalizedRect(x: 0.2, y: 0.7, width: 0.5, height: 0.1)
        )
        XCTAssertThrowsError(try ExtractionPlanner.plan(
            analyzedPages: [try AnalyzedSourcePage(pageBox: page(), anchors: [shifted])],
            profile: profile()
        )) {
            XCTAssertEqual($0 as? ExtractionPlanError, .missingAnchor(page: 1, anchorID: "barcode-zone"))
        }
        let close = try ObservedPageAnchor(
            kind: .barcodeLike,
            normalizedRect: NormalizedRect(x: 0.105, y: 0.7, width: 0.5, height: 0.1)
        )
        XCTAssertThrowsError(try ExtractionPlanner.plan(
            analyzedPages: [try AnalyzedSourcePage(
                pageBox: page(),
                anchors: [.init(kind: .barcodeLike, normalizedRect: anchorRect), close]
            )],
            profile: profile()
        )) {
            XCTAssertEqual($0 as? ExtractionPlanError, .ambiguousAnchor(page: 1, anchorID: "barcode-zone"))
        }
    }

    func testAnchorSchemaAndAnalysisAreBounded() throws {
        XCTAssertThrowsError(try StructuralAnchorExpectation(
            id: "bad id", kind: .border, normalizedRect: anchorRect
        ))
        XCTAssertThrowsError(try StructuralAnchorExpectation(
            id: "anchor", kind: .border, normalizedRect: anchorRect,
            maximumCoordinateDeviation: 0.5
        ))
        let candidates = Array(
            repeating: ObservedPageAnchor(kind: .darkBlock, normalizedRect: anchorRect),
            count: 257
        )
        XCTAssertThrowsError(try AnalyzedSourcePage(pageBox: page(), anchors: candidates)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .invalidAnalysis)
        }
    }
}
