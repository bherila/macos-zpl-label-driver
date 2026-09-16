import CryptoKit
import Darwin
import Dispatch
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class AcceptedJobStoreTests: XCTestCase {
    private final class ParentSyncGate: @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        func sync(_ descriptor: Int32) -> Int32 {
            entered.signal()
            release.wait()
            return fsync(descriptor)
        }
    }

    private struct Fixture {
        let root: URL
        let workflows: WorkflowProfileStore
        let printers: PrinterProfileStore
        let queues: VirtualQueueStore
        let active: ActiveVirtualQueueStore
        let jobs: AcceptedJobStore
        let printer: PrinterProfile
        let queue: VirtualQueueDefinition
        let selection: ActiveVirtualQueueSelection
        let sourcePDF: Data
        let cancellationToken: Data
        let ticket: ResolvedJobTicket
    }

    private func fixture(
        acceptanceID: String = "accepted-42",
        regionID: String = "label",
        cancellationToken: Data = Data("synthetic cancellation capability".utf8)
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AcceptedJobStore-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let workflows = try WorkflowProfileStore(root: root)
        let printers = try PrinterProfileStore(root: root)
        let queues = try VirtualQueueStore(root: root)
        let active = try ActiveVirtualQueueStore(root: root)
        let jobs = try AcceptedJobStore(root: root)

        let page = try PDFPageBox(originX: 0, originY: 0, width: 288, height: 432)
        let region = try NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        let workflow = try WorkflowProfile(
            id: "native-4x6-local", revision: 3, outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(
                width: try Millimeters.inches(4), height: try Millimeters.inches(6)
            ),
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: page.effectivePhysicalSize()),
                disposition: .extract([try ExtractionRegion(
                    id: regionID, normalizedRect: region, outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "border", kind: .border, normalizedRect: region
                )]
            )]
        )
        try workflows.save(workflow)
        try workflows.confirmForUnattendedUse(workflow)
        let workflowBytes = try WorkflowProfileJSON.encode(workflow)
        let workflowReference = try ImmutableProfileReference(
            id: workflow.id, schemaVersion: workflow.schemaVersion,
            revision: workflow.revision,
            sha256: Self.digest(workflowBytes)
        )

        let printer = try PrinterProfile.gc420dUSBReference(revision: 7)
        let printerReference = try printers.save(id: "gc420d-usb", profile: printer)
        let queue = try VirtualQueueDefinition(
            id: "shipping-native", revision: 2, displayName: "Native labels",
            physicalDevice: PhysicalDeviceCoordinationID(
                sha256: String(repeating: "d", count: 64)
            ),
            workflowProfile: workflowReference, printerProfile: printerReference,
            workflowDefaults: PrinterControlRequest(
                thermalMethod: .directThermal, finishing: .tearOff, printSpeedIps: 3
            ),
            validatingAgainst: printer
        )
        let queueReference = try queues.save(
            queue, workflowStore: workflows, printerStore: printers
        )
        let selection = try active.compareAndSwap(
            queue: queueReference, expected: nil, queueStore: queues,
            workflowStore: workflows, printerStore: printers
        )
        let plan = try ExtractionPlanner.plan(
            analyzedPages: [try AnalyzedSourcePage(
                pageBox: page,
                anchors: [ObservedPageAnchor(kind: .border, normalizedRect: region)]
            )], profile: workflow,
            copyPolicy: .engine(copies: 1, collated: true)
        )
        let sourcePDF = Data("%PDF-1.7\nsynthetic accepted source\n%%EOF\n".utf8)
        let ticket = try ResolvedJobTicket.accept(
            acceptanceID: acceptanceID,
            cancellationSHA256: Self.digest(cancellationToken),
            activeSelection: selection, queueReference: queueReference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: Self.digest(sourcePDF),
            sourceByteCount: sourcePDF.count, intakeProvenance: .cupsScheduler,
            plan: plan, copyOwnership: .engine(copies: 1, collated: true),
            pageRangeOwnership: .engine(selectedSourcePages: [1])
        )
        return Fixture(
            root: root, workflows: workflows, printers: printers,
            queues: queues, active: active, jobs: jobs, printer: printer,
            queue: queue, selection: selection, sourcePDF: sourcePDF,
            cancellationToken: cancellationToken, ticket: ticket
        )
    }

    private func preparedPayload(
        _ value: Fixture,
        seed: UInt8 = 0x80,
        outputs: [ResolvedOutputLabel]? = nil,
        profile: PrinterProfile? = nil,
        request: PrinterControlRequest? = nil,
        monochromeConversion: MonochromeConversion? = nil
    ) throws -> PreparedJobPayload {
        let outputs = outputs ?? value.ticket.outputLabels
        let profile = profile ?? value.printer
        let request = request ?? value.queue.workflowDefaults
        let encoder = try ZPLPreparedLabelEncoder()
        let labels = try outputs.enumerated().map { index, output in
            let byte = seed &+ UInt8(truncatingIfNeeded: index)
            let prepared = try encoder.prepare(
                bitmap: MonochromeBitmap(width: 8, height: 1, bytes: [byte]),
                profile: profile, job: request
            )
            return PreparedOutputLabel(output: output, prepared: prepared)
        }
        return try PreparedJobPayload(
            labels: labels, expectedOutputLabels: outputs,
            monochromeConversion: monochromeConversion ?? value.ticket.monochromeConversion
        )
    }

    func testImmutableRoundTripSurvivesActiveSelectionChange() throws {
        let value = try fixture()
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )

        let laterQueue = try VirtualQueueDefinition(
            id: value.queue.id, revision: value.queue.revision + 1,
            displayName: value.queue.displayName,
            physicalDevice: value.queue.physicalDevice,
            workflowProfile: value.queue.workflowProfile,
            printerProfile: value.queue.printerProfile,
            workflowDefaults: value.queue.workflowDefaults,
            validatingAgainst: value.printer
        )
        let laterReference = try value.queues.save(
            laterQueue, workflowStore: value.workflows, printerStore: value.printers
        )
        let laterSelection = try value.active.compareAndSwap(
            queue: laterReference, expected: value.selection, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )

        let loaded = try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(loaded.ticket, value.ticket)
        XCTAssertEqual(loaded.sourcePDF, value.sourcePDF)
        XCTAssertFalse(AcceptedJobStore.directoryName(value.ticket.acceptanceID).contains("accepted"))
        XCTAssertEqual(value.ticket.activeSelectionGeneration, 1)
        XCTAssertEqual(laterSelection.generation, 2)
        XCTAssertNotEqual(laterSelection.queue, value.ticket.queue)
    }

    func testLoadIfPresentDistinguishesAbsenceFromUnsafePresentBundle() throws {
        let value = try fixture(acceptanceID: "optional-load")
        XCTAssertNil(try value.jobs.loadIfPresent(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues,
            workflowStore: value.workflows,
            printerStore: value.printers
        ))

        let unsafe = value.root
            .appending(path: "accepted-jobs")
            .appending(path: AcceptedJobStore.directoryName(value.ticket.acceptanceID))
        try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: false)
        XCTAssertThrowsError(try value.jobs.loadIfPresent(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues,
            workflowStore: value.workflows,
            printerStore: value.printers
        )) {
            XCTAssertEqual($0 as? AcceptedJobStore.Error, .unsafeStoreDirectory)
        }
    }

    func testSameBytesAreIdempotentAndConflictingBytesFailClosed() throws {
        let first = try fixture()
        try first.jobs.save(
            first.ticket, sourcePDF: first.sourcePDF, queueStore: first.queues,
            workflowStore: first.workflows, printerStore: first.printers
        )
        try first.jobs.save(
            first.ticket, sourcePDF: first.sourcePDF, queueStore: first.queues,
            workflowStore: first.workflows, printerStore: first.printers
        )

        let bytes = try ResolvedJobTicketJSON.encode(first.ticket)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["source"] = try XCTUnwrap(object["source"] as? [String: Any]).merging(
            ["byteCount": 4_097], uniquingKeysWith: { _, new in new }
        )
        let target = first.root.appending(path: "accepted-jobs").appending(
            path: AcceptedJobStore.directoryName(first.ticket.acceptanceID)
        ).appending(path: "ticket.json")
        try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        ).write(to: target)
        XCTAssertThrowsError(try first.jobs.save(
            first.ticket, sourcePDF: first.sourcePDF, queueStore: first.queues,
            workflowStore: first.workflows, printerStore: first.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .jobConflict) }
    }

    func testTamperedIdentityNoncanonicalBytesAndMissingReferencesAreRejected() throws {
        let value = try fixture()
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let target = value.root.appending(path: "accepted-jobs").appending(
            path: AcceptedJobStore.directoryName(value.ticket.acceptanceID)
        ).appending(path: "ticket.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any]
        )
        object["acceptanceID"] = "accepted-elsewhere"
        try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        ).write(to: target)
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .jobIdentityMismatch) }

        object["acceptanceID"] = value.ticket.acceptanceID
        let canonical = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        try (Data([0x20]) + canonical).write(to: target)
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .cannotRead) }

        try ResolvedJobTicketJSON.encode(value.ticket).write(to: target)
        let sourceTarget = target.deletingLastPathComponent().appending(path: "source.pdf")
        try Data("different source".utf8).write(to: sourceTarget)
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .sourceMismatch) }
        try value.sourcePDF.write(to: sourceTarget)

        let queueTarget = value.root.appending(path: "queues").appending(
            path: VirtualQueueStore.fileName(
                value.ticket.queue.id, value.ticket.queue.revision
            )
        )
        try FileManager.default.removeItem(at: queueTarget)
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .queueReferenceMismatch) }
    }

    func testConcurrentConflictingAcceptedJobsNeverReplaceWinner() async throws {
        let value = try fixture()
        let bytes = try ResolvedJobTicketJSON.encode(value.ticket)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["cancellationSHA256"] = String(repeating: "a", count: 64)
        let changed = try ResolvedJobTicketJSON.decode(
            JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
            ),
            queueReference: value.ticket.queue,
            queueDefinition: value.queues.load(
                reference: value.ticket.queue, workflowStore: value.workflows,
                printerStore: value.printers
            ),
            workflowProfile: value.workflows.load(
                profileID: value.ticket.workflowProfile.id,
                revision: value.ticket.workflowProfile.revision
            ),
            printerProfile: value.printers.load(reference: value.ticket.printerProfile)
        )
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for ticket in [value.ticket, changed] {
                group.addTask {
                    (try? value.jobs.save(
                        ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                        workflowStore: value.workflows, printerStore: value.printers
                    )) != nil
                }
            }
            var values: [Bool] = []
            for await result in group { values.append(result) }
            return values
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let stored = try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertTrue(stored.ticket == value.ticket || stored.ticket == changed)
        XCTAssertEqual(stored.sourcePDF, value.sourcePDF)
    }

    func testPreCommitFaultsLeaveNoVisibleOrTemporaryBundle() throws {
        enum Injected: Swift.Error { case stop }
        for (index, point) in [
            AcceptedJobStore.FaultPoint.afterTicketWrite,
            .afterSourceWrite,
            .afterStateWrite,
            .beforeRename,
        ].enumerated() {
            let value = try fixture(acceptanceID: "fault-\(index + 1)")
            let faulted = try AcceptedJobStore(root: value.root) { observed in
                if observed == point { throw Injected.stop }
            }
            XCTAssertThrowsError(try faulted.save(
                value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )) { XCTAssertTrue($0 is Injected) }
            let entries = try FileManager.default.contentsOfDirectory(
                atPath: value.root.appending(path: "accepted-jobs").path
            )
            XCTAssertTrue(entries.isEmpty)
        }
    }

    func testPostRenameFaultIsUncertainButCompleteBundleIsRecoverable() throws {
        enum Injected: Swift.Error { case stop }
        let value = try fixture(acceptanceID: "fault-after-rename")
        let faulted = try AcceptedJobStore(root: value.root) { point in
            if point == .afterRename { throw Injected.stop }
        }
        XCTAssertThrowsError(try faulted.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .commitUncertain) }
        let loaded = try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(loaded, AcceptedJobBundle(
            ticket: value.ticket,
            acceptedTicketSHA256: Self.digest(try ResolvedJobTicketJSON.encode(value.ticket)),
            sourcePDF: value.sourcePDF
        ))
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: value.root.appending(path: "accepted-jobs").path
        )
        XCTAssertEqual(entries, [AcceptedJobStore.directoryName(value.ticket.acceptanceID)])
    }

    func testIdempotentRetryRequiresParentSyncAndPreservesAdvancedState() throws {
        let value = try fixture(acceptanceID: "idempotent-parent-sync")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let accepted = try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let prepared = try states.publishPrepared(
            acceptanceID: value.ticket.acceptanceID, expected: accepted,
            payload: preparedPayload(value), queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let failing = try AcceptedJobStore(
            root: value.root, syncParentDirectory: { _ in -1 }
        )
        for _ in 0..<2 {
            XCTAssertThrowsError(try failing.save(
                value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .commitUncertain) }
            XCTAssertEqual(try states.load(
                acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            ), prepared)
        }
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        ), prepared)
    }

    func testParentSyncFailureIsUncertainUntilAnIdenticalRetryConfirmsIt() throws {
        let value = try fixture(acceptanceID: "recover-parent-sync")
        let failing = try AcceptedJobStore(
            root: value.root, syncParentDirectory: { _ in -1 }
        )
        for _ in 0..<2 {
            XCTAssertThrowsError(try failing.save(
                value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .commitUncertain) }
        }
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let loaded = try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(loaded.ticket, value.ticket)
        XCTAssertEqual(loaded.sourcePDF, value.sourcePDF)
    }

    func testDuplicateWriterCanCompleteBarrierWhilePublisherIsPaused() async throws {
        let value = try fixture(acceptanceID: "concurrent-parent-sync")
        let gate = ParentSyncGate()
        let paused = try AcceptedJobStore(
            root: value.root, syncParentDirectory: { gate.sync($0) }
        )
        let first = Task.detached {
            try paused.save(
                value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )
        }
        XCTAssertEqual(gate.entered.wait(timeout: .now() + 2), .success)
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        gate.release.signal()
        try await first.value

        let loaded = try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(loaded.ticket, value.ticket)
        XCTAssertEqual(loaded.sourcePDF, value.sourcePDF)
    }

    func testMismatchedSourceIsRejectedBeforePublication() throws {
        let value = try fixture()
        XCTAssertThrowsError(try value.jobs.save(
            value.ticket, sourcePDF: Data("different".utf8), queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .sourceMismatch) }
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: value.root.appending(path: "accepted-jobs").path
        )
        XCTAssertTrue(entries.isEmpty)
    }

    func testSourceLinksAreRejectedOnReload() throws {
        let value = try fixture()
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let source = value.root.appending(path: "accepted-jobs").appending(
            path: AcceptedJobStore.directoryName(value.ticket.acceptanceID)
        ).appending(path: "source.pdf")
        let alternate = value.root.appending(path: "alternate.pdf")
        try value.sourcePDF.write(to: alternate)
        XCTAssertEqual(chmod(alternate.path, 0o600), 0)

        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(link(alternate.path, source.path), 0)
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .cannotRead) }

        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(symlink(alternate.path, source.path), 0)
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .cannotRead) }
    }

    func testStateStartsAtomicallyAcceptedAndAdvancesWithExactDigestChain() throws {
        let value = try fixture(acceptanceID: "state-roundtrip")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        var state = try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertEqual(state, try AcceptedJobStateRecord.accepted(
            acceptanceID: value.ticket.acceptanceID,
            acceptedTicketSHA256: Self.digest(try ResolvedJobTicketJSON.encode(value.ticket))
        ))
        XCTAssertThrowsError(try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: state,
            next: .prepared(payloadSHA256: String(repeating: "a", count: 64), byteCount: 20),
            queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .preparedPayloadRequired) }
        let priorBytes = try AcceptedJobStateJSON.encode(state)
        let payload = try preparedPayload(value)
        state = try states.publishPrepared(
            acceptanceID: value.ticket.acceptanceID, expected: state,
            payload: payload,
            queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(state.previousStateSHA256, Self.digest(priorBytes))
        let stored = try states.loadPrepared(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertEqual(stored.bytes, payload.bytes)
        XCTAssertEqual(
            stored.monochromeConversion, value.ticket.monochromeConversion
        )
        XCTAssertEqual(stored.outputLabels, value.ticket.outputLabels)
        XCTAssertEqual(stored.profileSnapshot, payload.profileSnapshot)
        XCTAssertEqual(stored.resolvedControls, value.ticket.controls)
        XCTAssertEqual(stored.physicalDevice, value.ticket.physicalDevice)
        XCTAssertEqual(stored.state, state)
    }

    func testCancellationRequiresTicketCapabilityAndCannotUseGeneralTransition() throws {
        let value = try fixture(acceptanceID: "state-cancel")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertThrowsError(try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            next: .cancelledBeforeTransmission,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .cancellationUnauthorized) }
        XCTAssertThrowsError(try states.cancel(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            cancellationToken: Data("wrong".utf8),
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .cancellationUnauthorized) }
        XCTAssertEqual(try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        ), initial)
        let cancelled = try states.cancel(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            cancellationToken: value.cancellationToken,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertEqual(cancelled.phase, .cancelledBeforeTransmission)
    }

    func testLegacyWaitingStateMigratesUnderBundleLockAndCanCancel() throws {
        let value = try fixture(acceptanceID: "state-legacy-cancel")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let prepared = try states.publishPrepared(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            payload: preparedPayload(value), queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let waiting = try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: prepared,
            next: .waiting(
                payloadSHA256: Self.digest(try preparedPayload(value).bytes),
                byteCount: try preparedPayload(value).bytes.count
            ), queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let statePath = Self.statePath(value)
        try Self.writeLegacyV1(waiting, to: statePath)

        XCTAssertEqual(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        ).ticket, value.ticket)

        let migrated = try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(migrated, waiting)
        XCTAssertEqual(try Data(contentsOf: statePath), try AcceptedJobStateJSON.encode(waiting))
        let cancelled = try states.cancel(
            acceptanceID: value.ticket.acceptanceID, expected: migrated,
            cancellationToken: value.cancellationToken, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(cancelled.phase, .cancelledBeforeTransmission)
    }

    func testLegacyTransmissionStatesPreserveProgressDuringMigration() throws {
        let value = try fixture(acceptanceID: "state-legacy-progress")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        var state = try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let payload = try preparedPayload(value)
        state = try states.publishPrepared(
            acceptanceID: value.ticket.acceptanceID, expected: state,
            payload: payload, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let digest = Self.digest(payload.bytes)
        state = try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: state,
            next: .waiting(payloadSHA256: digest, byteCount: payload.bytes.count),
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        state = try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: state,
            next: .transmitting(
                payloadSHA256: digest, byteCount: payload.bytes.count, bytesAccepted: 3
            ), queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let statePath = Self.statePath(value)
        try Self.writeLegacyV1(state, to: statePath)
        state = try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(
            state.phase,
            .transmitting(
                payloadSHA256: digest, byteCount: payload.bytes.count, bytesAccepted: 3
            )
        )

        state = try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: state,
            next: .uncertain(
                payloadSHA256: digest, byteCount: payload.bytes.count, bytesAccepted: 5
            ), queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        try Self.writeLegacyV1(state, to: statePath)
        let migrated = try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(migrated, state)
        XCTAssertEqual(
            migrated.phase,
            .uncertain(
                payloadSHA256: digest, byteCount: payload.bytes.count, bytesAccepted: 5
            )
        )
    }

    func testCrossStoreTokensAndExpectedStatesCannotMutateAnotherBundle() throws {
        let acceptanceID = "state-cross-store"
        let first = try fixture(
            acceptanceID: acceptanceID,
            cancellationToken: Data("first cancellation capability".utf8)
        )
        let second = try fixture(
            acceptanceID: acceptanceID,
            cancellationToken: Data("second cancellation capability".utf8)
        )
        for value in [first, second] {
            try value.jobs.save(
                value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )
        }

        let firstStates = AcceptedJobStateStore(acceptedJobStore: first.jobs)
        let secondStates = AcceptedJobStateStore(acceptedJobStore: second.jobs)
        let firstState = try firstStates.load(
            acceptanceID: acceptanceID, queueStore: first.queues,
            workflowStore: first.workflows, printerStore: first.printers
        )
        let secondState = try secondStates.load(
            acceptanceID: acceptanceID, queueStore: second.queues,
            workflowStore: second.workflows, printerStore: second.printers
        )
        XCTAssertNotEqual(firstState.acceptedTicketSHA256, secondState.acceptedTicketSHA256)

        XCTAssertThrowsError(try secondStates.cancel(
            acceptanceID: acceptanceID, expected: secondState,
            cancellationToken: first.cancellationToken, queueStore: second.queues,
            workflowStore: second.workflows, printerStore: second.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .cancellationUnauthorized) }
        XCTAssertThrowsError(try secondStates.compareAndSwap(
            acceptanceID: acceptanceID, expected: firstState,
            next: .failedBeforeTransmission, queueStore: second.queues,
            workflowStore: second.workflows, printerStore: second.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .acceptedJobMismatch) }
        XCTAssertEqual(try secondStates.load(
            acceptanceID: acceptanceID, queueStore: second.queues,
            workflowStore: second.workflows, printerStore: second.printers
        ), secondState)

        let cancelled = try secondStates.cancel(
            acceptanceID: acceptanceID, expected: secondState,
            cancellationToken: second.cancellationToken, queueStore: second.queues,
            workflowStore: second.workflows, printerStore: second.printers
        )
        XCTAssertEqual(cancelled.phase, .cancelledBeforeTransmission)
    }

    func testRepositoryCapabilitySurvivesRootPathReplacement() throws {
        let value = try fixture(acceptanceID: "state-path-replacement")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let moved = value.root.deletingLastPathComponent().appending(
            path: "AcceptedJobStore-moved-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: moved) }
        try FileManager.default.moveItem(at: value.root, to: moved)
        try FileManager.default.createDirectory(
            at: value.root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        _ = try AcceptedJobStore(root: value.root)

        let workflows = try WorkflowProfileStore(root: moved)
        let printers = try PrinterProfileStore(root: moved)
        let queues = try VirtualQueueStore(root: moved)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: queues,
            workflowStore: workflows, printerStore: printers
        )
        let cancelled = try states.cancel(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            cancellationToken: value.cancellationToken, queueStore: queues,
            workflowStore: workflows, printerStore: printers
        )
        XCTAssertEqual(cancelled.phase, .cancelledBeforeTransmission)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: value.root.appending(path: "accepted-jobs").appending(
                path: AcceptedJobStore.directoryName(value.ticket.acceptanceID)
            ).path
        ))
        let movedState = moved.appending(path: "accepted-jobs").appending(
            path: AcceptedJobStore.directoryName(value.ticket.acceptanceID)
        ).appending(path: "state.json")
        XCTAssertEqual(
            try AcceptedJobStateJSON.decode(Data(contentsOf: movedState)), cancelled
        )
    }

    func testConcurrentStateWritersHaveOneWinnerAndStaleExpectedFails() async throws {
        let value = try fixture(acceptanceID: "state-race")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let payloads = try [preparedPayload(value), preparedPayload(value, seed: 0x40)]
        let results = await withTaskGroup(of: Bool.self) { group in
            for payload in payloads {
                group.addTask {
                    (try? states.publishPrepared(
                        acceptanceID: value.ticket.acceptanceID, expected: initial,
                        payload: payload,
                        queueStore: value.queues,
                        workflowStore: value.workflows, printerStore: value.printers
                    )) != nil
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertThrowsError(try states.publishPrepared(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            payload: try preparedPayload(value, seed: 0x20),
            queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .stateConflict) }
    }

    func testPostRenameStateFaultIsUncertainAndRecoverable() throws {
        enum Injected: Swift.Error { case stop }
        let value = try fixture(acceptanceID: "state-uncertain")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let normal = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let initial = try normal.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let faulted = AcceptedJobStateStore(acceptedJobStore: value.jobs) { point in
            if point == .afterStateRename { throw Injected.stop }
        }
        let payload = try preparedPayload(value)
        XCTAssertThrowsError(try faulted.publishPrepared(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            payload: payload,
            queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .commitUncertain) }
        let recovered = try normal.loadPrepared(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertEqual(recovered.state.generation, 2)
        XCTAssertEqual(recovered.bytes, payload.bytes)
    }

    func testPreparedPublicationValidatesTicketOrderProfileAndControls() throws {
        let value = try fixture(acceptanceID: "prepared-binding")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let other = try fixture(
            acceptanceID: "prepared-binding-other", regionID: "other"
        )
        let mismatches = try [
            preparedPayload(other),
            preparedPayload(
                value,
                profile: PrinterProfile.gc420dUSBReference(
                    revision: value.printer.revision + 1
                )
            ),
            preparedPayload(value, request: .init(
                thermalMethod: .directThermal, finishing: .tearOff,
                printSpeedIps: 2
            )),
            preparedPayload(
                value, monochromeConversion: .photographicOrderedDither4x4
            ),
        ]
        for payload in mismatches {
            XCTAssertThrowsError(try states.publishPrepared(
                acceptanceID: value.ticket.acceptanceID, expected: initial,
                payload: payload,
            queueStore: value.queues, workflowStore: value.workflows,
                printerStore: value.printers
            )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .preparedPayloadMismatch) }
        }
        XCTAssertEqual(try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        ), initial)
        XCTAssertFalse(FileManager.default.fileExists(atPath: value.root
            .appending(path: "accepted-jobs")
            .appending(path: AcceptedJobStore.directoryName(value.ticket.acceptanceID))
            .appending(path: "prepared.zpl").path))
    }

    func testPreparedOrphanAllowsExactRetryButRejectsDifferentBytes() throws {
        enum Injected: Swift.Error { case stop }
        for (pointIndex, point) in [
            AcceptedJobStateStore.FaultPoint.afterPreparedRename,
            .afterPreparedDirectorySync,
        ].enumerated() {
            for conflict in [false, true] {
                let value = try fixture(
                    acceptanceID: "prepared-orphan-\(pointIndex)-\(conflict)"
                )
                try value.jobs.save(
                    value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                    workflowStore: value.workflows, printerStore: value.printers
                )
                let normal = AcceptedJobStateStore(acceptedJobStore: value.jobs)
                let initial = try normal.load(
                    acceptanceID: value.ticket.acceptanceID,
                    queueStore: value.queues, workflowStore: value.workflows,
                    printerStore: value.printers
                )
                let first = try preparedPayload(value)
                let faulted = AcceptedJobStateStore(acceptedJobStore: value.jobs) { observed in
                    if observed == point { throw Injected.stop }
                }
                XCTAssertThrowsError(try faulted.publishPrepared(
                    acceptanceID: value.ticket.acceptanceID, expected: initial,
                    payload: first,
            queueStore: value.queues, workflowStore: value.workflows,
                    printerStore: value.printers
                )) { XCTAssertTrue($0 is Injected) }
                XCTAssertEqual(try normal.load(
                    acceptanceID: value.ticket.acceptanceID,
                    queueStore: value.queues,
                    workflowStore: value.workflows, printerStore: value.printers
                ), initial)
                XCTAssertThrowsError(try normal.loadPrepared(
                    acceptanceID: value.ticket.acceptanceID,
                    queueStore: value.queues,
                    workflowStore: value.workflows, printerStore: value.printers
                )) {
                    XCTAssertEqual(
                        $0 as? AcceptedJobStateStore.Error,
                        .preparedPayloadUnavailable
                    )
                }

                let retry = try preparedPayload(
                    value, seed: conflict ? 0x40 : 0x80
                )
                if conflict {
                    XCTAssertThrowsError(try normal.publishPrepared(
                        acceptanceID: value.ticket.acceptanceID, expected: initial,
                        payload: retry,
            queueStore: value.queues, workflowStore: value.workflows,
                        printerStore: value.printers
                    )) {
                        XCTAssertEqual(
                            $0 as? AcceptedJobStateStore.Error,
                            .preparedPayloadConflict
                        )
                    }
                } else {
                    let state = try normal.publishPrepared(
                        acceptanceID: value.ticket.acceptanceID, expected: initial,
                        payload: retry,
            queueStore: value.queues, workflowStore: value.workflows,
                        printerStore: value.printers
                    )
                    XCTAssertEqual(state.generation, 2)
                }
            }
        }
    }

    func testPreparedArtifactTamperingBlocksLoadAndLaterTransitions() throws {
        let value = try fixture(acceptanceID: "prepared-tamper")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let prepared = try states.publishPrepared(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            payload: preparedPayload(value),
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let path = value.root.appending(path: "accepted-jobs")
            .appending(path: AcceptedJobStore.directoryName(value.ticket.acceptanceID))
            .appending(path: "prepared.zpl")
        try Data("tampered".utf8).write(to: path)
        XCTAssertThrowsError(try states.load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .preparedPayloadMismatch) }
        XCTAssertThrowsError(try states.loadPrepared(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .preparedPayloadMismatch) }
        XCTAssertThrowsError(try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: prepared,
            next: .waiting(
                payloadSHA256: Self.digest(try preparedPayload(value).bytes),
                byteCount: try preparedPayload(value).bytes.count
            ), queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .preparedPayloadMismatch) }
    }

    func testPreparedArtifactLinksAndLooseModesAreRejected() throws {
        for kind in ["hard", "symbolic", "mode"] {
            let value = try fixture(acceptanceID: "prepared-unsafe-\(kind)")
            try value.jobs.save(
                value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )
            let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
            let initial = try states.load(
                acceptanceID: value.ticket.acceptanceID,
                queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )
            let payload = try preparedPayload(value)
            _ = try states.publishPrepared(
                acceptanceID: value.ticket.acceptanceID, expected: initial,
                payload: payload,
            queueStore: value.queues, workflowStore: value.workflows,
                printerStore: value.printers
            )
            let path = value.root.appending(path: "accepted-jobs")
                .appending(path: AcceptedJobStore.directoryName(value.ticket.acceptanceID))
                .appending(path: "prepared.zpl")
            if kind == "mode" {
                XCTAssertEqual(chmod(path.path, 0o644), 0)
            } else {
                let alternate = value.root.appending(path: "alternate-\(kind).zpl")
                try payload.bytes.write(to: alternate)
                XCTAssertEqual(chmod(alternate.path, 0o600), 0)
                try FileManager.default.removeItem(at: path)
                if kind == "hard" {
                    XCTAssertEqual(link(alternate.path, path.path), 0)
                } else {
                    XCTAssertEqual(symlink(alternate.path, path.path), 0)
                }
            }
            XCTAssertThrowsError(try states.loadPrepared(
                acceptanceID: value.ticket.acceptanceID,
                queueStore: value.queues,
                workflowStore: value.workflows, printerStore: value.printers
            )) {
                let expected: AcceptedJobStateStore.Error = kind == "symbolic"
                    ? .preparedPayloadUnavailable : .preparedPayloadMismatch
                XCTAssertEqual($0 as? AcceptedJobStateStore.Error, expected)
            }
        }
    }

    func testTamperedStateAndRawCancellationCapabilityAreNotAcceptedOrStored() throws {
        let value = try fixture(acceptanceID: "state-tamper")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let bundle = value.root.appending(path: "accepted-jobs").appending(
            path: AcceptedJobStore.directoryName(value.ticket.acceptanceID)
        )
        for name in ["ticket.json", "source.pdf", "state.json"] {
            let bytes = try Data(contentsOf: bundle.appending(path: name))
            XCTAssertNil(bytes.range(of: value.cancellationToken))
        }
        let statePath = bundle.appending(path: "state.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: statePath)) as? [String: Any]
        )
        object["acceptanceID"] = "another-job"
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: statePath)
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: value.ticket.acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .jobIdentityMismatch) }
        XCTAssertThrowsError(try AcceptedJobStateStore(acceptedJobStore: value.jobs).load(
            acceptanceID: value.ticket.acceptanceID,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .acceptedJobMismatch) }
    }

    func testUnsafeRootAndInvalidLookupAreRejected() throws {
        let insecure = FileManager.default.temporaryDirectory.appending(
            path: "AcceptedJobStore-insecure-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: insecure) }
        try FileManager.default.createDirectory(at: insecure, withIntermediateDirectories: false)
        chmod(insecure.path, 0o755)
        XCTAssertThrowsError(try AcceptedJobStore(root: insecure)) {
            XCTAssertEqual($0 as? AcceptedJobStore.Error, .unsafeStoreDirectory)
        }

        let value = try fixture()
        XCTAssertThrowsError(try value.jobs.load(
            acceptanceID: "../escape", queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStore.Error, .jobIdentityMismatch) }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func statePath(_ value: Fixture) -> URL {
        value.root.appending(path: "accepted-jobs")
            .appending(path: AcceptedJobStore.directoryName(value.ticket.acceptanceID))
            .appending(path: "state.json")
    }

    private static func writeLegacyV1(
        _ state: AcceptedJobStateRecord, to path: URL
    ) throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: AcceptedJobStateJSON.encode(state)
            ) as? [String: Any]
        )
        object["schemaVersion"] = 1
        object.removeValue(forKey: "acceptedTicketSHA256")
        try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys]
        ).write(to: path)
        XCTAssertEqual(chmod(path.path, 0o600), 0)
    }
}

