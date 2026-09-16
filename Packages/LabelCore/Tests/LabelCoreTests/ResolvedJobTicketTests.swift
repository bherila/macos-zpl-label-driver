import Foundation
import XCTest
@testable import LabelCore

final class ResolvedJobTicketTests: XCTestCase {
    private let queueDigest = String(repeating: "a", count: 64)
    private let workflowDigest = String(repeating: "b", count: 64)
    private let printerDigest = String(repeating: "c", count: 64)
    private let deviceDigest = String(repeating: "d", count: 64)
    private let sourceDigest = String(repeating: "e", count: 64)
    private let cancellationDigest = String(repeating: "f", count: 64)

    private func fixture(
        queueRevision: Int = 2,
        copyPolicy: LabelOrderPlan.CopyPolicy = .engine(copies: 2, collated: true)
    ) throws -> (
        ActiveVirtualQueueSelection, ImmutableProfileReference,
        VirtualQueueDefinition, WorkflowProfile, PrinterProfile, ExtractionPlan
    ) {
        let printer = try PrinterProfile.gc420dUSBReference(revision: 7)
        let workflowReference = try ImmutableProfileReference(
            id: "letter-two-labels", revision: 3, sha256: workflowDigest
        )
        let printerReference = try ImmutableProfileReference(
            id: "gc420d-usb", revision: 7, sha256: printerDigest
        )
        let queue = try VirtualQueueDefinition(
            id: "shipping-labels", revision: queueRevision, displayName: "Shipping labels",
            physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
            workflowProfile: workflowReference,
            printerProfile: printerReference,
            workflowDefaults: PrinterControlRequest(
                thermalMethod: .directThermal, finishing: .tearOff, printSpeedIps: 3
            ),
            validatingAgainst: printer
        )
        let queueReference = try ImmutableProfileReference(
            id: queue.id, revision: queue.revision, sha256: queueDigest
        )
        let active = try ActiveVirtualQueueSelection(
            generation: 4, queue: queueReference,
            previousQueueSHA256: String(repeating: "9", count: 64)
        )
        let page = try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        let profile = try WorkflowProfile(
            id: workflowReference.id, revision: workflowReference.revision,
            outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(
                width: try Millimeters.inches(4), height: try Millimeters.inches(6)
            ),
            pageRules: [
                try WorkflowPageRule(
                    sourcePage: 1,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: page.effectivePhysicalSize()),
                    disposition: .extract([
                        try ExtractionRegion(
                            id: "label-a",
                            normalizedRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
                            outputOrder: 0
                        ),
                        try ExtractionRegion(
                            id: "label-b",
                            normalizedRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1),
                            outputOrder: 1
                        ),
                    ])
                ),
                try WorkflowPageRule(
                    sourcePage: 2,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: page.effectivePhysicalSize()),
                    disposition: .skip(.instructions)
                ),
            ]
        )
        let plan = try ExtractionPlanner.plan(
            sourcePages: [page, page], profile: profile, copyPolicy: copyPolicy
        )
        return (active, queueReference, queue, profile, printer, plan)
    }

    private func ticket(
        explicitControls: PrinterControlRequest = .init(),
        copyOwnership: JobCopyOwnership = .engine(copies: 2, collated: true)
    ) throws -> ResolvedJobTicket {
        let (active, reference, queue, workflow, printer, plan) = try fixture()
        return try ResolvedJobTicket.accept(
            acceptanceID: "accepted-42", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 4_096,
            intakeProvenance: .cupsScheduler,
            plan: plan, copyOwnership: copyOwnership,
            pageRangeOwnership: .engine(selectedSourcePages: [1, 2]),
            explicitControls: explicitControls
        )
    }

    func testCanonicalRoundTripBindsReferencesOrderCopiesAndControls() throws {
        let original = try ticket(explicitControls: PrinterControlRequest(printSpeedIps: 4))
        let bytes = try ResolvedJobTicketJSON.encode(original)
        let (_, reference, queue, workflow, printer, _) = try fixture()
        XCTAssertEqual(try ResolvedJobTicketJSON.queueReference(bytes), reference)
        let decoded = try ResolvedJobTicketJSON.decode(
            bytes, queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer
        )
        XCTAssertEqual(try ResolvedJobTicketJSON.encode(decoded), bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(original.activeSelectionGeneration, 4)
        XCTAssertEqual(original.outputLabels.map(\.regionID), [
            "label-a", "label-b", "label-a", "label-b",
        ])
        XCTAssertEqual(original.skippedPages, [
            ResolvedSkippedPage(sourcePage: 2, reason: .instructions),
        ])
        XCTAssertEqual(original.controls.printSpeedIps, .value(4))
        XCTAssertEqual(original.controls.darkness, .leaveUnchanged)
        XCTAssertEqual(original.controls.mediaGeometry, .leaveUnchanged)
        XCTAssertEqual(original.copyOwnership, .engine(copies: 2, collated: true))
        XCTAssertEqual(original.pageRangeOwnership, .engine(selectedSourcePages: [1, 2]))
        XCTAssertEqual(original.transformOwnership, .workflowProfile)
        XCTAssertEqual(original.intakeProvenance, .cupsScheduler)
    }

    func testAcceptedTicketDoesNotFollowLaterActiveRevision() throws {
        let accepted = try ticket()
        let later = try ImmutableProfileReference(
            id: accepted.queue.id, revision: accepted.queue.revision + 1,
            sha256: String(repeating: "1", count: 64)
        )
        let changed = try ActiveVirtualQueueSelection(
            generation: accepted.activeSelectionGeneration + 1,
            queue: later, previousQueueSHA256: accepted.queue.sha256
        )
        XCTAssertNotEqual(changed.queue, accepted.queue)
        XCTAssertEqual(accepted.queue.revision, 2)
        XCTAssertEqual(accepted.workflowProfile.revision, 3)
        XCTAssertEqual(accepted.printerProfile.revision, 7)
    }

    func testMismatchedQueuePlanAndUnsupportedControlsFailBeforeTicket() throws {
        let (active, reference, queue, workflow, printer, plan) = try fixture()
        let wrongReference = try ImmutableProfileReference(
            id: reference.id, revision: reference.revision,
            sha256: String(repeating: "2", count: 64)
        )
        XCTAssertThrowsError(try ResolvedJobTicket.accept(
            acceptanceID: "accepted-42", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: wrongReference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 4_096,
            intakeProvenance: .cupsScheduler,
            plan: plan, copyOwnership: .engine(copies: 2, collated: true),
            pageRangeOwnership: .engine(selectedSourcePages: [1, 2])
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidReference) }
        XCTAssertThrowsError(try ResolvedJobTicket.accept(
            acceptanceID: "accepted-42", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 4_096,
            intakeProvenance: .cupsScheduler,
            plan: plan, copyOwnership: .engine(copies: 2, collated: true),
            pageRangeOwnership: .engine(selectedSourcePages: [1, 2]),
            explicitControls: PrinterControlRequest(finishing: .cut)
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidControls) }
    }

    func testUnknownFieldsPayloadsAndBadScalarTypesFailClosed() throws {
        let original = try ticket()
        let bytes = try ResolvedJobTicketJSON.encode(original)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        root["documentPath"] = "/private/source.pdf"
        let (_, reference, queue, workflow, printer, _) = try fixture()
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(
            JSONSerialization.data(withJSONObject: root), queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .unknownField) }

        root.removeValue(forKey: "documentPath")
        root["activeSelectionGeneration"] = true
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(
            JSONSerialization.data(withJSONObject: root), queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidType("activeSelectionGeneration")) }
    }

    func testResolvedRecordsRejectChangedBindingsOrderAndOwnership() throws {
        let original = try ticket()
        let bytes = try ResolvedJobTicketJSON.encode(original)
        let (_, reference, queue, workflow, printer, _) = try fixture()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])

        var workflowReference = try XCTUnwrap(root["workflowProfile"] as? [String: Any])
        workflowReference["sha256"] = String(repeating: "7", count: 64)
        root["workflowProfile"] = workflowReference
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(
            JSONSerialization.data(withJSONObject: root), queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidReference) }

        root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var labels = try XCTUnwrap(root["outputLabels"] as? [[String: Any]])
        labels.swapAt(0, 1)
        root["outputLabels"] = labels
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(
            JSONSerialization.data(withJSONObject: root), queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidPlan) }

        root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        root["transformOwnership"] = [
            "extraction": "workflowProfile", "orientation": "upstream",
            "scaling": "workflowProfile",
        ]
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(
            JSONSerialization.data(withJSONObject: root), queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidPlan) }
    }

    func testWireAndSourceBoundsApplyBeforeAcceptance() throws {
        let bytes = try ResolvedJobTicketJSON.encode(ticket())
        let (active, reference, queue, workflow, printer, plan) = try fixture()
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(
            Data(repeating: 0x20, count: ResolvedJobTicketJSON.maximumBytes + 1),
            queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .inputTooLarge) }
        XCTAssertThrowsError(try ResolvedJobTicketJSON.encode(
            try ticket(), maximumBytes: bytes.count - 1
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .outputTooLarge) }

        XCTAssertThrowsError(try ResolvedJobTicket.accept(
            acceptanceID: "accepted-42", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest,
            sourceByteCount: ResolvedJobTicket.maximumSourceBytes + 1,
            intakeProvenance: .cupsScheduler,
            plan: plan, copyOwnership: .engine(copies: 2, collated: true),
            pageRangeOwnership: .engine(selectedSourcePages: [1, 2])
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidSource) }
    }

    func testUpstreamCopyOwnershipIsExplicitAndHasNoSecondCount() throws {
        let (active, reference, queue, workflow, printer, plan) = try fixture(
            copyPolicy: .alreadyExpanded
        )
        let original = try ResolvedJobTicket.accept(
            acceptanceID: "accepted-43", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 4_096,
            intakeProvenance: .cupsScheduler,
            plan: plan, copyOwnership: .upstreamAlreadyExpanded,
            pageRangeOwnership: .upstreamAlreadyApplied
        )
        XCTAssertEqual(original.outputLabels.map(\.regionID), ["label-a", "label-b"])
        let bytes = try ResolvedJobTicketJSON.encode(original)
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("upstream"))
        XCTAssertEqual(try ResolvedJobTicketJSON.decode(
            bytes, queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer
        ), original)
    }

    func testUnboundedCopyClaimFailsBeforeExpansion() throws {
        let (active, reference, queue, workflow, printer, plan) = try fixture()
        XCTAssertThrowsError(try ResolvedJobTicket.accept(
            acceptanceID: "accepted-44", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 4_096,
            intakeProvenance: .cupsScheduler,
            plan: plan, copyOwnership: .engine(copies: Int.max, collated: true),
            pageRangeOwnership: .engine(selectedSourcePages: [1, 2])
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidCopyOwnership) }
    }
}
