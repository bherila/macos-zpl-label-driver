import XCTest
@testable import LabelCore

final class ReferenceWorkflowsTests: XCTestCase {
    func testInitialSetUsesOneStockAndDistinctInputGeometry() throws {
        let workflows = try ReferenceWorkflowDefinition.gc420dInitialSet(revision: 4)
        XCTAssertEqual(workflows.map(\.id), ["native-4x6", "letter-to-4x6", "a4-to-4x6"])
        XCTAssertEqual(Set(workflows.map(\.outputStockID)), ["gc420d-4x6-precut"])
        XCTAssertTrue(workflows.allSatisfy { $0.outputStock == workflows[0].outputStock })
        XCTAssertEqual(workflows[0].expectedInput.uprightPhysicalSize.width.value, 101.6, accuracy: 0.0001)
        XCTAssertEqual(workflows[1].expectedInput.uprightPhysicalSize.width.value, 215.9, accuracy: 0.0001)
        XCTAssertEqual(workflows[2].expectedInput.uprightPhysicalSize.width.value, 210, accuracy: 0.0001)
    }

    func testNativeWorkflowPlansOnlyAFullNativePage() throws {
        let workflow = try ReferenceWorkflowDefinition.gc420dInitialSet(revision: 4)[0]
        let native = try PDFPageBox(originX: 12, originY: -7, width: 288, height: 432)
        let plan = try workflow.plan(sourcePages: [native])
        XCTAssertEqual(plan.profileRevision, 4)
        XCTAssertEqual(plan.outputLabels.map(\.regionID), ["full-page"])
        XCTAssertEqual(plan.outputLabels[0].sourceRect, PDFSourceRect(x: 12, y: -7, width: 288, height: 432))

        let letter = try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        XCTAssertThrowsError(try workflow.plan(sourcePages: [letter])) {
            XCTAssertEqual($0 as? ExtractionPlanError, .inputGeometryMismatch(page: 1))
        }
    }

    func testLetterAndA4NeverGuessAnUnconfiguredCrop() throws {
        let workflows = try ReferenceWorkflowDefinition.gc420dInitialSet()
        let letter = try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        let a4 = try PDFPageBox(originX: 0, originY: 0, width: 595.2756, height: 841.8898)
        XCTAssertThrowsError(try workflows[1].plan(sourcePages: [letter])) {
            XCTAssertEqual($0 as? ReferenceWorkflowError, .requiresTeachOnce(workflowID: "letter-to-4x6"))
        }
        XCTAssertThrowsError(try workflows[2].plan(sourcePages: [a4])) {
            XCTAssertEqual($0 as? ReferenceWorkflowError, .requiresTeachOnce(workflowID: "a4-to-4x6"))
        }
    }

    func testInvalidRevisionCannotCreateReferenceProfiles() {
        XCTAssertThrowsError(try ReferenceWorkflowDefinition.gc420dInitialSet(revision: 0)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .invalidProfile)
        }
    }
}
