import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class WorkflowProfileTransferTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "WorkflowTransfer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func profile() throws -> WorkflowProfile {
        let reference = try ReferenceWorkflowDefinition.gc420dInitialSet()[1]
        let rect = try NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5)
        return try WorkflowProfile(id: "synthetic-transfer-source", revision: 7,
            outputStockID: reference.outputStockID, outputStock: reference.outputStock,
            monochromeConversion: .photographicOrderedDither4x4,
            pageRules: [WorkflowPageRule(sourcePage: 1, expectedInput: reference.expectedInput,
                disposition: .extract([ExtractionRegion(id: "label", normalizedRect: rect, outputOrder: 0)]),
                structuralAnchors: [StructuralAnchorExpectation(id: "layout", kind: .border, normalizedRect: rect)])])
    }

    func testImportUsesNewIdentityAndNeverCopiesLocalQualification() async throws {
        let root = try directory()
        let store = try WorkflowProfileStore(root: root.appending(path: "store"))
        let source = try profile()
        try store.save(source)
        try store.confirmForUnattendedUse(source)
        let file = root.appending(path: "profile.json")
        try WorkflowProfileJSON.encode(source).write(to: file)
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: URL(fileURLWithPath: "/nonexistent"))
        await model.importProfileDefinition(file)
        let first = try XCTUnwrap(model.savedWorkflows.first { $0.profile.id != source.id }?.profile)
        XCTAssertTrue(first.id.hasPrefix("import-"))
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(first.pageRules, source.pageRules)
        XCTAssertEqual(first.outputStockID, source.outputStockID)
        XCTAssertEqual(first.outputStock, source.outputStock)
        XCTAssertEqual(first.monochromeConversion, source.monochromeConversion)
        XCTAssertNil(try store.qualification(for: first))
        XCTAssertNotNil(try store.qualification(for: source))
        XCTAssertNil(model.editor)
        await model.importProfileDefinition(file)
        XCTAssertEqual(Set(model.savedWorkflows.map { $0.profile.id }).count, 3)
        XCTAssertFalse(model.isTransferringProfile)
    }

    func testExportIsExactDefinitionAndRejectsTamperedOrCrossStoreSnapshot() async throws {
        let root = try directory()
        let store = try WorkflowProfileStore(root: root.appending(path: "store"))
        let source = try profile()
        try store.save(source)
        try store.confirmForUnattendedUse(source)
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: URL(fileURLWithPath: "/nonexistent"))
        let document = await model.prepareProfileExport(source)
        XCTAssertEqual(document?.canonicalDefinition, try WorkflowProfileJSON.encode(source))
        XCTAssertEqual(try WorkflowProfileJSON.decode(XCTUnwrap(document?.canonicalDefinition)), source)
        let altered = try WorkflowProfile(id: source.id, revision: source.revision,
            outputStockID: "foreign-stock", outputStock: source.outputStock, pageRules: source.pageRules)
        let rejected = await model.prepareProfileExport(altered)
        XCTAssertNil(rejected)
        let other = WorkflowDocumentOpeningModel(store: try WorkflowProfileStore(root: root.appending(path: "other")),
            workerExecutable: URL(fileURLWithPath: "/nonexistent"))
        let missing = await other.prepareProfileExport(source)
        XCTAssertNil(missing)
        XCTAssertEqual(try store.load(profileID: source.id, revision: source.revision), source)
    }

    func testImportRejectsOversizeMalformedUnknownFieldsSymlinkAndDirectory() async throws {
        let root = try directory()
        let store = try WorkflowProfileStore(root: root.appending(path: "store"))
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: URL(fileURLWithPath: "/nonexistent"))
        let file = root.appending(path: "input.json")
        let valid = try WorkflowProfileJSON.encode(profile())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["qualification"] = true
        var unsupported = object
        unsupported.removeValue(forKey: "qualification")
        unsupported["schemaVersion"] = 99
        for bytes in [Data(repeating: 0x20, count: WorkflowProfileJSON.maximumBytes + 1),
                      Data("not-json".utf8), try JSONSerialization.data(withJSONObject: object),
                      try JSONSerialization.data(withJSONObject: unsupported)] {
            try bytes.write(to: file)
            await model.importProfileDefinition(file)
            XCTAssertEqual(try store.savedWorkflows(), [])
            XCTAssertNil(model.uncertainImportedProfile)
        }
        try valid.write(to: file)
        let link = root.appending(path: "link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        for url in [link, root, try XCTUnwrap(URL(string: "https://example.invalid/profile.json"))] {
            await model.importProfileDefinition(url)
            XCTAssertEqual(try store.savedWorkflows(), [])
        }
    }

    private final class SyncSwitch: @unchecked Sendable {
        let lock = NSLock()
        private var failing = true
        func recover() { lock.lock(); failing = false; lock.unlock() }
        func call(_ descriptor: Int32) -> Int32 {
            lock.lock(); let fail = failing; lock.unlock()
            if fail { errno = EIO; return -1 }
            return fsync(descriptor)
        }
    }

    func testCancelledImportBeforePublicationLeavesStoreEmpty() async throws {
        let root = try directory()
        let store = try WorkflowProfileStore(root: root.appending(path: "store"))
        let file = root.appending(path: "source.json")
        try WorkflowProfileJSON.encode(profile()).write(to: file)
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: URL(fileURLWithPath: "/nonexistent"))
        let task = Task { await model.importProfileDefinition(file) }
        task.cancel()
        await task.value
        XCTAssertEqual(try store.savedWorkflows(), [])
        XCTAssertEqual(model.profileTransferStatus, "Import cancelled before publication.")
        XCTAssertFalse(model.isTransferringProfile)
    }

    func testUncertainImportReconcilesSameCandidateWithoutCreatingDuplicates() async throws {
        let root = try directory()
        let sync = SyncSwitch()
        let storeRoot = root.appending(path: "store")
        let storage = try PrivateImmutableDirectory(root: storeRoot, syncDirectory: sync.call)
        let store = WorkflowProfileStore(root: storeRoot, storage: storage)
        let file = root.appending(path: "source.json")
        try WorkflowProfileJSON.encode(profile()).write(to: file)
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: URL(fileURLWithPath: "/nonexistent"))
        await model.importProfileDefinition(file)
        let candidate = try XCTUnwrap(model.uncertainImportedProfile)
        XCTAssertEqual(try store.savedWorkflows().map(\.profile), [candidate])
        await model.importProfileDefinition(file)
        await model.reconcileProfileImport()
        XCTAssertEqual(model.uncertainImportedProfile, candidate)
        XCTAssertEqual(try store.savedWorkflows().map(\.profile), [candidate])
        sync.recover()
        await model.reconcileProfileImport()
        XCTAssertNil(model.uncertainImportedProfile)
        XCTAssertEqual(model.savedWorkflows.map(\.profile), [candidate])
        XCTAssertNil(try store.qualification(for: candidate))
    }

    func testFullCatalogImportPreservesReadableCatalogAndShowsCapacityFailure() async throws {
        let root = try directory()
        let store = try WorkflowProfileStore(root: root.appending(path: "store"))
        let source = try profile()
        for index in 0..<256 {
            try store.save(WorkflowProfile(id: "synthetic-capacity-\(index)", revision: 1,
                outputStockID: source.outputStockID, outputStock: source.outputStock,
                monochromeConversion: source.monochromeConversion, pageRules: source.pageRules))
        }
        let model = WorkflowDocumentOpeningModel(store: store, workerExecutable: URL(fileURLWithPath: "/nonexistent"))
        await model.refreshSavedWorkflows()
        let previous = model.savedWorkflows
        let file = root.appending(path: "source.json")
        try WorkflowProfileJSON.encode(source).write(to: file)
        await model.importProfileDefinition(file)
        XCTAssertEqual(model.savedWorkflows, previous)
        XCTAssertEqual(try store.savedWorkflows().count, 256)
        XCTAssertNil(model.uncertainImportedProfile)
        XCTAssertNil(model.savedWorkflowError)
        XCTAssertTrue(model.profileTransferStatus?.contains("catalog is full") == true)
        XCTAssertFalse(model.isTransferringProfile)
    }
}