private extension AcceptedJobStoreTests {
    private final class InertEventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [InertPersistedDelivery.Event] = []

        func append(_ event: InertPersistedDelivery.Event) {
            lock.withLock { storage.append(event) }
        }

        var events: [InertPersistedDelivery.Event] {
            lock.withLock { storage }
        }
    }

    private struct PreparedInertFixture {
        let value: Fixture
        let states: AcceptedJobStateStore
        let payload: PreparedJobPayload
        let preparedState: AcceptedJobStateRecord
        let leaseDirectory: URL
    }

    private func preparedInertFixture(
        acceptanceID: String
    ) throws -> PreparedInertFixture {
        let value = try fixture(acceptanceID: acceptanceID)
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(acceptedJobStore: value.jobs)
        let accepted = try states.load(
            acceptanceID: acceptanceID, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let payload = try preparedPayload(value)
        let preparedState = try states.publishPrepared(
            acceptanceID: acceptanceID, expected: accepted, payload: payload,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let leaseDirectory = value.root.appending(path: "device-leases")
        try FileManager.default.createDirectory(
            at: leaseDirectory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return PreparedInertFixture(
            value: value, states: states, payload: payload,
            preparedState: preparedState, leaseDirectory: leaseDirectory
        )
    }

    private func inertDelivery(
        _ fixture: PreparedInertFixture,
        recorder: InertEventRecorder = InertEventRecorder()
    ) -> InertPersistedDelivery {
        InertPersistedDelivery(
            acceptedJobStore: fixture.value.jobs,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers,
            leaseDirectory: fixture.leaseDirectory,
            observe: recorder.append
        )
    }

    private func recovery(
        _ fixture: PreparedInertFixture
    ) -> PersistedJobRecovery {
        PersistedJobRecovery(
            acceptedJobStore: fixture.value.jobs,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers,
            leaseDirectory: fixture.leaseDirectory
        )
    }

    private func transmitting(
        _ fixture: PreparedInertFixture,
        bytesAccepted: Int
    ) throws -> AcceptedJobStateRecord {
        guard case let .prepared(hash, count) = fixture.preparedState.phase else {
            throw PersistedJobRecovery.Error.invalidState
        }
        let waiting = try fixture.states.compareAndSwap(
            acceptanceID: fixture.value.ticket.acceptanceID,
            expected: fixture.preparedState,
            next: .waiting(payloadSHA256: hash, byteCount: count),
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        return try fixture.states.compareAndSwap(
            acceptanceID: fixture.value.ticket.acceptanceID,
            expected: waiting,
            next: .transmitting(
                payloadSHA256: hash,
                byteCount: count,
                bytesAccepted: bytesAccepted
            ),
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
    }
}

extension AcceptedJobStoreTests {
    func testInertPersistedDeliveryPersistsIntentBeforeDiscardAndCompletes() throws {
        let fixture = try preparedInertFixture(acceptanceID: "inert-success")
        let recorder = InertEventRecorder()
        let delivery = inertDelivery(fixture, recorder: recorder)

        let outcome = try delivery.deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario(maximumChunkBytes: 3)
        )

        XCTAssertEqual(outcome, .transmitted(byteCount: fixture.payload.bytes.count))
        XCTAssertFalse(outcome.mayRetryAutomatically)
        XCTAssertEqual(recorder.events.first, .sendAttemptPersisted)
        XCTAssertEqual(
            recorder.events.dropFirst().reduce(0) { total, event in
                if case let .bytesDiscarded(count) = event { return total + count }
                return total
            },
            fixture.payload.bytes.count
        )
        let final = try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        guard case let .transmitted(payloadSHA256, byteCount) = final.phase else {
            return XCTFail("expected transmitted lifecycle state")
        }
        XCTAssertEqual(payloadSHA256, Self.digest(fixture.payload.bytes))
        XCTAssertEqual(byteCount, fixture.payload.bytes.count)
    }

    func testInertPersistedDeliveryRecordsZeroByteAmbiguityWithoutRetry() throws {
        let fixture = try preparedInertFixture(acceptanceID: "inert-zero-uncertain")
        let recorder = InertEventRecorder()
        let outcome = try inertDelivery(fixture, recorder: recorder).deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario(becomeAmbiguousAfterBytes: 0)
        )

        XCTAssertEqual(outcome, .uncertain(bytesAccepted: 0))
        XCTAssertFalse(outcome.mayRetryAutomatically)
        XCTAssertEqual(recorder.events, [.sendAttemptPersisted])
        let final = try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        guard case let .uncertain(_, _, bytesAccepted) = final.phase else {
            return XCTFail("expected uncertain lifecycle state")
        }
        XCTAssertEqual(bytesAccepted, 0)
    }

    func testInertPersistedDeliveryRecordsPartialAmbiguityWithoutRetry() throws {
        let fixture = try preparedInertFixture(acceptanceID: "inert-partial-uncertain")
        let recorder = InertEventRecorder()
        let outcome = try inertDelivery(fixture, recorder: recorder).deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario(
                maximumChunkBytes: 2, becomeAmbiguousAfterBytes: 3
            )
        )

        XCTAssertEqual(outcome, .uncertain(bytesAccepted: 3))
        XCTAssertFalse(outcome.mayRetryAutomatically)
        XCTAssertEqual(recorder.events.first, .sendAttemptPersisted)
        XCTAssertEqual(
            recorder.events.dropFirst().reduce(0) { total, event in
                if case let .bytesDiscarded(count) = event { return total + count }
                return total
            },
            3
        )
        let final = try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        guard case let .uncertain(_, _, bytesAccepted) = final.phase else {
            return XCTFail("expected uncertain lifecycle state")
        }
        XCTAssertEqual(bytesAccepted, 3)
    }

    func testInertPersistedDeliveryFailureBeforeTransmissionIsRetryable() throws {
        let fixture = try preparedInertFixture(acceptanceID: "inert-before-send")
        let recorder = InertEventRecorder()
        let outcome = try inertDelivery(fixture, recorder: recorder).deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario(failBeforeTransmission: true)
        )

        XCTAssertEqual(outcome, .failedBeforeTransmission)
        XCTAssertTrue(outcome.mayRetryAutomatically)
        XCTAssertTrue(recorder.events.isEmpty)
        let final = try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        guard case .waiting = final.phase else {
            return XCTFail("expected retryable waiting lifecycle state")
        }

        let retry = try inertDelivery(fixture).deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario()
        )
        XCTAssertEqual(retry, .transmitted(byteCount: fixture.payload.bytes.count))
    }

    func testInertPersistedDeliveryBusyLeaseLeavesPreparedStateUntouched() throws {
        let fixture = try preparedInertFixture(acceptanceID: "inert-device-busy")
        let held = try PhysicalDeviceLease(
            acquiring: PhysicalDeviceIdentity(
                coordinationID: fixture.value.ticket.physicalDevice
            ),
            inExistingDirectory: fixture.leaseDirectory
        )
        defer { held.release() }
        let recorder = InertEventRecorder()

        let outcome = try inertDelivery(fixture, recorder: recorder).deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario()
        )

        XCTAssertEqual(outcome, .deviceBusy)
        XCTAssertTrue(outcome.mayRetryAutomatically)
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        ), fixture.preparedState)
    }

    func testInertPersistedDeliveryRejectsRepeatAndInvalidFaultWithoutSinkEffects() throws {
        let fixture = try preparedInertFixture(acceptanceID: "inert-invalid")
        let recorder = InertEventRecorder()
        let delivery = inertDelivery(fixture, recorder: recorder)
        XCTAssertThrowsError(try delivery.deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario(
                becomeAmbiguousAfterBytes: fixture.payload.bytes.count + 1
            )
        )) { XCTAssertEqual($0 as? InertPersistedDelivery.Error, .invalidScenario) }
        XCTAssertEqual(try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        ), fixture.preparedState)
        XCTAssertTrue(recorder.events.isEmpty)

        _ = try delivery.deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario()
        )
        let priorEvents = recorder.events
        XCTAssertThrowsError(try delivery.deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario()
        )) { XCTAssertEqual($0 as? InertPersistedDelivery.Error, .invalidState) }
        XCTAssertEqual(recorder.events, priorEvents)
    }

    func testInertPersistedDeliveryResumesDurableWaitingStateUnderLease() throws {
        let fixture = try preparedInertFixture(acceptanceID: "inert-resume-waiting")
        guard case let .prepared(payloadSHA256, byteCount) = fixture.preparedState.phase else {
            return XCTFail("expected prepared lifecycle state")
        }
        let waiting = try fixture.states.compareAndSwap(
            acceptanceID: fixture.value.ticket.acceptanceID,
            expected: fixture.preparedState,
            next: .waiting(payloadSHA256: payloadSHA256, byteCount: byteCount),
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        let recorder = InertEventRecorder()

        let outcome = try inertDelivery(fixture, recorder: recorder).deliver(
            acceptanceID: fixture.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario(maximumChunkBytes: 2)
        )

        XCTAssertEqual(outcome, .transmitted(byteCount: fixture.payload.bytes.count))
        XCTAssertEqual(recorder.events.first, .sendAttemptPersisted)
        let final = try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        XCTAssertGreaterThan(final.generation, waiting.generation)
        guard case .transmitted = final.phase else {
            return XCTFail("expected transmitted lifecycle state")
        }
    }

    func testInertDeliveryScenarioRejectsContradictoryFaults() {
        XCTAssertThrowsError(try InertDeliveryScenario(
            failBeforeTransmission: true, becomeAmbiguousAfterBytes: 0
        )) { XCTAssertEqual(
            $0 as? InertDeliveryScenario.ValidationError, .conflictingFaults
        ) }
    }

    func testRecoveryClassifiesPreSendStatesWithoutMutation() throws {
        let accepted = try fixture(acceptanceID: "recovery-accepted")
        try accepted.jobs.save(
            accepted.ticket, sourcePDF: accepted.sourcePDF,
            queueStore: accepted.queues, workflowStore: accepted.workflows,
            printerStore: accepted.printers
        )
        let acceptedLeases = accepted.root.appending(path: "device-leases")
        try FileManager.default.createDirectory(
            at: acceptedLeases, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let acceptedRecovery = PersistedJobRecovery(
            acceptedJobStore: accepted.jobs, queueStore: accepted.queues,
            workflowStore: accepted.workflows, printerStore: accepted.printers,
            leaseDirectory: acceptedLeases
        )
        XCTAssertEqual(
            try acceptedRecovery.reconcile(acceptanceID: accepted.ticket.acceptanceID),
            .acceptedNeedsPreparation
        )

        let prepared = try preparedInertFixture(acceptanceID: "recovery-prepared")
        XCTAssertEqual(
            try recovery(prepared).reconcile(
                acceptanceID: prepared.value.ticket.acceptanceID
            ),
            .readyForDelivery
        )
        XCTAssertEqual(try prepared.states.load(
            acceptanceID: prepared.value.ticket.acceptanceID,
            queueStore: prepared.value.queues,
            workflowStore: prepared.value.workflows,
            printerStore: prepared.value.printers
        ), prepared.preparedState)
    }

    func testRecoveryMakesInterruptedTransmissionUncertainWithoutReplay() throws {
        let fixture = try preparedInertFixture(acceptanceID: "recovery-interrupted")
        let interrupted = try transmitting(fixture, bytesAccepted: 3)

        let first = try recovery(fixture).reconcile(
            acceptanceID: fixture.value.ticket.acceptanceID
        )
        XCTAssertEqual(first, .uncertain(bytesAccepted: 3))
        let reconciled = try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        )
        XCTAssertEqual(reconciled.generation, interrupted.generation + 1)
        guard case let .uncertain(_, _, accepted) = reconciled.phase else {
            return XCTFail("expected uncertain lifecycle state")
        }
        XCTAssertEqual(accepted, 3)

        XCTAssertEqual(try recovery(fixture).reconcile(
            acceptanceID: fixture.value.ticket.acceptanceID
        ), .uncertain(bytesAccepted: 3))
        XCTAssertEqual(try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        ), reconciled)
    }

    func testRecoveryDoesNotReconcileTransmissionOwnedByLiveProcess() throws {
        let fixture = try preparedInertFixture(acceptanceID: "recovery-owned")
        let interrupted = try transmitting(fixture, bytesAccepted: 0)
        let held = try PhysicalDeviceLease(
            acquiring: PhysicalDeviceIdentity(
                coordinationID: fixture.value.ticket.physicalDevice
            ),
            inExistingDirectory: fixture.leaseDirectory
        )
        defer { held.release() }

        XCTAssertEqual(try recovery(fixture).reconcile(
            acceptanceID: fixture.value.ticket.acceptanceID
        ), .physicalDeviceBusy)
        XCTAssertEqual(try fixture.states.load(
            acceptanceID: fixture.value.ticket.acceptanceID,
            queueStore: fixture.value.queues,
            workflowStore: fixture.value.workflows,
            printerStore: fixture.value.printers
        ), interrupted)
    }

    func testRecoveryReadsTerminalEvidenceWithoutStateMutation() throws {
        let transmitted = try preparedInertFixture(acceptanceID: "recovery-transmitted")
        XCTAssertEqual(try inertDelivery(transmitted).deliver(
            acceptanceID: transmitted.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario()
        ), .transmitted(byteCount: transmitted.payload.bytes.count))
        let transmittedState = try transmitted.states.load(
            acceptanceID: transmitted.value.ticket.acceptanceID,
            queueStore: transmitted.value.queues,
            workflowStore: transmitted.value.workflows,
            printerStore: transmitted.value.printers
        )
        XCTAssertEqual(try recovery(transmitted).reconcile(
            acceptanceID: transmitted.value.ticket.acceptanceID
        ), .transmitted(byteCount: transmitted.payload.bytes.count))
        XCTAssertEqual(try transmitted.states.load(
            acceptanceID: transmitted.value.ticket.acceptanceID,
            queueStore: transmitted.value.queues,
            workflowStore: transmitted.value.workflows,
            printerStore: transmitted.value.printers
        ), transmittedState)

        let uncertain = try preparedInertFixture(acceptanceID: "recovery-uncertain")
        XCTAssertEqual(try inertDelivery(uncertain).deliver(
            acceptanceID: uncertain.value.ticket.acceptanceID,
            scenario: try InertDeliveryScenario(becomeAmbiguousAfterBytes: 2)
        ), .uncertain(bytesAccepted: 2))
        XCTAssertEqual(try recovery(uncertain).reconcile(
            acceptanceID: uncertain.value.ticket.acceptanceID
        ), .uncertain(bytesAccepted: 2))
    }
}
