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
        let physicalDevice: PhysicalDeviceCoordinationID
        let leaseDirectory: URL
        let queue: VirtualQueueDefinition
        let selection: ActiveVirtualQueueSelection
        let printer: PrinterProfile
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

    func testRetryableWaitingStateResumesThroughPipelineEntryPoint() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "retryable-waiting.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(failBeforeTransmission: true)
        )
        XCTAssertEqual(first.delivery, .failedBeforeTransmission)
        XCTAssertTrue(first.delivery.mayRetryAutomatically)
        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("wrong cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .acceptanceFailed)
        }
        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "different-queue", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .acceptanceFailed)
        }

        let laterQueue = try VirtualQueueDefinition(
            id: fixture.queue.id,
            revision: fixture.queue.revision + 1,
            displayName: fixture.queue.displayName,
            physicalDevice: fixture.queue.physicalDevice,
            workflowProfile: fixture.queue.workflowProfile,
            printerProfile: fixture.queue.printerProfile,
            workflowDefaults: fixture.queue.workflowDefaults,
            validatingAgainst: fixture.printer
        )
        let laterReference = try fixture.queues.save(
            laterQueue, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        _ = try fixture.active.compareAndSwap(
            queue: laterReference, expected: fixture.selection,
            queueStore: fixture.queues, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )

        let retry = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-waiting-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(
            retry.delivery, .transmitted(byteCount: first.preparedByteCount)
        )
        XCTAssertEqual(retry.preparedByteCount, first.preparedByteCount)
    }

    func testRetryableDeviceContentionResumesPreparedArtifact() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "retryable-contention.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        let held = try PhysicalDeviceLease(
            acquiring: PhysicalDeviceIdentity(coordinationID: fixture.physicalDevice),
            inExistingDirectory: fixture.leaseDirectory
        )

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-contention-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(first.delivery, .deviceBusy)
        XCTAssertTrue(first.delivery.mayRetryAutomatically)
        held.release()

        let retry = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-contention-retry",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(
            retry.delivery, .transmitted(byteCount: first.preparedByteCount)
        )
    }

    func testPreparedByteBudgetStopsMultiLabelJobWithoutPublishingPayload() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(
            workflowSource: original, regionCount: 2,
            maximumPreparedBytes: 400_000
        )
        let path = fixture.root.appending(path: "bounded-multi-label.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-bounded-payload",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .preparationFailed)
        }
        let state = try AcceptedJobStateStore(
            acceptedJobStore: fixture.jobs
        ).load(
            acceptanceID: "synthetic-bounded-payload",
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )
        XCTAssertEqual(state.phase, .accepted)
    }

    func testWorkflowStockMustMatchObservedLoadedFace() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(
            workflowSource: original, useMismatchedOutputStock: true
        )
        let path = fixture.root.appending(path: "stock-mismatch.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        XCTAssertThrowsError(try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-stock-mismatch",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )) {
            XCTAssertEqual(
                $0 as? SyntheticInertJobPipeline.Error, .configurationUnavailable
            )
        }
        XCTAssertThrowsError(try fixture.jobs.load(
            acceptanceID: "synthetic-stock-mismatch",
            queueStore: fixture.queues,
            workflowStore: fixture.workflows,
            printerStore: fixture.printers
        ))
    }

    func testPersistedUncertaintyIsReturnedWithoutReplayOnReentry() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "persisted-uncertainty.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-persisted-uncertain",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(
                maximumChunkBytes: 2, becomeAmbiguousAfterBytes: 3
            )
        )
        XCTAssertEqual(first.delivery, .uncertain(bytesAccepted: 3))
        let states = AcceptedJobStateStore(acceptedJobStore: fixture.jobs)
        let before = try states.load(
            acceptanceID: first.acceptanceID,
            queueStore: fixture.queues, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        )

        let recovered = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: first.acceptanceID,
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(recovered, first)
        XCTAssertEqual(try states.load(
            acceptanceID: first.acceptanceID,
            queueStore: fixture.queues, workflowStore: fixture.workflows,
            printerStore: fixture.printers
        ), before)
    }

    func testPersistedTransmissionIsReturnedWithoutSecondDelivery() throws {
        let original = try Data(contentsOf: fixtureURL("native-vector.pdf"))
        let fixture = try makeFixture(workflowSource: original)
        let path = fixture.root.appending(path: "persisted-transmission.pdf")
        try original.write(to: path, options: .withoutOverwriting)
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        let first = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: "synthetic-persisted-transmitted",
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario()
        )
        let recovered = try fixture.pipeline.run(
            queueID: "shipping-native", sourcePDFDescriptor: descriptor,
            acceptanceID: first.acceptanceID,
            cancellationToken: Data("synthetic cancellation capability".utf8),
            scenario: try InertDeliveryScenario(becomeAmbiguousAfterBytes: 0)
        )
        XCTAssertEqual(recovered, first)
    }

    private func makeFixture(
        workflowSource: Data,
        regionCount: Int = 1,
        maximumPreparedBytes: Int = PreparedJobPayload.maximumBytes,
        useMismatchedOutputStock: Bool = false
    ) throws -> Fixture {
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
        let stock = if useMismatchedOutputStock {
            PhysicalSize(
                width: try Millimeters.inches(2),
                height: try Millimeters.inches(3)
            )
        } else {
            PhysicalSize(
                width: try Millimeters.inches(4),
                height: try Millimeters.inches(6)
            )
        }
        let regions = try (0..<regionCount).map { index in
            try ExtractionRegion(
                id: "full-page-\(index)",
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                outputOrder: index
            )
        }
        let workflow = try WorkflowProfile(
            id: "native-4x6-local", revision: 1,
            outputStockID: "nominal-4x6", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(
                    uprightPhysicalSize: try box.effectivePhysicalSize()
                ),
                disposition: .extract(regions),
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
        let physicalDevice = try PhysicalDeviceCoordinationID(
            sha256: String(repeating: "d", count: 64)
        )
        let queue = try VirtualQueueDefinition(
            id: "shipping-native", revision: 1,
            displayName: "Synthetic native labels",
            physicalDevice: physicalDevice,
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
                leaseDirectory: leases,
                maximumPreparedBytes: maximumPreparedBytes
            ),
            physicalDevice: physicalDevice,
            leaseDirectory: leases,
            queue: queue,
            selection: try XCTUnwrap(try active.load(
                queueID: queue.id, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            )),
            printer: printer
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
