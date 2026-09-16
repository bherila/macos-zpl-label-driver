import XCTest
@testable import LabelCore

final class WorkflowProfileDraftTests: XCTestCase {
    private func profile(revision: Int = 4) throws -> WorkflowProfile {
        let letter = PhysicalSize(
            width: try Millimeters.inches(8.5), height: try Millimeters.inches(11)
        )
        let stock = PhysicalSize(
            width: try Millimeters.inches(4), height: try Millimeters.inches(6)
        )
        func region(_ id: String, _ order: Int, _ x: Double) throws -> ExtractionRegion {
            try ExtractionRegion(
                id: id,
                normalizedRect: NormalizedRect(x: x, y: 0.1, width: 0.25, height: 0.4),
                outputOrder: order
            )
        }
        return try WorkflowProfile(
            id: "teach-once-letter", revision: revision,
            outputStockID: "nominal-4x6", outputStock: stock,
            pageRules: [
                try WorkflowPageRule(
                    sourcePage: 1,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: letter),
                    disposition: .extract([try region("A", 0, 0.1), try region("B", 2, 0.6)])
                ),
                try WorkflowPageRule(
                    sourcePage: 2,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: letter),
                    disposition: .extract([try region("C", 1, 0.3)])
                ),
            ]
        )
    }

    func testNextRevisionEditsCanonicalCoordinatesAndRotation() throws {
        var draft = try WorkflowProfileDraft(nextRevisionOf: profile())
        let rect = try NormalizedRect(x: 0.2, y: 0.25, width: 0.3, height: 0.5)
        try draft.updateRegion(id: "A", normalizedRect: rect, rotation: .degrees90)
        let saved = draft.validatedProfile()
        XCTAssertEqual(saved.revision, 5)
        guard case let .extract(regions) = saved.pageRules[0].disposition else {
            return XCTFail("expected extraction rule")
        }
        XCTAssertEqual(regions[0].normalizedRect, rect)
        XCTAssertEqual(regions[0].rotation, .degrees90)
    }

    func testGlobalReorderSurvivesJSONRoundTripAndPlannerCopies() throws {
        var draft = try WorkflowProfileDraft(nextRevisionOf: profile())
        try draft.moveRegion(id: "B", to: 0)
        let saved = draft.validatedProfile()
        let reopened = try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(saved))
        XCTAssertEqual(reopened, saved)
        let pages = try (0..<2).map { _ in
            try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        }
        let plan = try ExtractionPlanner.plan(
            sourcePages: pages, profile: reopened,
            copyPolicy: .engine(copies: 2, collated: true)
        )
        XCTAssertEqual(plan.outputLabels.map(\.regionID), ["B", "A", "C", "B", "A", "C"])
    }

    func testInvalidEditsLeaveDraftUnchanged() throws {
        var draft = WorkflowProfileDraft(profile: try profile())
        let original = draft
        XCTAssertThrowsError(try draft.moveRegion(id: "missing", to: 0)) {
            XCTAssertEqual($0 as? WorkflowProfileDraft.Error, .regionNotFound("missing"))
        }
        XCTAssertEqual(draft, original)
        XCTAssertThrowsError(try draft.moveRegion(id: "A", to: 3)) {
            XCTAssertEqual($0 as? WorkflowProfileDraft.Error, .invalidDestination)
        }
        XCTAssertEqual(draft, original)
    }

    func testRevisionOverflowFails() throws {
        XCTAssertThrowsError(try WorkflowProfileDraft(nextRevisionOf: profile(revision: .max))) {
            XCTAssertEqual($0 as? WorkflowProfileDraft.Error, .revisionOverflow)
        }
    }
}
