import Foundation
import XCTest
@testable import LabelMac

@MainActor
final class WorkflowDocumentOpeningModelTests: XCTestCase {
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
