import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class QuartzStructuralAnalyzerTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appending(path: "Fixtures/generated/\(name).pdf"))
    }

    private func principalBorder(_ page: AnalyzedSourcePage) throws -> ObservedPageAnchor {
        try XCTUnwrap(page.anchors?.max {
            let lhs = $0.normalizedRect.width * $0.normalizedRect.height
            let rhs = $1.normalizedRect.width * $1.normalizedRect.height
            return lhs < rhs
        })
    }

    func testConcreteLetterFixtureProducesExpectedLabelBorder() throws {
        let analyzed = try QuartzStructuralAnalyzer.analyzeBorders(
            originalPDF: fixture("letter-one"), pageNumber: 1
        )
        let border = try principalBorder(analyzed).normalizedRect
        XCTAssertEqual(border.x, 46.0 / 612.0, accuracy: 0.01)
        XCTAssertEqual(border.y, 190.0 / 792.0, accuracy: 0.01)
        XCTAssertEqual(border.width, 268.0 / 612.0, accuracy: 0.01)
        XCTAssertEqual(border.height, 412.0 / 792.0, accuracy: 0.01)
    }

    func testChangedLayoutCannotValidateOriginalFixtureAnchor() throws {
        let original = try QuartzStructuralAnalyzer.analyzeBorders(
            originalPDF: fixture("letter-one"), pageNumber: 1
        )
        let changed = try QuartzStructuralAnalyzer.analyzeBorders(
            originalPDF: fixture("layout-changed"), pageNumber: 1
        )
        let expectedBorder = try principalBorder(original).normalizedRect
        let stock = PhysicalSize(
            width: try Millimeters.inches(4), height: try Millimeters.inches(6)
        )
        let profile = try WorkflowProfile(
            id: "fixture-layout", revision: 1,
            outputStockID: "nominal-4x6", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(
                    uprightPhysicalSize: try original.pageBox.effectivePhysicalSize()
                ),
                disposition: .extract([try ExtractionRegion(
                    id: "label", normalizedRect: expectedBorder, outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "outer-border", kind: .border,
                    normalizedRect: expectedBorder,
                    maximumCoordinateDeviation: 0.03
                )]
            )]
        )
        XCTAssertNoThrow(try ExtractionPlanner.plan(analyzedPages: [original], profile: profile))
        XCTAssertThrowsError(try ExtractionPlanner.plan(analyzedPages: [changed], profile: profile)) {
            XCTAssertEqual(
                $0 as? ExtractionPlanError,
                .missingAnchor(page: 1, anchorID: "outer-border")
            )
        }
    }

    func testHardAnalysisLimitsCannotBeRaised() throws {
        XCTAssertThrowsError(try QuartzStructuralAnalyzer.analyzeBorders(
            originalPDF: fixture("letter-one"), pageNumber: 1,
            maximumDimension: 1_025
        )) {
            XCTAssertEqual($0 as? QuartzStructuralAnalyzer.Error, .invalidLimits)
        }
        XCTAssertThrowsError(try QuartzStructuralAnalyzer.analyzeBorders(
            originalPDF: fixture("letter-one"), pageNumber: 1,
            maximumInputBytes: 100 * 1024 * 1024 + 1
        )) {
            XCTAssertEqual($0 as? QuartzStructuralAnalyzer.Error, .invalidLimits)
        }
    }
}
