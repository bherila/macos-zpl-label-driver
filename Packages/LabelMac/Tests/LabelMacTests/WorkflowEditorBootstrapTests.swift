import CoreGraphics
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class WorkflowEditorBootstrapTests: XCTestCase {
    private enum TestError: Error { case unavailable }

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

    func testRealWorkerBootstrapMatchesAllThreeReferenceProfiles() async throws {
        for name in ["native-vector", "letter-one", "a4-one"] {
            let source = try fixture(name)
            let profileStore = try store()
            let expected = try WorkflowEditorBootstrap.makeModel(originalPDF: source, store: profileStore)
            let actual = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), deadlineSeconds: 5)
            XCTAssertEqual(actual.profile, expected.profile)
            XCTAssertFalse(actual.isSaved)
        }
    }

    func testWorkerBootstrapRetainsPageLimitAndCancellation() async throws {
        let source = try fixture("native-vector")
        let profileStore = try store()
        let cancellation = OfflineRenderWorkerCancellation()
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(
                originalPDF: fixture("mixed-pages"), store: profileStore,
                workerExecutable: worker(), maximumPages: 1, deadlineSeconds: 5)
            XCTFail("oversized page count succeeded")
        } catch {
            XCTAssertEqual(error as? OfflineRenderWorkerProcess.Error, .jobRejected(code: .limitExceeded))
        }
        cancellation.cancel()
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), cancellation: cancellation)
            XCTFail("pre-cancelled bootstrap succeeded")
        } catch {
            XCTAssertEqual(error as? OfflineRenderWorkerProcess.Error, .cancelled)
        }
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), maximumPages: 33)
            XCTFail("raised editor page cap succeeded")
        } catch {
            XCTAssertEqual(error as? QuartzStructuralAnalyzer.Error, .invalidLimits)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appending(path: "Fixtures/generated/\(name).pdf"))
    }

    private func store() throws -> WorkflowProfileStore {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "WorkflowEditorBootstrapTests-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try WorkflowProfileStore(root: root)
    }

    private func borderlessNativePDF() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw TestError.unavailable
        }
        var box = CGRect(x: 0, y: 0, width: 288, height: 432)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw TestError.unavailable
        }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 120, y: 210, width: 48, height: 12))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    func testLetterFixtureCreatesUnsavedEditableProfileAndExactPreview() throws {
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("letter-one"), store: try store()
        )
        XCTAssertEqual(model.profile.id, "letter-to-4x6-local")
        XCTAssertEqual(model.profile.revision, 1)
        XCTAssertEqual(model.regions.count, 1)
        XCTAssertFalse(model.isSaved)
        XCTAssertEqual(model.regions[0].normalizedRect.x, 46.0 / 612.0, accuracy: 0.01)
        XCTAssertEqual(model.regions[0].normalizedRect.y, 190.0 / 792.0, accuracy: 0.01)
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.previewPBM, model.preview?.bitmap.pbmData())
    }

    func testA4FixtureUsesA4ReferenceWithoutChangingPhysicalStock() throws {
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("a4-one"), store: try store()
        )
        XCTAssertEqual(model.profile.id, "a4-to-4x6-local")
        XCTAssertEqual(model.profile.outputStock.width.value, 101.6, accuracy: 0.001)
        XCTAssertEqual(model.profile.outputStock.height.value, 152.4, accuracy: 0.001)
        XCTAssertEqual(model.regions.count, 1)
    }

    func testAmbiguousLandscapeSheetRequiresReviewInsteadOfChoosingOneLabel() throws {
        XCTAssertThrowsError(try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("ambiguous-region"), store: try store()
        )) {
            XCTAssertEqual(
                $0 as? WorkflowEditorBootstrap.Error,
                .ambiguousBorderCandidates(page: 1)
            )
        }
    }

    func testMixedGeometryAndUnexpectedPageCannotBeSilentlyDiscarded() throws {
        for name in ["mixed-pages", "non-label-pages"] {
            XCTAssertThrowsError(try WorkflowEditorBootstrap.makeModel(
                originalPDF: fixture(name), store: try store()
            )) {
                XCTAssertEqual($0 as? WorkflowEditorBootstrap.Error, .mixedReferenceGeometry)
            }
        }
    }

    func testSourcePageLimitIsAppliedBeforeCreatingDraft() throws {
        XCTAssertThrowsError(try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("mixed-pages"), store: try store(), maximumPages: 1
        )) {
            XCTAssertEqual(
                $0 as? QuartzPDFRenderer.Error,
                .sourcePageLimitExceeded(actual: 2, limit: 1)
            )
        }
    }

    func testNativeFixtureStillRequiresExplicitSaveAndApproval() throws {
        let store = try store()
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("native-vector"), store: store
        )
        XCTAssertEqual(model.profile.id, "native-4x6-local")
        XCTAssertEqual(model.regions.first?.normalizedRect, try NormalizedRect(
            x: 0, y: 0, width: 1, height: 1
        ))
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(try? store.qualification(for: model.profile))
    }

    func testNativePageDoesNotRequireAnArtificialBorder() throws {
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: borderlessNativePDF(), store: try store()
        )
        XCTAssertEqual(model.profile.id, "native-4x6-local")
        XCTAssertEqual(model.profile.pageRules.first?.structuralAnchors, [])
        XCTAssertEqual(model.regions.first?.normalizedRect, try NormalizedRect(
            x: 0, y: 0, width: 1, height: 1
        ))
    }
}
