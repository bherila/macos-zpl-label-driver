import XCTest
@testable import LabelCore

final class ExtractionPlanTests: XCTestCase {
    private let letter = try! PhysicalSize(width: Millimeters.inches(8.5), height: Millimeters.inches(11))
    private let stock = try! PhysicalSize(width: Millimeters.inches(4), height: Millimeters.inches(6))

    private func page(rotation: Int = 0, originX: Double = 0, originY: Double = 0) throws -> PDFPageBox {
        try PDFPageBox(
            originX: originX, originY: originY,
            width: 612, height: 792,
            rotationDegreesClockwise: rotation
        )
    }

    private func region(_ id: String, _ order: Int, x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) throws -> ExtractionRegion {
        try ExtractionRegion(
            id: id,
            normalizedRect: NormalizedRect(x: x, y: y, width: width, height: height),
            outputOrder: order
        )
    }

    private func rule(page: Int, disposition: WorkflowPageDisposition) throws -> WorkflowPageRule {
        try WorkflowPageRule(
            sourcePage: page,
            expectedInput: ExpectedInputPage(uprightPhysicalSize: letter),
            disposition: disposition
        )
    }

    func testInputSheetAndOutputStockRemainSeparate() throws {
        let profile = try WorkflowProfile(
            id: "letter-to-4x6", revision: 3, outputStockID: "gc420d-4x6",
            outputStock: stock,
            pageRules: [try rule(page: 1, disposition: .extract([try region("label", 0)]))]
        )
        let plan = try ExtractionPlanner.plan(sourcePages: [page()], profile: profile)
        XCTAssertEqual(plan.outputLabels[0].outputStock, stock)
        XCTAssertNotEqual(letter, stock)
        XCTAssertEqual(plan.outputLabels[0].profileRevision, 3)
    }

