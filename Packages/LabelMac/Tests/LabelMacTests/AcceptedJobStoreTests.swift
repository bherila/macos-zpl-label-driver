import CryptoKit
import Darwin
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class AcceptedJobStoreTests: XCTestCase {
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

    private func fixture(acceptanceID: String = "accepted-42") throws -> Fixture {
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
                    id: "label", normalizedRect: region, outputOrder: 0
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
            id: workflow.id, revision: workflow.revision,
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
        let cancellationToken = Data("synthetic cancellation capability".utf8)
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
            ticket: value.ticket, sourcePDF: value.sourcePDF
        ))
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: value.root.appending(path: "accepted-jobs").path
        )
        XCTAssertEqual(entries, [AcceptedJobStore.directoryName(value.ticket.acceptanceID)])
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
        let states = AcceptedJobStateStore(root: value.root)
        var state = try states.load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertEqual(state, try AcceptedJobStateRecord.accepted(
            acceptanceID: value.ticket.acceptanceID
        ))
        let priorBytes = try AcceptedJobStateJSON.encode(state)
        state = try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: state,
            next: .prepared(payloadSHA256: String(repeating: "a", count: 64), byteCount: 20),
            acceptedJobStore: value.jobs, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        XCTAssertEqual(state.previousStateSHA256, Self.digest(priorBytes))
        XCTAssertEqual(try states.load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        ), state)
    }

    func testCancellationRequiresTicketCapabilityAndCannotUseGeneralTransition() throws {
        let value = try fixture(acceptanceID: "state-cancel")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(root: value.root)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertThrowsError(try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            next: .cancelledBeforeTransmission, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .cancellationUnauthorized) }
        XCTAssertThrowsError(try states.cancel(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            cancellationToken: Data("wrong".utf8), acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .cancellationUnauthorized) }
        XCTAssertEqual(try states.load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        ), initial)
        let cancelled = try states.cancel(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            cancellationToken: value.cancellationToken, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertEqual(cancelled.phase, .cancelledBeforeTransmission)
    }

    func testConcurrentStateWritersHaveOneWinnerAndStaleExpectedFails() async throws {
        let value = try fixture(acceptanceID: "state-race")
        try value.jobs.save(
            value.ticket, sourcePDF: value.sourcePDF, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )
        let states = AcceptedJobStateStore(root: value.root)
        let initial = try states.load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let results = await withTaskGroup(of: Bool.self) { group in
            for hash in [String(repeating: "a", count: 64), String(repeating: "b", count: 64)] {
                group.addTask {
                    (try? states.compareAndSwap(
                        acceptanceID: value.ticket.acceptanceID, expected: initial,
                        next: .prepared(payloadSHA256: hash, byteCount: 10),
                        acceptedJobStore: value.jobs, queueStore: value.queues,
                        workflowStore: value.workflows, printerStore: value.printers
                    )) != nil
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertThrowsError(try states.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            next: .prepared(payloadSHA256: String(repeating: "c", count: 64), byteCount: 10),
            acceptedJobStore: value.jobs, queueStore: value.queues,
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
        let normal = AcceptedJobStateStore(root: value.root)
        let initial = try normal.load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        let faulted = AcceptedJobStateStore(root: value.root) { _ in throw Injected.stop }
        XCTAssertThrowsError(try faulted.compareAndSwap(
            acceptanceID: value.ticket.acceptanceID, expected: initial,
            next: .prepared(payloadSHA256: String(repeating: "a", count: 64), byteCount: 10),
            acceptedJobStore: value.jobs, queueStore: value.queues,
            workflowStore: value.workflows, printerStore: value.printers
        )) { XCTAssertEqual($0 as? AcceptedJobStateStore.Error, .commitUncertain) }
        let recovered = try normal.load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
            queueStore: value.queues, workflowStore: value.workflows,
            printerStore: value.printers
        )
        XCTAssertEqual(recovered.generation, 2)
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
        XCTAssertThrowsError(try AcceptedJobStateStore(root: value.root).load(
            acceptanceID: value.ticket.acceptanceID, acceptedJobStore: value.jobs,
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
}
