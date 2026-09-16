import Foundation
import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class WorkflowDocumentOpeningModelTests: XCTestCase {
    func testSavedManualWorkflowReopensAgainstOriginalAsNewUnqualifiedRevision() async throws {
        let store = try store()
        let creating = WorkflowDocumentOpeningModel(store: store, workerExecutable: try worker())
        creating.open(fixture("letter-one"), mode: .manual)
        await creating.currentOpeningTask?.value
        let original = try XCTUnwrap(creating.editor)
        try original.setSelectedRegionMillimeters(left: 20, top: 20, width: 101.6, height: 152.4)
        await original.refreshPreviewInWorker(workerExecutable: try worker())
        let expected = try XCTUnwrap(original.preview).bitmap
        try original.save()
        let saved = original.profile
        let reopening = WorkflowDocumentOpeningModel(store: store, workerExecutable: try worker())
        await reopening.refreshSavedWorkflows()
        XCTAssertEqual(reopening.savedWorkflows.map(\.profile), [saved])
        XCTAssertNil(reopening.savedWorkflowError)
        reopening.openSavedWorkflow(fixture("letter-one"), profile: saved)
        await reopening.currentOpeningTask?.value
        let corrected = try XCTUnwrap(reopening.editor)
        XCTAssertNil(reopening.error)
        XCTAssertTrue(corrected.isReopenedWorkflow)
        XCTAssertFalse(corrected.isSaved)
        XCTAssertEqual(corrected.profile.id, saved.id)
        XCTAssertEqual(corrected.profile.revision, saved.revision + 1)
        XCTAssertEqual(corrected.profile.pageRules, saved.pageRules)
        await corrected.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertEqual(corrected.preview?.bitmap, expected)
        XCTAssertEqual(corrected.preview?.previewPBM, expected.pbmData())
        try corrected.save()
        XCTAssertEqual(try store.load(profileID: saved.id, revision: saved.revision), saved)
        XCTAssertNil(try store.qualification(for: corrected.profile))
        XCTAssertThrowsError(try corrected.approveForUnattendedUse())
    }

    func testSavedWorkflowMismatchPreservesEditorAndPriorQualification() async throws {
        let store = try store()
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: try worker())
        model.open(fixture("letter-one"))
        await model.currentOpeningTask?.value
        let original = try XCTUnwrap(model.editor)
        try original.save()
        try original.approveForUnattendedUse()
        let saved = original.profile
        for source in ["a4-one", "layout-changed", "mixed-pages"] {
            model.openSavedWorkflow(fixture(source), profile: saved)
            await model.currentOpeningTask?.value
            XCTAssertTrue(model.editor === original, source)
            XCTAssertEqual(model.error,
                "This PDF does not match the saved workflow's pages or layout. The current draft was kept.", source)
            XCTAssertTrue(original.isSaved)
            XCTAssertNotNil(try store.qualification(for: saved))
        }
        model.openSavedWorkflow(fixture("letter-one"), profile: saved)
        await model.currentOpeningTask?.value
        let corrected = try XCTUnwrap(model.editor)
        XCTAssertEqual(corrected.profile.revision, saved.revision + 1)
        try corrected.save()
        XCTAssertNil(try store.qualification(for: corrected.profile))
        XCTAssertNotNil(try store.qualification(for: saved))
    }

    func testSavedWorkflowSnapshotMustMatchTheOpeningModelsOwnStore() async throws {
        let storeA = try store()
        let storeB = try store()
        let source = try Data(contentsOf: fixture("letter-one"))
        let first = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: storeA, workerExecutable: worker(), deadlineSeconds: 5)
        try first.save()
        let expected = first.profile
        var altered = WorkflowProfileDraft(profile: expected)
        guard case let .extract(regions) = expected.pageRules[0].disposition else {
            return XCTFail("expected extraction rule")
        }
        try altered.updateRegion(id: XCTUnwrap(regions.first).id,
            normalizedRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.5), rotation: .degrees0)
        try storeB.save(altered.profile)
        let model = WorkflowDocumentOpeningModel(store: storeB, workerExecutable: try worker())
        model.openSavedWorkflow(fixture("letter-one"), profile: expected)
        await model.currentOpeningTask?.value
        XCTAssertNil(model.editor)
        XCTAssertEqual(model.error,
            "The saved workflow changed or could not be verified. Refresh the saved workflow list.")
        XCTAssertEqual(try storeA.load(profileID: expected.id, revision: expected.revision), expected)
        XCTAssertEqual(try storeB.load(profileID: expected.id, revision: expected.revision), altered.profile)
    }

    func testSavedWorkflowCannotChangeTheConfirmedOutputStock() async throws {
        let store = try store()
        let manual = try await WorkflowEditorBootstrap.makeModelUsingWorker(
            originalPDF: Data(contentsOf: fixture("letter-one")),
            store: store, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let profile = manual.profile
        let other = try WorkflowProfile(id: profile.id, revision: profile.revision,
            outputStockID: "other-stock",
            outputStock: PhysicalSize(width: Millimeters(50), height: Millimeters(50)),
            pageRules: profile.pageRules)
        try store.save(other)
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: try worker())
        model.openSavedWorkflow(fixture("letter-one"), profile: other)
        await model.currentOpeningTask?.value
        XCTAssertNil(model.editor)
        XCTAssertEqual(model.error,
            "This saved workflow uses different output stock. The current setup is 4×6 tear-off.")
        XCTAssertEqual(try store.load(profileID: other.id, revision: other.revision), other)
    }

    func testMissingMalformedOrNoncanonicalSavedSnapshotKeepsCurrentEditor() async throws {
        let store = try store()
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: try worker())
        model.open(fixture("letter-one"), mode: .manual)
        await model.currentOpeningTask?.value
        let current = try XCTUnwrap(model.editor)
        try current.save()
        let saved = current.profile
        let path = store.root.appending(path: "profiles")
            .appending(path: WorkflowProfileStore.profileFileName(saved.id, saved.revision))
        var spaced = try WorkflowProfileJSON.encode(saved)
        spaced.append(0x20)
        for replacement in [spaced, Data("malformed".utf8), nil] as [Data?] {
            if let replacement { try replacement.write(to: path) }
            else { try FileManager.default.removeItem(at: path) }
            model.openSavedWorkflow(fixture("letter-one"), profile: saved)
            await model.currentOpeningTask?.value
            XCTAssertTrue(model.editor === current)
            XCTAssertTrue(current.isSaved)
            XCTAssertEqual(model.error,
                "The saved workflow changed or could not be verified. Refresh the saved workflow list.")
        }
    }

    func testManualOpeningIsAnExplicitChoiceNotFailureFallback() async throws {
        let model = WorkflowDocumentOpeningModel(store: try store(), workerExecutable: try worker())
        model.open(fixture("ambiguous-region"))
        await model.currentOpeningTask?.value
        XCTAssertNil(model.editor)
        XCTAssertNotNil(model.error)
        model.open(fixture("ambiguous-region"), mode: .manual)
        await model.currentOpeningTask?.value
        XCTAssertTrue(try XCTUnwrap(model.editor).isManualDraft)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isOpening)
    }

    private var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private func fixture(_ name: String) -> URL {
        root.appending(path: "Fixtures/generated/\(name).pdf")
    }

    private func store() throws -> WorkflowProfileStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "WorkflowOpeningTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try WorkflowProfileStore(root: url)
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

    func testRealOpeningPreservesPriorDraftOnFailureAndCancellation() async throws {
        let model = WorkflowDocumentOpeningModel(store: try store(), workerExecutable: try worker())
        model.open(fixture("native-vector"))
        await model.currentOpeningTask?.value
        let original = try XCTUnwrap(model.editor)
        XCTAssertEqual(original.profile.id, "native-4x6-local")
        XCTAssertFalse(original.isSaved)
        model.open(fixture("encrypted-input"))
        await model.currentOpeningTask?.value
        XCTAssertTrue(model.editor === original)
        XCTAssertEqual(model.error, "The PDF could not be opened.")
        model.open(fixture("letter-one"))
        let cancelled = model.currentOpeningTask
        model.cancelOpening()
        await cancelled?.value
        XCTAssertTrue(model.editor === original)
        XCTAssertFalse(model.isOpening)
        XCTAssertNil(model.error)
    }

    private actor Barrier {
        var arrived = false
        private var calls = 0
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pauseFirst() async {
            calls += 1
            guard calls == 1 else { return }
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

    func testCompletedObsoleteOpenCannotReplaceNewerEditor() async throws {
        let barrier = Barrier()
        let model = WorkflowDocumentOpeningModel(store: try store(), workerExecutable: try worker(),
            afterAnalysis: { await barrier.pauseFirst() })
        model.open(fixture("letter-one"))
        let obsolete = model.currentOpeningTask
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await barrier.arrived) && ContinuousClock.now < limit { await Task.yield() }
        let arrived = await barrier.arrived
        XCTAssertTrue(arrived)
        model.open(fixture("a4-one"))
        await model.currentOpeningTask?.value
        let current = model.editor
        XCTAssertEqual(current?.profile.id, "a4-to-4x6-local")
        await barrier.release()
        await obsolete?.value
        XCTAssertTrue(model.editor === current)
        XCTAssertFalse(model.isOpening)
        XCTAssertNil(model.error)
    }

    func testCompletedObsoleteSavedOpenCannotReplaceNewManualEditor() async throws {
        let store = try store()
        let saved = try await WorkflowEditorBootstrap.makeModelUsingWorker(
            originalPDF: Data(contentsOf: fixture("letter-one")),
            store: store, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        try saved.save()
        let barrier = Barrier()
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: try worker(),
            afterAnalysis: { await barrier.pauseFirst() })
        model.openSavedWorkflow(fixture("letter-one"), profile: saved.profile)
        let obsolete = model.currentOpeningTask
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await barrier.arrived) && ContinuousClock.now < limit { await Task.yield() }
        let arrived = await barrier.arrived
        XCTAssertTrue(arrived)
        model.open(fixture("a4-one"), mode: .manual)
        await model.currentOpeningTask?.value
        let current = try XCTUnwrap(model.editor)
        XCTAssertFalse(current.isReopenedWorkflow)
        XCTAssertNotEqual(current.profile.id, saved.profile.id)
        await barrier.release()
        await obsolete?.value
        XCTAssertTrue(model.editor === current)
        XCTAssertFalse(model.isOpening)
        XCTAssertNil(model.error)
    }

    func testUnavailableWorkerHasNoInProcessFallback() async throws {
        let model = WorkflowDocumentOpeningModel(store: try store(),
            workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"))
        model.open(fixture("native-vector"))
        await model.currentOpeningTask?.value
        XCTAssertNil(model.editor)
        XCTAssertFalse(model.isOpening)
        XCTAssertEqual(model.error, "The PDF could not be opened.")
    }
}