    func testRotationAndShiftedOriginUseCanonicalSourceTransform() throws {
        let quarter = try region("quarter", 0, x: 0, y: 0, width: 0.5, height: 0.5)
        let rotatedLetter = try PhysicalSize(width: Millimeters.inches(11), height: Millimeters.inches(8.5))
        let profile = try WorkflowProfile(
            id: "rotated", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: rotatedLetter),
                disposition: .extract([quarter])
            )]
        )
        let plan = try ExtractionPlanner.plan(
            sourcePages: [page(rotation: 90, originX: 10, originY: 20)], profile: profile
        )
        XCTAssertEqual(plan.outputLabels[0].sourceRect, PDFSourceRect(x: 10, y: 20, width: 306, height: 396))
        XCTAssertEqual(plan.outputLabels[0].scalePolicy, .uniformFit)
    }

    func testMultiplePagesRegionsAndCopiesUseExplicitOutputOrder() throws {
        let rules = [
            try rule(page: 1, disposition: .extract([try region("B", 1), try region("A", 0)])),
            try rule(page: 2, disposition: .extract([try region("C", 2)])),
        ]
        let profile = try WorkflowProfile(
            id: "ordered", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: rules
        )
        let collated = try ExtractionPlanner.plan(
            sourcePages: [page(), page()], profile: profile,
            copyPolicy: .engine(copies: 2, collated: true)
        )
        XCTAssertEqual(collated.outputLabels.map(\.regionID), ["A", "B", "C", "A", "B", "C"])
        let uncollated = try ExtractionPlanner.plan(
            sourcePages: [page(), page()], profile: profile,
            copyPolicy: .engine(copies: 2, collated: false)
        )
        XCTAssertEqual(uncollated.outputLabels.map(\.regionID), ["A", "A", "B", "B", "C", "C"])
    }

    func testEveryPageMustBeAccountedForAndExplicitSkipIsReported() throws {
        let incomplete = try WorkflowProfile(
            id: "incomplete", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [try rule(page: 1, disposition: .extract([try region("A", 0)]))]
        )
        XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages: [page(), page()], profile: incomplete)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .unaccountedSourcePage(2))
        }
        let explicit = try WorkflowProfile(
            id: "explicit", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [
                try rule(page: 1, disposition: .extract([try region("A", 0)])),
                try rule(page: 2, disposition: .skip(.customsForm)),
            ]
        )
        let plan = try ExtractionPlanner.plan(sourcePages: [page(), page()], profile: explicit)
        XCTAssertEqual(plan.outputLabels.map(\.regionID), ["A"])
        XCTAssertEqual(plan.skippedPages, [.init(sourcePage: 2, reason: .customsForm)])
    }

    func testChangedGeometryAndMissingPagesFailBeforePlanningOutput() throws {
        let profile = try WorkflowProfile(
            id: "letter", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [
                try rule(page: 1, disposition: .extract([try region("A", 0)])),
                try rule(page: 2, disposition: .skip(.instructions)),
            ]
        )
        XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages: [page()], profile: profile)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .missingSourcePage(2))
        }
        let a4 = try PDFPageBox(originX: 0, originY: 0, width: 595.2756, height: 841.8898)
        XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages: [a4, page()], profile: profile)) {
            XCTAssertEqual($0 as? ExtractionPlanError, .inputGeometryMismatch(page: 1))
        }
    }

    func testProfileAndOutputBoundsRejectUnsafePlans() throws {
        XCTAssertThrowsError(try ExtractionRegion(
            id: "bad id", normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1), outputOrder: 0
        ))
        XCTAssertThrowsError(try ExpectedInputPage(uprightPhysicalSize: letter, toleranceMillimeters: .infinity))
        XCTAssertThrowsError(try WorkflowProfile(
            id: "duplicate", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [try rule(page: 1, disposition: .extract([
                try region("A", 0), try region("B", 0),
            ]))]
        ))
        XCTAssertThrowsError(try WorkflowProfile(
            id: "duplicate-id", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [try rule(page: 1, disposition: .extract([
                try region("A", 0), try region("A", 1),
            ]))]
        ))
        let profile = try WorkflowProfile(
            id: "bounded", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [try rule(page: 1, disposition: .extract([try region("A", 0)]))]
        )
        XCTAssertThrowsError(try ExtractionPlanner.plan(
            sourcePages: [page()], profile: profile,
            copyPolicy: .engine(copies: 2, collated: true), maximumOutputLabels: 1
        )) {
            XCTAssertEqual($0 as? ExtractionPlanError, .tooManyOutputLabels)
        }
        XCTAssertThrowsError(try ExtractionPlanner.plan(
            sourcePages: [page()], profile: profile,
            copyPolicy: .engine(copies: 0, collated: true)
        )) {
            XCTAssertEqual($0 as? ExtractionPlanError, .invalidCopyPolicy)
        }
    }
    func testPageRangesPrecedeCopiesInBothPlannerEntryPointsAndRetainSelectedNonlabels() throws {
        let profile = try WorkflowProfile(id: "range-copies", revision: 1, outputStockID: "stock", outputStock: stock,
            pageRules: [rule(page: 1, disposition: .extract([region("A",0),region("B",1)])),
                        rule(page: 2, disposition: .extract([region("C",2)])),
                        rule(page: 3, disposition: .skip(.customsForm))])
        let pages = try [page(),page(),page()]
        let analyzed = try pages.map { try AnalyzedSourcePage(pageBox:$0,anchors:nil) }
        for collated in [true,false] {
            let expected = collated ? ["A","B","A","B"] : ["A","A","B","B"]
            let direct = try ExtractionPlanner.plan(sourcePages:pages,profile:profile,
                selectedSourcePages:[1,3],copyPolicy:.engine(copies:2,collated:collated))
            let observed = try ExtractionPlanner.plan(analyzedPages:analyzed,profile:profile,
                selectedSourcePages:[1,3],copyPolicy:.engine(copies:2,collated:collated))
            XCTAssertEqual(direct,observed)
            XCTAssertEqual(direct.outputLabels.map(\.regionID),expected)
            XCTAssertEqual(direct.sourcePageCount,3)
            XCTAssertEqual(direct.skippedPages.map(\.sourcePage),[3])
            XCTAssertTrue(try ExtractionPlanner.plan(sourcePages:pages,profile:profile,
                selectedSourcePages:[1]).skippedPages.isEmpty)
            XCTAssertTrue(try ExtractionPlanner.plan(analyzedPages:analyzed,profile:profile,
                selectedSourcePages:[1]).skippedPages.isEmpty)
        }
    }
    func testExplicitRangeCannotHideUnexpectedSourcePagesOrInvalidUnselectedGeometry() throws {
        let one = try WorkflowProfile(id:"range-source",revision:1,outputStockID:"stock",outputStock:stock,
            pageRules:[rule(page:1,disposition:.extract([region("A",0)]))])
        XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages:[page(),page()],profile:one,selectedSourcePages:[1])) {
            XCTAssertEqual($0 as? ExtractionPlanError,.unaccountedSourcePage(2))
        }
        let two = try WorkflowProfile(id:"range-full",revision:1,outputStockID:"stock",outputStock:stock,
            pageRules:[rule(page:1,disposition:.extract([region("A",0)])),
                       rule(page:2,disposition:.extract([region("B",1)]))])
        let wrong = try PDFPageBox(originX:0,originY:0,width:300,height:300)
        XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages:[page(),wrong],profile:two,selectedSourcePages:[1])) {
            XCTAssertEqual($0 as? ExtractionPlanError,.inputGeometryMismatch(page:2))
        }
        for selection in [Set<Int>(),[0],[3]] {
            XCTAssertThrowsError(try ExtractionPlanner.plan(sourcePages:[page(),page()],profile:two,selectedSourcePages:selection)) {
                XCTAssertEqual($0 as? ExtractionPlanError,.invalidPageSelection)
            }
        }
    }

    /// The v3 worker ticket carries margins only because the profile admitted
    /// them first. These are the emission-side gates: a non-zero margin on a
    /// v2 profile, and margins that leave no printable area, must fail closed
    /// with their own typed error rather than being clamped or defaulted.
    func testProfileRejectsMarginsOnVersionTwoAndMarginsLeavingNoPrintableArea() throws {
        func profile(schemaVersion: Int, margins: OutputMargins) throws -> WorkflowProfile {
            try WorkflowProfile(
                schemaVersion: schemaVersion, id: "margin-admission", revision: 1,
                outputStockID: "stock", outputStock: stock, outputMargins: margins,
                pageRules: [try rule(page: 1, disposition: .extract([try region("label", 0)]))]
            )
        }
        // A v2 profile has no margin field on the wire, so a non-zero margin
        // there would print an unrepresentable geometry.
        XCTAssertThrowsError(try profile(schemaVersion: 2,
            margins: OutputMargins(left: 1, top: 0, right: 0, bottom: 0))) {
            XCTAssertEqual($0 as? ExtractionPlanError, .invalidProfile)
        }
        // Margins that consume the whole stock leave nothing to image.
        let noWidth = try OutputMargins(left: stock.width.value / 2, top: 0,
            right: stock.width.value / 2, bottom: 0)
        let noHeight = try OutputMargins(left: 0, top: stock.height.value / 2,
            right: 0, bottom: stock.height.value / 2)
        for exhausting in [noWidth, noHeight] {
            XCTAssertThrowsError(try profile(schemaVersion: 3, margins: exhausting)) {
                XCTAssertEqual($0 as? ExtractionPlanError, .invalidProfile)
            }
        }
        // Non-finite and negative edges are refused before a profile sees them.
        for value in [Double.nan, .infinity, -.infinity, -1] {
            for index in 0..<4 {
                var edges = [0.0, 0, 0, 0]; edges[index] = value
                XCTAssertThrowsError(try OutputMargins(left: edges[0], top: edges[1],
                    right: edges[2], bottom: edges[3])) {
                    XCTAssertEqual($0 as? PagePlacementError, .invalidMargins)
                }
            }
        }
        // The admitted margin reaches the planned label, which is what the
        // worker ticket serializes; an accepted margin must not vanish.
        let admitted = try OutputMargins(left: 1, top: 2, right: 3, bottom: 0.5)
        let plan = try ExtractionPlanner.plan(sourcePages: [try page()],
            profile: try profile(schemaVersion: 3, margins: admitted))
        XCTAssertEqual(plan.outputLabels[0].outputMargins, admitted)
    }
}
