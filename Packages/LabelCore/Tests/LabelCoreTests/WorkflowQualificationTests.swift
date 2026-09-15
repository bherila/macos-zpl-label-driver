import XCTest
@testable import LabelCore

final class WorkflowQualificationTests: XCTestCase {
    private let page = try! PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
    private let border = try! NormalizedRect(x: 0.075, y: 0.24, width: 0.438, height: 0.52)

    private func profile(
        revision: Int = 1,
        regionX: Double = 0.075,
        includeChecks: Bool = true
    ) throws -> WorkflowProfile {
        let region = try NormalizedRect(x: regionX, y: 0.24, width: 0.438, height: 0.52)
        return try WorkflowProfile(
            id: "confirmed-letter", revision: revision,
            outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(
                width: try Millimeters.inches(4), height: try Millimeters.inches(6)
            ),
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(
                    uprightPhysicalSize: try page.effectivePhysicalSize()
                ),
                disposition: .extract([try ExtractionRegion(
                    id: "label", normalizedRect: region, outputOrder: 0
                )]),
                structuralAnchors: includeChecks ? [try StructuralAnchorExpectation(
                    id: "outer-border", kind: .border, normalizedRect: region
                )] : []
            )]
        )
    }

    private func analyzed(_ observed: NormalizedRect? = nil) throws -> AnalyzedSourcePage {
        try AnalyzedSourcePage(
            pageBox: page,
            anchors: observed.map { [.init(kind: .border, normalizedRect: $0)] } ?? []
        )
    }

    func testMatchingUnconfirmedOrImportedProfileStillRequiresConfirmation() throws {
        let candidate = try profile()
        let imported = try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(candidate))
        let result = try WorkflowMatcher.match(
            analyzedPages: [analyzed(border)], profile: imported
        )
        guard case let .confirmationRequired(plan) = result else {
            return XCTFail("unconfirmed imported profile was qualified")
        }
        XCTAssertEqual(plan.profileRevision, 1)
    }

    func testQualificationRequiresExplicitChecksOnEveryPage() throws {
        XCTAssertThrowsError(try UnattendedWorkflowQualification(
            userConfirmed: profile(includeChecks: false)
        )) {
            XCTAssertEqual(
                $0 as? UnattendedWorkflowQualification.Error,
                .missingStructuralChecks(page: 1)
            )
        }
    }

    func testExactConfirmedImmutableProfileCanMatchUnattended() throws {
        let candidate = try profile()
        let qualification = try UnattendedWorkflowQualification(userConfirmed: candidate)
        let result = try WorkflowMatcher.match(
            analyzedPages: [analyzed(border)],
            profile: candidate,
            qualification: qualification
        )
        guard case let .qualified(plan) = result else {
            return XCTFail("exact confirmed profile was not qualified")
        }
        XCTAssertEqual(qualification.profileID, candidate.id)
        XCTAssertEqual(qualification.profileRevision, candidate.revision)
        XCTAssertEqual(plan.profileID, candidate.id)
    }

    func testAnyProfileRevisionOrGeometryChangeRequiresNewConfirmation() throws {
        let original = try profile()
        let qualification = try UnattendedWorkflowQualification(userConfirmed: original)

        let revised = try profile(revision: 2)
        XCTAssertEqual(
            try WorkflowMatcher.match(
                analyzedPages: [analyzed(border)], profile: revised,
                qualification: qualification
            ),
            .confirmationRequired(try ExtractionPlanner.plan(
                analyzedPages: [analyzed(border)], profile: revised
            ))
        )

        let moved = try profile(regionX: 0.08)
        let movedBorder = try NormalizedRect(x: 0.08, y: 0.24, width: 0.438, height: 0.52)
        guard case .confirmationRequired = try WorkflowMatcher.match(
            analyzedPages: [analyzed(movedBorder)], profile: moved,
            qualification: qualification
        ) else { return XCTFail("changed geometry reused an old qualification") }
    }

    func testQualificationCannotOverrideStructuralMismatch() throws {
        let candidate = try profile()
        let qualification = try UnattendedWorkflowQualification(userConfirmed: candidate)
        let moved = try NormalizedRect(x: 0.2, y: 0.24, width: 0.438, height: 0.52)
        XCTAssertThrowsError(try WorkflowMatcher.match(
            analyzedPages: [analyzed(moved)],
            profile: candidate,
            qualification: qualification
        )) {
            XCTAssertEqual(
                $0 as? ExtractionPlanError,
                .missingAnchor(page: 1, anchorID: "outer-border")
            )
        }
    }
}
