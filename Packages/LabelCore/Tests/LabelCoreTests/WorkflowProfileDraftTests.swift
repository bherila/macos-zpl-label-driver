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

    func testMarginsSurviveCorrectionEditsAndInvalidStockChangesAreAtomic() throws {
        let original = try profile()
        var draft = try WorkflowProfileDraft(nextRevisionOf: original)
        let margins = try OutputMargins(left: 10, top: 2, right: 12, bottom: 3)
        try draft.setOutputMargins(margins)
        try draft.moveRegion(id: "A", to: 1)
        let correction = try WorkflowProfileDraft(nextRevisionOf: draft.profile)
        XCTAssertEqual(correction.profile.outputMargins, margins)
        XCTAssertEqual(correction.profile.schemaVersion, 3)
        XCTAssertEqual(correction.profile.pageRules, draft.profile.pageRules)
        try draft.setOutputStock(id: "smaller-stock", size: PhysicalSize(width: .inches(2), height: .inches(3)))
        XCTAssertEqual(draft.profile.outputMargins, margins)
        XCTAssertEqual(draft.profile.schemaVersion, 3)
        let before = draft.profile
        XCTAssertThrowsError(try draft.setOutputStock(id: "small-stock", size: PhysicalSize(
            width: Millimeters(10), height: Millimeters(10))))
        XCTAssertEqual(draft.profile, before)
        XCTAssertThrowsError(try draft.setOutputMargins(OutputMargins(left: 200, top: 0, right: 0, bottom: 0)))
        XCTAssertEqual(draft.profile, before)
        XCTAssertEqual(original.schemaVersion, 2)
        XCTAssertEqual(original.outputMargins, .zero)
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

    func testOutputStockEditPreservesSheetRulesSkipsCopyOrderAndRevision() throws {
        let base = try profile()
        let original = try WorkflowProfile(id: base.id, revision: base.revision,
            outputStockID: base.outputStockID, outputStock: base.outputStock,
            monochromeConversion: base.monochromeConversion,
            pageRules: base.pageRules + [try WorkflowPageRule(sourcePage: 3,
                expectedInput: base.pageRules[0].expectedInput, disposition: .skip(.customsForm))])
        var draft = try WorkflowProfileDraft(nextRevisionOf: original)
        let before = draft.profile
        let stock = PhysicalSize(width: try Millimeters.inches(2), height: try Millimeters.inches(3))
        try draft.setOutputStock(id: "configured-2x3", size: stock)
        XCTAssertEqual(draft.profile.id, original.id)
        XCTAssertEqual(draft.profile.revision, original.revision + 1)
        XCTAssertEqual(draft.profile.pageRules, original.pageRules)
        XCTAssertEqual(draft.profile.monochromeConversion, original.monochromeConversion)
        XCTAssertEqual(draft.profile.outputStockID, "configured-2x3")
        XCTAssertEqual(draft.profile.outputStock, stock)
        let decoded = try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(draft.profile))
        XCTAssertEqual(decoded, draft.profile)
        let pages = try (0..<3).map { _ in
            try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        }
        let copies = LabelOrderPlan.CopyPolicy.engine(copies: 2, collated: true)
        let priorPlan = try ExtractionPlanner.plan(sourcePages: pages, profile: before, copyPolicy: copies)
        let plan = try ExtractionPlanner.plan(sourcePages: pages, profile: decoded, copyPolicy: copies)
        XCTAssertEqual(plan.outputLabels.map(\.regionID), ["A", "C", "B", "A", "C", "B"])
        XCTAssertEqual(plan.outputLabels.map(\.sourceRect), priorPlan.outputLabels.map(\.sourceRect))
        XCTAssertEqual(plan.skippedPages, priorPlan.skippedPages)
        XCTAssertEqual(plan.skippedPages, [AccountedNonLabelPage(sourcePage: 3, reason: .customsForm)])
        XCTAssertTrue(plan.outputLabels.allSatisfy { $0.outputStock == stock && $0.outputStockID == "configured-2x3" })
        let accepted = draft
        XCTAssertThrowsError(try draft.setOutputStock(id: "invalid stock", size: original.outputStock))
        XCTAssertEqual(draft, accepted)
        XCTAssertEqual(original.outputStock, base.outputStock)
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

    func testAddRemovePreservePagesGlobalOrderAndCanonicalRoundTrip() throws {
        var draft = WorkflowProfileDraft(profile: try profile())
        try draft.duplicateRegion(id: "A", newID: "D")
        let added = draft.profile
        XCTAssertEqual(try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(added)), added)
        let pages = try (0..<2).map { _ in try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792) }
        let plan = try ExtractionPlanner.plan(sourcePages: pages, profile: added,
            copyPolicy: .engine(copies: 2, collated: false))
        XCTAssertEqual(plan.outputLabels.map(\.regionID), ["A", "A", "D", "D", "C", "C", "B", "B"])
        XCTAssertEqual(plan.outputLabels.map(\.sourcePage), [1, 1, 1, 1, 2, 2, 1, 1])
        try draft.removeRegion(id: "A")
        XCTAssertEqual(try ExtractionPlanner.plan(sourcePages: pages, profile: draft.profile)
            .outputLabels.map(\.regionID), ["D", "C", "B"])
        XCTAssertEqual(draft.profile.pageRules.map(\.expectedInput), added.pageRules.map(\.expectedInput))
        let before = draft
        XCTAssertThrowsError(try draft.removeRegion(id: "C")) {
            XCTAssertEqual($0 as? WorkflowProfileDraft.Error, .lastRegionOnPage)
        }
        XCTAssertThrowsError(try draft.duplicateRegion(id: "D", newID: "B"))
        XCTAssertThrowsError(try draft.duplicateRegion(id: "missing", newID: "E"))
        XCTAssertEqual(draft, before)
    }

    func testAddRejectsPublicPerPageLimitWithoutChangingDraft() throws {
        var draft = WorkflowProfileDraft(profile: try profile())
        for index in 0..<254 { try draft.duplicateRegion(id: "A", newID: "new-\(index)") }
        let before = draft
        XCTAssertThrowsError(try draft.duplicateRegion(id: "A", newID: "overflow"))
        XCTAssertEqual(draft, before)
        XCTAssertEqual(try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(draft.profile)), draft.profile)
    }

    func testExplicitSkipReportsReasonRetainsGeometryAndRestoresFullPageLast() throws {
        var draft = WorkflowProfileDraft(profile: try profile())
        let original = draft.profile
        try draft.skipPage(1, reason: .customsForm)
        XCTAssertEqual(draft.profile.pageRules[0].disposition, .skip(.customsForm))
        XCTAssertEqual(draft.profile.pageRules.map(\.expectedInput), original.pageRules.map(\.expectedInput))
        XCTAssertEqual(draft.profile.pageRules.map(\.structuralAnchors), original.pageRules.map(\.structuralAnchors))
        let pages = try (0..<2).map { _ in try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792) }
        let plan = try ExtractionPlanner.plan(sourcePages: pages, profile: draft.profile,
            copyPolicy: .engine(copies: 2, collated: true))
        XCTAssertEqual(plan.outputLabels.map(\.regionID), ["C", "C"])
        XCTAssertEqual(plan.skippedPages.map(\.sourcePage), [1])
        XCTAssertEqual(plan.skippedPages.map(\.reason), [.customsForm])
        XCTAssertEqual(try WorkflowProfileJSON.decode(WorkflowProfileJSON.encode(draft.profile)), draft.profile)
        let skipped = draft
        XCTAssertThrowsError(try draft.skipPage(2, reason: .instructions)) {
            XCTAssertEqual($0 as? WorkflowProfileDraft.Error, .lastOutputPage)
        }
        XCTAssertThrowsError(try draft.restorePage(1, newRegionID: "C"))
        XCTAssertThrowsError(try draft.skipPage(99, reason: .explicitlyIgnored))
        XCTAssertEqual(draft, skipped)
        try draft.restorePage(1, newRegionID: "restored")
        let restored = try ExtractionPlanner.plan(sourcePages: pages, profile: draft.profile)
        XCTAssertEqual(restored.outputLabels.map(\.regionID), ["C", "restored"])
        XCTAssertEqual(restored.outputLabels.last?.normalizedRect,
            try NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertTrue(restored.skippedPages.isEmpty)
        XCTAssertThrowsError(try draft.restorePage(1, newRegionID: "again"))
        XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages: pages + [pages[0]], profile: draft.profile)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .unaccountedSourcePage(3))
        }
    }

    func testSkippedPageStillRequiresItsGeometryAndStructuralAnchor() throws {
        let original = try profile()
        let anchor = try StructuralAnchorExpectation(id: "instruction-border", kind: .border,
            normalizedRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        let first = original.pageRules[0]
        let guarded = try WorkflowProfile(id: original.id, revision: original.revision,
            outputStockID: original.outputStockID, outputStock: original.outputStock,
            pageRules: [WorkflowPageRule(sourcePage: 1, expectedInput: first.expectedInput,
                disposition: first.disposition, structuralAnchors: [anchor]), original.pageRules[1]])
        var draft = WorkflowProfileDraft(profile: guarded)
        try draft.skipPage(1, reason: .instructions)
        let letter = try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        let matched = try AnalyzedSourcePage(pageBox: letter,
            anchors: [ObservedPageAnchor(kind: .border, normalizedRect: anchor.normalizedRect)])
        let second = try AnalyzedSourcePage(pageBox: letter, anchors: [])
        XCTAssertEqual(try ExtractionPlanner.plan(analyzedPages: [matched, second], profile: draft.profile)
            .skippedPages.map(\.reason), [.instructions])
        let missing = try AnalyzedSourcePage(pageBox: letter, anchors: [])
        XCTAssertThrowsError(try ExtractionPlanner.plan(analyzedPages: [missing, second], profile: draft.profile)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .missingAnchor(page: 1, anchorID: anchor.id))
        }
        let changed = try AnalyzedSourcePage(pageBox: PDFPageBox(originX: 0, originY: 0, width: 300, height: 792),
            anchors: matched.anchors)
        XCTAssertThrowsError(try ExtractionPlanner.plan(analyzedPages: [changed, second], profile: draft.profile)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .inputGeometryMismatch(page: 1))
        }
    }
}
