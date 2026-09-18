import CoreGraphics
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class WorkflowEditorBootstrapTests: XCTestCase {
    private enum TestError: Error { case unavailable }

    func testDistinctManualWorkflowsCanBeSavedInTheSameImmutableStore() async throws {
        let profileStore = try store()
        let first = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: fixture("letter-one"),
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let second = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: fixture("a4-one"),
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        XCTAssertNotEqual(first.profile.id, second.profile.id)
        XCTAssertEqual(first.profile.revision, 1)
        XCTAssertEqual(second.profile.revision, 1)
        try first.setSelectedRegionMillimeters(left: 20, top: 20, width: 101.6, height: 152.4)
        try second.setSelectedRegionMillimeters(left: 10, top: 30, width: 101.6, height: 152.4)
        try first.save()
        try first.save() // Identical save remains idempotent.
        try second.save()
        XCTAssertEqual(try profileStore.load(profileID: first.profile.id, revision: 1), first.profile)
        XCTAssertEqual(try profileStore.load(profileID: second.profile.id, revision: 1), second.profile)
        XCTAssertThrowsError(try first.approveForUnattendedUse())
        XCTAssertThrowsError(try second.approveForUnattendedUse())
    }

    func testExplicitManualBorderlessLetterRemainsUnqualifiedAndRendersOriginal() async throws {
        let source = try borderlessNativePDF(width: 612, height: 792)
        let profileStore = try store()
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), deadlineSeconds: 5)
            XCTFail("assisted opening guessed a borderless crop")
        } catch {
            XCTAssertEqual(error as? WorkflowEditorBootstrap.Error, .noBorderCandidate(page: 1))
        }
        let manual = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        XCTAssertTrue(manual.isManualDraft)
        XCTAssertFalse(manual.isSaved)
        XCTAssertEqual(manual.regions.first?.normalizedRect,
            try NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(manual.profile.outputStock.width.value, 101.6, accuracy: 0.001)
        XCTAssertEqual(manual.profile.pageRules[0].expectedInput.uprightPhysicalSize.width.value, 215.9, accuracy: 0.001)
        XCTAssertTrue(manual.profile.pageRules.allSatisfy { $0.structuralAnchors.isEmpty })
        try manual.setSelectedRegionMillimeters(left: 20, top: 20, width: 101.6, height: 152.4)
        await manual.refreshPreviewInWorker(workerExecutable: try worker())
        let preview = try XCTUnwrap(manual.preview)
        XCTAssertEqual(preview.previewPBM, preview.bitmap.pbmData())
        try manual.save()
        let reloaded = try profileStore.load(profileID: manual.profile.id, revision: manual.profile.revision)
        XCTAssertEqual(reloaded, manual.profile, "Edited profile must survive exact persistence round trip")
        XCTAssertThrowsError(try manual.approveForUnattendedUse()) {
            XCTAssertEqual($0 as? UnattendedWorkflowQualification.Error, .missingStructuralChecks(page: 1),
                           "Unexpected qualification rejection: \($0)")
        }
        XCTAssertNil(try? profileStore.qualification(for: manual.profile))
    }

    func testManualAmbiguousAndMixedPagesNeverGuessOrDiscard() async throws {
        for name in ["ambiguous-region", "mixed-pages", "non-label-pages"] {
            let source = try fixture(name)
            let manual = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: store(), workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
            let count = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source).count
            XCTAssertEqual(manual.profile.pageRules.map(\.sourcePage), Array(1...count))
            XCTAssertEqual(manual.regions.count, count)
            XCTAssertTrue(manual.profile.pageRules.allSatisfy { $0.structuralAnchors.isEmpty })
            XCTAssertTrue(manual.regions.allSatisfy {
                $0.normalizedRect.x == 0 && $0.normalizedRect.y == 0 &&
                $0.normalizedRect.width == 1 && $0.normalizedRect.height == 1
            })
        }
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

    private func borderlessNativePDF(width: Double = 288, height: Double = 432) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw TestError.unavailable
        }
        var box = CGRect(x: 0, y: 0, width: width, height: height)
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
