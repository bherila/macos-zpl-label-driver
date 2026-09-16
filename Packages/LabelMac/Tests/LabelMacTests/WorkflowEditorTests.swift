import CoreGraphics
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class WorkflowEditorTests: XCTestCase {
    private enum TestError: Error { case unavailable }

    private func pdf() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw TestError.unavailable }
        var box = CGRect(x: 0, y: 0, width: 20, height: 10)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw TestError.unavailable }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func makeModel() throws -> (WorkflowEditorModel, WorkflowProfileStore) {
        let source = try PDFPageBox(originX: 0, originY: 0, width: 20, height: 10)
        let sourceSize = try source.effectivePhysicalSize()
        let stock = PhysicalSize(
            width: try Millimeters(10 * 25.4 / 72),
            height: try Millimeters(10 * 25.4 / 72)
        )
        let selected = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let anchor = try NormalizedRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
        let profile = try WorkflowProfile(
            id: "editor-fixture", revision: 1,
            outputStockID: "test-stock", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: sourceSize),
                disposition: .extract([try ExtractionRegion(
                    id: "selected", normalizedRect: selected, outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "layout", kind: .border, normalizedRect: anchor
                )]
            )]
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "WorkflowEditorTests-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try WorkflowProfileStore(root: root)
        let canvas = try DotCanvas(
            physicalSize: stock,
            resolution: DotResolution(
                xDotsPerMillimeter: 72 / 25.4,
                yDotsPerMillimeter: 72 / 25.4
            )
        )
        return (WorkflowEditorModel(
            draft: try WorkflowProfileDraft(nextRevisionOf: profile),
            originalPDF: try pdf(),
            analyzedPages: [try AnalyzedSourcePage(
                pageBox: source,
                anchors: [.init(kind: .border, normalizedRect: anchor)]
            )],
            canvas: canvas,
            store: store
        ), store)
    }

    func testPreviewUsesExactPackedOutputAndMillimeterCorrection() throws {
        let (model, _) = try makeModel()
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.bitmap.bytes, Array(repeating: [0xFF, 0xC0], count: 10).flatMap { $0 })
        XCTAssertEqual(model.preview?.previewPBM, model.preview?.bitmap.pbmData())

        let pageWidth = model.profile.pageRules[0].expectedInput.uprightPhysicalSize.width.value
        let pageHeight = model.profile.pageRules[0].expectedInput.uprightPhysicalSize.height.value
        try model.setSelectedRegionMillimeters(
            left: pageWidth / 2, top: 0, width: pageWidth / 2, height: pageHeight
        )
        XCTAssertNil(model.preview)
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.bitmap.bytes, Array(repeating: [0x00, 0x00], count: 10).flatMap { $0 })
    }

    func testSaveApprovalReloadAndCorrectionUseDistinctRevisions() throws {
        let (model, store) = try makeModel()
        XCTAssertEqual(model.profile.revision, 2)
        XCTAssertFalse(model.isSaved)
        try model.save()
        XCTAssertTrue(model.isSaved)
        XCTAssertNil(try store.qualification(for: model.profile))
        try model.approveForUnattendedUse()
        XCTAssertNotNil(try store.qualification(for: model.profile))

        try model.reloadForCorrection(profileID: model.profile.id, revision: 2)
        XCTAssertEqual(model.profile.revision, 3)
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(model.preview)
        XCTAssertNil(try? store.qualification(for: model.profile))
    }

    func testInvalidMillimeterEditLeavesDraftAndPreviewUnchanged() throws {
        let (model, _) = try makeModel()
        try model.refreshPreview()
        let before = model.draft
        let preview = model.preview
        XCTAssertThrowsError(try model.setSelectedRegionMillimeters(
            left: -1, top: 0, width: 1, height: 1
        ))
        XCTAssertEqual(model.draft, before)
        XCTAssertEqual(model.preview, preview)
    }

    func testNativeViewCanBeConstructedFromModel() throws {
        let (model, _) = try makeModel()
        _ = WorkflowEditorView(model: model)
    }
}
