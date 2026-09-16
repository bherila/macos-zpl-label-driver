import CryptoKit
import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class SyntheticInertJobPipelineTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let workflows: WorkflowProfileStore
        let printers: PrinterProfileStore
        let queues: VirtualQueueStore
        let active: ActiveVirtualQueueStore
        let jobs: AcceptedJobStore
        let pipeline: SyntheticInertJobPipeline
    }

    func testDescriptorBoundPDFIsAcceptedPreparedAndInertlyDelivered() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let submittedPath = fixture.root.appending(path: "scheduler-input.pdf")
        try original.write(to: submittedPath, options: .withoutOverwriting)
        let descriptor = open(
            submittedPath.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let moved = fixture.root.appending(path: "opened-source.pdf")
        try FileManager.default.moveItem(at: submittedPath, to: moved)
        try Data("not the opened PDF".utf8).write(
            to: submittedPath, options: .withoutOverwriting
        )

        let result = try fixture.pipeline.run(
            queueID: "shipping-native",
            sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-intake-1",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(maximumChunkBytes: 4_096)
        )
        XCTAssertEqual(result.acceptanceID, "synthetic-intake-1")
        XCTAssertEqual(result.outputLabelCount, 1)
        XCTAssertGreaterThan(result.preparedByteCount, 0)
        XCTAssertEqual(
            result.delivery, .transmitted(byteCount: result.preparedByteCount)
        )

        let bundle = try fixture.jobs.load(
            acceptanceID: result.acceptanceID,
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        XCTAssertEqual(bundle.sourcePDF, original)
        XCTAssertEqual(bundle.ticket.sourceDocumentSHA256, digest(original))
        XCTAssertEqual(bundle.ticket.copyOwnership, .upstreamAlreadyExpanded)
        XCTAssertEqual(bundle.ticket.pageRangeOwnership, .upstreamAlreadyApplied)
        XCTAssertEqual(bundle.ticket.intakeProvenance, .cupsScheduler)

        let stored = try AcceptedJobStateStore(
            acceptedJobStore: fixture.jobs
        ).loadPrepared(
            acceptanceID: result.acceptanceID,
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        XCTAssertEqual(stored.bytes.count, result.preparedByteCount)
        XCTAssertTrue(stored.bytes.starts(with: Data("^XA\n".utf8)))
        guard case .transmitted = stored.state.phase else {
            return XCTFail("expected persisted transmitted state")
        }
    }

    func testUnexpectedPageIsRejectedBeforeAcceptedBundlePublication() throws {
        let native = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let extraPages = try Data(contentsOf: fixtureURL("copy-order.pdf"))
        XCTAssertGreaterThan(
            try QuartzPDFRenderer.documentPageBoxes(originalPDF: extraPages).count, 1
        )
        let fixture = try makeFixture(workflowSource: native)
        let path = fixture.root.appending(path: "unexpected-pages.pdf")
        try extraPages.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native",
            sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-unexpected-pages",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .layoutRejected)
        }
        XCTAssertThrowsError(try fixture.jobs.load(
            acceptanceID: "synthetic-unexpected-pages",
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        ))
    }

    private func makeFixture(workflowSource: Data) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SyntheticInertJobPipeline-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let workflows = try WorkflowProfileStore(root: root)
        let printers = try PrinterProfileStore(root: root)
        let queues = try VirtualQueueStore(root: root)
        let active = try ActiveVirtualQueueStore(root: root)
        let jobs = try AcceptedJobStore(root: root)

        let box = try XCTUnwrap(
            QuartzPDFRenderer.documentPageBoxes(originalPDF: workflowSource).first
        )
        let analyzed = try QuartzStructuralAnalyzer.analyzeBorders(
            originalPDF: workflowSource, pageNumber: 1
        )
        let observed = try XCTUnwrap(analyzed.anchors?.first)
        let stock = PhysicalSize(
            width: try Millimeters.inches(4),
            height: try Millimeters.inches(6)
        )
        let workflow = try WorkflowProfile(
            id: "native-4x6-local", revision: 1,
            outputStockID: "nominal-4x6", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(
                    uprightPhysicalSize: try box.effectivePhysicalSize()
                ),
                disposition: .extract([try ExtractionRegion(
                    id: "full-page",
                    normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                    outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "observed-border",
                    kind: observed.kind,
                    normalizedRect: observed.normalizedRect
                )]
            )]
        )
        try workflows.save(workflow)
        try workflows.confirmForUnattendedUse(workflow)
        let workflowReference = try ImmutableProfileReference(
            id: workflow.id, schemaVersion: workflow.schemaVersion,
            revision: workflow.revision,
            sha256: digest(try WorkflowProfileJSON.encode(workflow))
        )
        let printer = try PrinterProfile.gc420dUSBReference(revision: 1)
        let printerReference = try printers.save(id: "gc420d-usb", profile: printer)
        let queue = try VirtualQueueDefinition(
            id: "shipping-native", revision: 1,
            displayName: "Synthetic native labels",
            physicalDevice: try PhysicalDeviceCoordinationID(
                sha256: String(repeating: "d", count: 64)
            ),
            workflowProfile: workflowReference,
            printerProfile: printerReference,
            workflowDefaults: PrinterControlRequest(
                thermalMethod: .directThermal,
                finishing: .tearOff,
                printSpeedIps: 3
            ),
            validatingAgainst: printer
        )
        let queueReference = try queues.save(
            queue, workflowStore: workflows, printerStore: printers
        )
        _ = try active.compareAndSwap(
            queue: queueReference, expected: nil,
            queueStore: queues, workflowStore: workflows,
            printerStore: printers
        )
        let leases = root.appending(path: "device-leases")
        try FileManager.default.createDirectory(
            at: leases, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return Fixture(
            root: root, workflows: workflows, printers: printers,
            queues: queues, active: active, jobs: jobs,
            pipeline: SyntheticInertJobPipeline(
                activeQueueStore: active,
                queueStore: queues,
                workflowStore: workflows,
                printerStore: printers,
                acceptedJobStore: jobs,
                leaseDirectory: leases
            )
        )
    }

    private func fixtureURL(_ name: String) -> URL {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appending(path: "Fixtures/generated/\(name)")
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
