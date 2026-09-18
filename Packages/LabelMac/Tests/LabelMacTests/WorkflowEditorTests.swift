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

    private func worker() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let url = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        return try XCTUnwrap(FileManager.default.isExecutableFile(atPath: url.path) ? url : nil)
    }

    func testWorkerPreviewMatchesExactOriginalPackedOutput() async throws {
        let (model, _) = try makeModel()
        try model.refreshPreview()
        let expected = try XCTUnwrap(model.preview)
        await model.refreshPreviewInWorker(workerExecutable: try worker(), deadlineSeconds: 5)
        XCTAssertEqual(model.preview, expected)
        XCTAssertEqual(model.preview?.previewPBM, expected.bitmap.pbmData())
        XCTAssertFalse(model.isPreparingPreview)
        XCTAssertNil(model.lastError)
    }

    func testEditsCancelObsoletePreviewWithoutInstallingItsResultOrError() async throws {
        let (model, _) = try makeModel()
        let task = Task { await model.refreshPreviewInWorker(
            workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"), deadlineSeconds: 5) }
        let limit = ContinuousClock.now.advanced(by: .seconds(1))
        while !model.isPreparingPreview && ContinuousClock.now < limit { await Task.yield() }
        XCTAssertTrue(model.isPreparingPreview)
        try model.setSelectedRotation(.degrees90)
        await task.value
        XCTAssertNil(model.preview)
        XCTAssertNil(model.lastError)
        XCTAssertFalse(model.isPreparingPreview)
        await model.refreshPreviewInWorker(workerExecutable: try worker(), deadlineSeconds: 5)
        XCTAssertNotNil(model.preview)
        XCTAssertNil(model.lastError)
    }

    func testSelectionAndTaskCancellationRejectPendingPreview() async throws {
        let (model, _) = try makeModel()
        for cancelTask in [false, true] {
            model.selectedRegionID = "selected"
            let task = Task { await model.refreshPreviewInWorker(
                workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"), deadlineSeconds: 5) }
            let limit = ContinuousClock.now.advanced(by: .seconds(1))
            while !model.isPreparingPreview && ContinuousClock.now < limit { await Task.yield() }
            XCTAssertTrue(model.isPreparingPreview)
            if cancelTask { task.cancel() } else { model.selectedRegionID = nil }
            await task.value
            XCTAssertNil(model.preview)
            XCTAssertNil(model.lastError)
            XCTAssertFalse(model.isPreparingPreview)
        }
    }

    func testUnavailableWorkerFailsWithoutInProcessFallback() async throws {
        let (model, _) = try makeModel()
        await model.refreshPreviewInWorker(workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"))
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.lastError, "Preview could not be prepared.")
        XCTAssertFalse(model.isPreparingPreview)
    }

    private actor PreviewBarrier {
        var arrived = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            arrived = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    func testCompletedObsoleteWorkerCannotReplaceNewerPreview() async throws {
        let (model, _) = try makeModel()
        let executable = try worker()
        let barrier = PreviewBarrier()
        let obsolete = Task {
            await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5,
                afterPreparation: { await barrier.pause() })
        }
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await barrier.arrived) && ContinuousClock.now < limit { await Task.yield() }
        let arrived = await barrier.arrived
        XCTAssertTrue(arrived)
        XCTAssertNoThrow(try model.setSelectedRotation(.degrees90))
        await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5)
        let current = model.preview
        await barrier.release()
        await obsolete.value
        XCTAssertNotNil(current)
        XCTAssertEqual(model.preview, current)
        XCTAssertFalse(model.isPreparingPreview)
        XCTAssertNil(model.lastError)
    }
}
