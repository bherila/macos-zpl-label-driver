import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class WorkflowSourcePagePreviewTests: XCTestCase {
    @MainActor
    private func editor() async throws -> WorkflowEditorModel {
        let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/letter-one.pdf"))
        let path = FileManager.default.temporaryDirectory.appending(path: "SourceEditorTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: WorkflowProfileStore(root: path), workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
    }

    @MainActor
    func testConnectedSourceReferenceCannotReplaceExactOriginalExtraction() async throws {
        let model = try await editor()
        await model.refreshSourcePageInWorker(workerExecutable: try worker(), deadlineSeconds: 5)
        let reference = try XCTUnwrap(model.sourcePreview)
        XCTAssertNil(model.preview)
        XCTAssertEqual(reference.canvas.physicalSize.width.value, 215.9, accuracy: 0.001)
        try model.setSelectedRegionMillimeters(left: 20, top: 20, width: 101.6, height: 152.4)
        await model.refreshPreviewInWorker(workerExecutable: try worker(), deadlineSeconds: 5)
        let workerOutput = try XCTUnwrap(model.preview)
        XCTAssertEqual(model.sourcePreview, reference)
        XCTAssertNotEqual(reference.bitmap.layout, workerOutput.bitmap.layout)
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.bitmap, workerOutput.bitmap)
    }

    private actor Barrier {
        var arrived = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            arrived = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    @MainActor
    func testCompletedSourceResultCannotSurviveChangedSelection() async throws {
        let model = try await editor()
        let barrier = Barrier()
        let executable = try worker()
        let task = Task {
            await model.refreshSourcePageInWorker(workerExecutable: executable, deadlineSeconds: 5,
                afterPreparation: { await barrier.pause() })
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await barrier.arrived) && ContinuousClock.now < deadline { await Task.yield() }
        let arrived = await barrier.arrived
        XCTAssertTrue(arrived)
        model.select("no-longer-selected")
        await barrier.release()
        await task.value
        XCTAssertNil(model.sourcePreview)
        XCTAssertNil(model.sourcePreviewError)
        XCTAssertFalse(model.isPreparingSourcePreview)
    }

    private var root: URL {
        var value = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { value.deleteLastPathComponent() }
        return value
    }

    private func worker() throws -> URL {
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let url = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        return try XCTUnwrap(FileManager.default.isExecutableFile(atPath: url.path) ? url : nil)
    }

    func testRealWorkerSourceReferenceMatchesWholeOriginalPageWithinCeiling() throws {
        for name in ["native-vector", "letter-one", "a4-one", "ambiguous-region"] {
            let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/\(name).pdf"))
            let box = try QuartzPDFRenderer.pageBox(originalPDF: source, pageNumber: 1)
            let result = try WorkflowSourcePagePreview.render(originalPDF: source, sourcePage: 1,
                pageBox: box, workerExecutable: worker(), maximumDimension: 320, deadlineSeconds: 5)
            XCTAssertEqual(result.sourcePage, 1)
            XCTAssertEqual(max(result.bitmap.layout.width, result.bitmap.layout.height), 320)
            XCTAssertLessThanOrEqual(result.bitmap.bytes.count, 180_000)
            XCTAssertEqual(result.canvas.physicalSize, try box.effectivePhysicalSize())
            let grayscale = try QuartzPDFRenderer.render(.init(originalPDF: source,
                pageNumber: 1, canvas: result.canvas))
            let expected = try MonochromeConversion.photographicOrderedDither4x4.convert(
                width: grayscale.width, height: grayscale.height,
                grayscale: grayscale.pixels, stride: grayscale.bytesPerRow)
            XCTAssertEqual(result.bitmap, expected)
        }
    }

    func testReferenceRejectsRaisedLimitsAndUnavailableWorkerWithoutFallback() throws {
        let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/letter-one.pdf"))
        let box = try QuartzPDFRenderer.pageBox(originalPDF: source, pageNumber: 1)
        for dimension in [0, 63, 1_201, Int.max] {
            XCTAssertThrowsError(try WorkflowSourcePagePreview.render(originalPDF: source, sourcePage: 1,
                pageBox: box, workerExecutable: worker(), maximumDimension: dimension)) {
                XCTAssertEqual($0 as? WorkflowSourcePagePreview.Error, .invalidLimit)
            }
        }
        XCTAssertThrowsError(try WorkflowSourcePagePreview.render(originalPDF: source, sourcePage: 1,
            pageBox: box, workerExecutable: URL(fileURLWithPath: "/nonexistent-source-worker"))) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .workerUnavailable)
        }
    }
}
