import CryptoKit
import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class VirtualQueueStoreTests: XCTestCase {
    private let deviceDigest = String(repeating: "c", count: 64)

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "VirtualQueueStore-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func workflow(revision: Int = 1) throws -> WorkflowProfile {
        let page = try PDFPageBox(originX: 0, originY: 0, width: 288, height: 432)
        let region = try NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        return try WorkflowProfile(
            id: "native-4x6-local", revision: revision,
            outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(
                width: try Millimeters.inches(4), height: try Millimeters.inches(6)
            ),
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: page.effectivePhysicalSize()),
                disposition: .extract([try ExtractionRegion(
                    id: "label", normalizedRect: region,
                    outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "border", kind: .border, normalizedRect: region
                )]
            )]
        )
    }

    private func workflowReference(_ workflow: WorkflowProfile) throws -> ImmutableProfileReference {
        let bytes = try WorkflowProfileJSON.encode(workflow)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return try ImmutableProfileReference(
            id: workflow.id, schemaVersion: workflow.schemaVersion,
            revision: workflow.revision, sha256: digest
        )
    }

    private func queue(
        workflow: WorkflowProfile,
        printerReference: ImmutableProfileReference,
        displayName: String = "Native labels",
        workflowDigest: String? = nil
    ) throws -> VirtualQueueDefinition {
        let printer = try PrinterProfile.gc420dUSBReference(revision: 7)
        let reference = try workflowReference(workflow)
        return try VirtualQueueDefinition(
            id: "shipping-native", revision: 2, displayName: displayName,
            physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
            workflowProfile: ImmutableProfileReference(
                id: reference.id, revision: reference.revision,
                sha256: workflowDigest ?? reference.sha256
            ),
            printerProfile: printerReference,
            workflowDefaults: PrinterControlRequest(
                thermalMethod: .directThermal, finishing: .tearOff, printSpeedIps: 3
            ),
            validatingAgainst: printer
        )
    }

    private func qualifiedStores(
        root: URL
    ) throws -> (
        WorkflowProfileStore, PrinterProfileStore, VirtualQueueStore,
        WorkflowProfile, ImmutableProfileReference
    ) {
        let workflows = try WorkflowProfileStore(root: root)
        let printers = try PrinterProfileStore(root: root)
        let queues = try VirtualQueueStore(root: root)
        let value = try workflow()
        try workflows.save(value)
        try workflows.confirmForUnattendedUse(value)
        let printerReference = try printers.save(
            id: "gc420d-usb", profile: PrinterProfile.gc420dUSBReference(revision: 7)
        )
        return (workflows, printers, queues, value, printerReference)
    }

    func testImmutableQueueRoundTripRevalidatesExactQualifiedReferences() throws {
        let (workflows, printers, queues, value, printerReference) = try qualifiedStores(
            root: temporaryRoot()
        )
        let original = try queue(workflow: value, printerReference: printerReference)
        try queues.save(
            original, workflowStore: workflows, printerStore: printers
        )
        try queues.save(
            original, workflowStore: workflows, printerStore: printers
        )
        XCTAssertEqual(try queues.load(
            queueID: original.id, revision: original.revision,
            workflowStore: workflows, printerStore: printers
        ), original)
        XCTAssertFalse(VirtualQueueStore.fileName(original.id, original.revision).contains("/"))
    }

    func testUnqualifiedOrChangedWorkflowCannotBePublished() throws {
        let root = try temporaryRoot()
        let workflows = try WorkflowProfileStore(root: root)
        let printers = try PrinterProfileStore(root: root)
        let queues = try VirtualQueueStore(root: root)
        let value = try workflow()
        try workflows.save(value)
        let printer = try PrinterProfile.gc420dUSBReference(revision: 7)
        let printerReference = try printers.save(id: "gc420d-usb", profile: printer)
        XCTAssertThrowsError(try queues.save(
            queue(workflow: value, printerReference: printerReference),
            workflowStore: workflows, printerStore: printers
        )) { XCTAssertEqual($0 as? VirtualQueueStore.Error, .workflowNotQualified) }

        try workflows.confirmForUnattendedUse(value)
        XCTAssertThrowsError(try queues.save(
            queue(
                workflow: value, printerReference: printerReference,
                workflowDigest: String(repeating: "a", count: 64)
            ),
            workflowStore: workflows, printerStore: printers
        )) { XCTAssertEqual($0 as? VirtualQueueStore.Error, .workflowReferenceMismatch) }
    }

    func testPrinterDigestAndConflictingQueueBytesFailClosed() throws {
        let (workflows, printers, queues, value, printerReference) = try qualifiedStores(
            root: temporaryRoot()
        )
        let original = try queue(workflow: value, printerReference: printerReference)
        let wrongReference = try ImmutableProfileReference(
            id: printerReference.id, revision: printerReference.revision,
            sha256: String(repeating: "d", count: 64)
        )
        XCTAssertThrowsError(try queues.save(
            queue(workflow: value, printerReference: wrongReference),
            workflowStore: workflows, printerStore: printers
        )) { XCTAssertEqual($0 as? VirtualQueueStore.Error, .printerReferenceMismatch) }

        try queues.save(
            original, workflowStore: workflows,
            printerStore: printers
        )
        XCTAssertThrowsError(try queues.save(
            queue(workflow: value, printerReference: printerReference, displayName: "Changed"),
            workflowStore: workflows, printerStore: printers
        )) { XCTAssertEqual($0 as? VirtualQueueStore.Error, .queueConflict) }
    }

    func testTamperedIdentityAndUnsafeRootsAreRejected() throws {
        let root = try temporaryRoot()
        let (workflows, printers, queues, value, printerReference) = try qualifiedStores(root: root)
        let printer = try PrinterProfile.gc420dUSBReference(revision: 7)
        let original = try queue(workflow: value, printerReference: printerReference)
        try queues.save(
            original, workflowStore: workflows, printerStore: printers
        )
        let target = root.appending(path: "queues").appending(
            path: VirtualQueueStore.fileName(original.id, original.revision)
        )
        let changed = try VirtualQueueDefinition(
            id: "different", revision: original.revision, displayName: original.displayName,
            physicalDevice: original.physicalDevice,
            workflowProfile: original.workflowProfile,
            printerProfile: original.printerProfile,
            workflowDefaults: original.workflowDefaults,
            validatingAgainst: printer
        )
        try VirtualQueueJSON.encode(changed).write(to: target)
        XCTAssertThrowsError(try queues.load(
            queueID: original.id, revision: original.revision,
            workflowStore: workflows, printerStore: printers
        )) { XCTAssertEqual($0 as? VirtualQueueStore.Error, .queueIdentityMismatch) }

        let insecure = FileManager.default.temporaryDirectory.appending(
            path: "VirtualQueueStore-insecure-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: insecure) }
        try FileManager.default.createDirectory(at: insecure, withIntermediateDirectories: false)
        chmod(insecure.path, 0o755)
        XCTAssertThrowsError(try VirtualQueueStore(root: insecure)) {
            XCTAssertEqual($0 as? VirtualQueueStore.Error, .unsafeStoreDirectory)
        }
    }

    func testConcurrentConflictingWritersNeverReplaceWinner() async throws {
        let (workflows, printers, queues, value, printerReference) = try qualifiedStores(
            root: temporaryRoot()
        )
        let first = try queue(workflow: value, printerReference: printerReference)
        let second = try queue(
            workflow: value, printerReference: printerReference, displayName: "Alternate"
        )
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask {
                (try? queues.save(
                    first, workflowStore: workflows, printerStore: printers
                )) != nil
            }
            group.addTask {
                (try? queues.save(
                    second, workflowStore: workflows, printerStore: printers
                )) != nil
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let stored = try queues.load(
            queueID: first.id, revision: first.revision,
            workflowStore: workflows, printerStore: printers
        )
        XCTAssertTrue(stored == first || stored == second)
    }
}
