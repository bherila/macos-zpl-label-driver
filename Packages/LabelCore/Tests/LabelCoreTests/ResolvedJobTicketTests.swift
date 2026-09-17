import Foundation
import XCTest
@testable import LabelCore

final class ResolvedJobTicketTests: XCTestCase {
    func testExactIntegerIdentityAcrossLargeTicketQueueReferences() throws {
        for value in [9_007_199_254_740_993, Int.max] {
            let (active, reference, queue, workflow, printer, plan) = try fixture(queueRevision: value)
            let expected = try ResolvedJobTicket.accept(acceptanceID: "large-reference",
                cancellationSHA256: cancellationDigest, activeSelection: active, queueReference: reference,
                queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
                sourceDocumentSHA256: sourceDigest, sourceByteCount: 4096, intakeProvenance: .cupsScheduler,
                plan: plan, copyOwnership: .engine(copies: 2, collated: true),
                pageRangeOwnership: .engine(selectedSourcePages: [1, 2]), explicitControls: .init())
            let bytes = try ResolvedJobTicketJSON.encode(expected)
            XCTAssertEqual(try ResolvedJobTicketJSON.queueReference(bytes), reference)
            XCTAssertEqual(try ResolvedJobTicketJSON.decode(bytes, queueReference: reference,
                queueDefinition: queue, workflowProfile: workflow, printerProfile: printer), expected)
        }
    }

    private let queueDigest = String(repeating: "a", count: 64)
    private let workflowDigest = String(repeating: "b", count: 64)
    private let printerDigest = String(repeating: "c", count: 64)
    private let deviceDigest = String(repeating: "d", count: 64)
    private let sourceDigest = String(repeating: "e", count: 64)
    private let cancellationDigest = String(repeating: "f", count: 64)

    private func fixture(
        queueRevision: Int = 2,
        copyPolicy: LabelOrderPlan.CopyPolicy = .engine(copies: 2, collated: true),
        qualifiedMotorSpeeds: Bool = false,
        qualifiedDarkness: Bool = false,
        qualifiedGeometry: Bool = false,
        qualifiedOffsets: Bool = false,
        qualifiedThermal: Bool = false
    ) throws -> (
        ActiveVirtualQueueSelection, ImmutableProfileReference,
        VirtualQueueDefinition, WorkflowProfile, PrinterProfile, ExtractionPlan
    ) {
        let baseline = try qualifiedMotorSpeeds ? MotorSpeedTestFixture.profile() : PrinterProfile.gc420dUSBReference(revision: 7)
        let c = baseline.capabilities
        let printer = try qualifiedThermal ? ThermalControlTestFixture.profile() : (qualifiedOffsets ? OffsetControlTestFixture.profile() : (qualifiedGeometry ? GeometryControlTestFixture.profile() : (qualifiedDarkness ? PrinterProfile(schemaVersion: 4, revision: 7,
            capabilities: .init(model: c.model, thermalTransfer: c.thermalTransfer, cutter: c.cutter,
                peeler: c.peeler, rewind: c.rewind, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps,
                darkness: .init(state: .supported, evidence: .documentedModel(sourceID: "R45")),
                feedSpeeds: c.feedSpeeds, backfeedSpeeds: c.backfeedSpeeds),
            installedHardware: baseline.installedHardware, media: baseline.media, connection: baseline.connection,
            configuredDefaults: .init(printSpeedIps: baseline.configuredDefaults.printSpeedIps,
                feedSpeedIps: baseline.configuredDefaults.feedSpeedIps,
                backfeedSpeedIps: baseline.configuredDefaults.backfeedSpeedIps, darkness: 10)) : baseline)))
        let workflowReference = try ImmutableProfileReference(
            id: "letter-two-labels", schemaVersion: 2,
            revision: 3, sha256: workflowDigest
        )
        let printerReference = try ImmutableProfileReference(
            id: "gc420d-usb", schemaVersion: printer.schemaVersion, revision: 7, sha256: printerDigest
        )
        let queue = try VirtualQueueDefinition(
            schemaVersion: qualifiedThermal ? 6 : (qualifiedOffsets ? 5 : (qualifiedGeometry ? 4 : (qualifiedDarkness ? 3 : (qualifiedMotorSpeeds ? 2 : 1)))),
            id: "shipping-labels", revision: queueRevision, displayName: "Shipping labels",
            physicalDevice: PhysicalDeviceCoordinationID(sha256: deviceDigest),
            workflowProfile: workflowReference,
            printerProfile: printerReference,
            workflowDefaults: PrinterControlRequest(
                thermalMethod: qualifiedThermal ? nil : .directThermal, finishing: .tearOff, printSpeedIps: 3,
                feedSpeedIps: qualifiedMotorSpeeds ? 4 : nil,
                backfeedSpeedIps: qualifiedMotorSpeeds ? 2 : nil, darkness: qualifiedDarkness ? 20 : nil,
                tracking: qualifiedGeometry ? .continuous : nil,
                mediaGeometry: qualifiedGeometry ? MediaGeometryRequest(widthDots: 30, lengthDots: 20, originXDot: 2) : nil,
                offsets: qualifiedOffsets ? .init(shiftLeftDots: 1) : nil
            ),
            validatingAgainst: printer
        )
        let queueReference = try ImmutableProfileReference(
            id: queue.id, schemaVersion: queue.schemaVersion, revision: queue.revision, sha256: queueDigest
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
            monochromeConversion: .photographicOrderedDither4x4,
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
        XCTAssertEqual(try ResolvedJobTicketJSON.acceptanceID(bytes), original.acceptanceID)
        XCTAssertEqual(try ResolvedJobTicketJSON.sourceByteCount(bytes), 4_096)
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
        XCTAssertEqual(original.monochromeConversion, .photographicOrderedDither4x4)
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

        root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        root["monochromeConversion"] = [
            "mode": "textAndBarcodeThreshold", "cutoff": 128,
        ]
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(
            JSONSerialization.data(withJSONObject: root), queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer
        )) { XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidImaging) }
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
    func testQualifiedMotorSpeedsSurviveQueueTicketAndImmutablePreparation() throws {
        let (active, reference, queue, workflow, printer, plan) = try fixture(qualifiedMotorSpeeds: true)
        let queueBytes = try VirtualQueueJSON.encode(queue)
        XCTAssertEqual(try VirtualQueueJSON.printerProfileReference(in: queueBytes), queue.printerProfile)
        XCTAssertEqual(try VirtualQueueJSON.decode(queueBytes, validatingAgainst: printer), queue)
        let ticket = try ResolvedJobTicket.accept(acceptanceID: "motor-job", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer, sourceDocumentSHA256: sourceDigest,
            sourceByteCount: 4096, intakeProvenance: .cupsScheduler, plan: plan,
            copyOwnership: .engine(copies: 2, collated: true),
            pageRangeOwnership: .engine(selectedSourcePages: [1, 2]),
            explicitControls: .init(feedSpeedIps: 2, backfeedSpeedIps: 3))
        XCTAssertEqual(ticket.schemaVersion, 3)
        XCTAssertEqual(ticket.controls.feedSpeedIps, .value(2))
        XCTAssertEqual(ticket.controls.backfeedSpeedIps, .value(3))
        let bytes = try ResolvedJobTicketJSON.encode(ticket)
        XCTAssertEqual(try ResolvedJobTicketJSON.queueReference(bytes), reference)
        XCTAssertEqual(try ResolvedJobTicketJSON.acceptanceID(bytes), ticket.acceptanceID)
        XCTAssertEqual(try ResolvedJobTicketJSON.sourceByteCount(bytes), 4096)
        let decoded = try ResolvedJobTicketJSON.decode(bytes, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer)
        XCTAssertEqual(decoded, ticket)
        XCTAssertEqual(try ResolvedJobTicketJSON.encode(decoded), bytes)
        XCTAssertEqual(try ZPLControlEncoder().encode(decoded.controls), Data("^MMT\n^PR3,2,3\n".utf8))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["feedSpeedIps", "backfeedSpeedIps"] {
            var changed = root
            var controls = try XCTUnwrap(changed["controls"] as? [String: Any])
            controls[key] = ["mode": "value", "value": 12]; changed["controls"] = controls
            XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(JSONSerialization.data(withJSONObject: changed),
                queueReference: reference, queueDefinition: queue, workflowProfile: workflow, printerProfile: printer)) {
                XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidControls)
            }
            controls.removeValue(forKey: key); changed["controls"] = controls
            XCTAssertThrowsError(try ResolvedJobTicketJSON.acceptanceID(JSONSerialization.data(withJSONObject: changed)))
        }
        var missingEffective = root
        var missingControls = try XCTUnwrap(root["controls"] as? [String: Any])
        for key in ["feedSpeedIps", "backfeedSpeedIps"] {
            missingControls[key] = ["mode": "notExplicitlyControlled", "value": NSNull()]
        }
        missingEffective["controls"] = missingControls
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(JSONSerialization.data(withJSONObject: missingEffective),
            queueReference: reference, queueDefinition: queue, workflowProfile: workflow, printerProfile: printer)) {
            XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidControls)
        }
        var downgraded = root; downgraded["schemaVersion"] = 2
        XCTAssertThrowsError(try ResolvedJobTicketJSON.acceptanceID(JSONSerialization.data(withJSONObject: downgraded)))
        var queueRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: queueBytes) as? [String: Any])
        for key in ["feedSpeedIps", "backfeedSpeedIps"] {
            var changed = queueRoot
            var defaults = try XCTUnwrap(changed["defaults"] as? [String: Any])
            defaults.removeValue(forKey: key); changed["defaults"] = defaults
            XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: changed), validatingAgainst: printer))
            defaults[key] = true; changed["defaults"] = defaults
            XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: changed), validatingAgainst: printer))
        }
        queueRoot["schemaVersion"] = 1
        XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: queueRoot), validatingAgainst: printer))
    }

    func testQualifiedDarknessQueueAndTicketPreserveDefaultAndRejectDroppedControl() throws {
        let (active, reference, queue, workflow, printer, plan) = try fixture(qualifiedMotorSpeeds: true, qualifiedDarkness: true)
        let queueBytes = try VirtualQueueJSON.encode(queue)
        XCTAssertEqual(try VirtualQueueJSON.printerProfileReference(in: queueBytes), queue.printerProfile)
        XCTAssertEqual(try VirtualQueueJSON.decode(queueBytes, validatingAgainst: printer), queue)
        let ticket = try ResolvedJobTicket.accept(acceptanceID: "synthetic-darkness", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer, sourceDocumentSHA256: sourceDigest,
            sourceByteCount: 4096, intakeProvenance: .offlineCLI, plan: plan,
            copyOwnership: .engine(copies: 2, collated: true), pageRangeOwnership: .engine(selectedSourcePages: [1, 2]))
        XCTAssertEqual(ticket.schemaVersion, 4)
        XCTAssertEqual(ticket.controls.darkness, .value(20))
        let bytes = try ResolvedJobTicketJSON.encode(ticket)
        let decoded = try ResolvedJobTicketJSON.decode(bytes, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer)
        XCTAssertEqual(decoded, ticket)
        XCTAssertEqual(try ResolvedJobTicketJSON.encode(decoded), bytes)
        XCTAssertEqual(try ZPLControlEncoder().encode(decoded.controls), Data("^MMT\n^PR3,4,2\n^MD0\n~SD20\n".utf8))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var changed = root
        var controls = try XCTUnwrap(root["controls"] as? [String: Any])
        controls["darkness"] = ["mode": "leaveUnchanged", "value": NSNull()]; changed["controls"] = controls
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(JSONSerialization.data(withJSONObject: changed),
            queueReference: reference, queueDefinition: queue, workflowProfile: workflow, printerProfile: printer))
        changed = root; changed["schemaVersion"] = 3
        XCTAssertThrowsError(try ResolvedJobTicketJSON.acceptanceID(JSONSerialization.data(withJSONObject: changed)))
        var queueRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: queueBytes) as? [String: Any])
        var defaults = try XCTUnwrap(queueRoot["defaults"] as? [String: Any])
        for replacement: Any in [true, -1, 31, "20"] {
            defaults["darkness"] = replacement; queueRoot["defaults"] = defaults
            XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: queueRoot), validatingAgainst: printer))
        }
        defaults.removeValue(forKey: "darkness"); queueRoot["defaults"] = defaults
        XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: queueRoot), validatingAgainst: printer))
    }

    func testGeometryQueueAndTicketResolvePartialDefaultsAndRejectDroppingOrDowngrading() throws {
        let (active, reference, queue, workflow, printer, plan) = try fixture(qualifiedGeometry: true)
        let queueBytes = try VirtualQueueJSON.encode(queue)
        XCTAssertEqual(try VirtualQueueJSON.printerProfileReference(in: queueBytes), queue.printerProfile)
        XCTAssertEqual(try VirtualQueueJSON.decode(queueBytes, validatingAgainst: printer), queue)
        let ticket = try ResolvedJobTicket.accept(acceptanceID: "synthetic-geometry", cancellationSHA256: cancellationDigest,
            activeSelection: active, queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer, sourceDocumentSHA256: sourceDigest,
            sourceByteCount: 4096, intakeProvenance: .offlineCLI, plan: plan,
            copyOwnership: .engine(copies: 2, collated: true), pageRangeOwnership: .engine(selectedSourcePages: [1, 2]),
            explicitControls: .init(mediaGeometry: MediaGeometryRequest(originYDot: 3)))
        XCTAssertEqual(ticket.schemaVersion, 5)
        XCTAssertEqual(ticket.controls.mediaGeometry, .value(try .init(widthDots: 30, lengthDots: 20, originXDot: 2, originYDot: 3)))
        let bytes = try ResolvedJobTicketJSON.encode(ticket)
        let decoded = try ResolvedJobTicketJSON.decode(bytes, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer)
        XCTAssertEqual(decoded, ticket)
        XCTAssertEqual(try ResolvedJobTicketJSON.encode(decoded), bytes)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var changed = root
        var controls = try XCTUnwrap(root["controls"] as? [String: Any])
        controls["mediaGeometry"] = ["mode": "leaveUnchanged", "value": NSNull()]; changed["controls"] = controls
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(JSONSerialization.data(withJSONObject: changed),
            queueReference: reference, queueDefinition: queue, workflowProfile: workflow, printerProfile: printer))
        for version in [2, 3, 4, 6] {
            changed = root; changed["schemaVersion"] = version
            XCTAssertThrowsError(try ResolvedJobTicketJSON.acceptanceID(JSONSerialization.data(withJSONObject: changed)))
        }
        changed = root
        var futureQueue = try XCTUnwrap(root["queue"] as? [String: Any])
        futureQueue["schemaVersion"] = 7; changed["queue"] = futureQueue
        XCTAssertThrowsError(try ResolvedJobTicketJSON.queueReference(JSONSerialization.data(withJSONObject: changed))) {
            XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidReference)
        }
        let queueRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: queueBytes) as? [String: Any])
        for version in [1, 2, 3, 5] {
            var changedQueue = queueRoot; changedQueue["schemaVersion"] = version
            XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: changedQueue), validatingAgainst: printer))
        }
    }

    func testOffsetQueueFiveAndTicketSixPreserveIndependentImmutableFields() throws {
        let (selection, reference, queue, workflow, printer, plan) = try fixture(qualifiedOffsets: true)
        let queueBytes = try VirtualQueueJSON.encode(queue)
        XCTAssertEqual(try VirtualQueueJSON.decode(queueBytes, validatingAgainst: printer), queue)
        XCTAssertEqual(try VirtualQueueJSON.printerProfileReference(in: queueBytes), queue.printerProfile)
        let ticket = try ResolvedJobTicket.accept(acceptanceID: "synthetic-offset-ticket",
            cancellationSHA256: cancellationDigest, activeSelection: selection, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 100, intakeProvenance: .offlineCLI, plan: plan,
            copyOwnership: .engine(copies: 2, collated: true), pageRangeOwnership: .engine(selectedSourcePages: [1, 2]),
            explicitControls: .init(offsets: .init(labelTopDots: 2)))
        XCTAssertEqual(ticket.schemaVersion, 6)
        XCTAssertEqual(ticket.queue.schemaVersion, 5)
        XCTAssertEqual(ticket.printerProfile.schemaVersion, 6)
        XCTAssertEqual(ticket.controls.offsets, .value(.init(shiftLeftDots: 1, labelTopDots: 2)))
        let bytes = try ResolvedJobTicketJSON.encode(ticket)
        XCTAssertEqual(try ResolvedJobTicketJSON.decode(bytes, queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer), ticket)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var changed = root
        var controls = try XCTUnwrap(root["controls"] as? [String: Any])
        controls["offsets"] = ["mode": "leaveUnchanged", "value": NSNull()]; changed["controls"] = controls
        XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(JSONSerialization.data(withJSONObject: changed),
            queueReference: reference, queueDefinition: queue, workflowProfile: workflow, printerProfile: printer))
        for version in [2, 3, 4, 5, 8] {
            changed = root; changed["schemaVersion"] = version
            XCTAssertThrowsError(try ResolvedJobTicketJSON.acceptanceID(JSONSerialization.data(withJSONObject: changed)))
        }
        let queueRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: queueBytes) as? [String: Any])
        for version in [1, 2, 3, 4, 7] {
            changed = queueRoot; changed["schemaVersion"] = version
            XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: changed), validatingAgainst: printer))
        }
        changed = root
        var wrongQueue = try XCTUnwrap(root["queue"] as? [String: Any])
        wrongQueue["schemaVersion"] = 7; changed["queue"] = wrongQueue
        XCTAssertThrowsError(try ResolvedJobTicketJSON.queueReference(JSONSerialization.data(withJSONObject: changed)))
    }

    func testThermalTicket7AndQueue6CaptureConfiguredMethodAndRejectTampering() throws {
        let (active, reference, queue, workflow, printer, plan) = try fixture(qualifiedThermal: true)
        let ticket = try ResolvedJobTicket.accept(acceptanceID: "thermal-acceptance",
            cancellationSHA256: cancellationDigest, activeSelection: active, queueReference: reference,
            queueDefinition: queue, workflowProfile: workflow, printerProfile: printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 42, intakeProvenance: .offlineCLI, plan: plan,
            copyOwnership: .engine(copies: 2, collated: true), pageRangeOwnership: .engine(selectedSourcePages: [1, 2]))
        XCTAssertEqual(ticket.schemaVersion, 7)
        XCTAssertEqual(ticket.queue.schemaVersion, 6)
        XCTAssertEqual(ticket.printerProfile.schemaVersion, 7)
        XCTAssertEqual(ticket.controls.thermalMethod, .value(.thermalTransfer))
        XCTAssertEqual(ticket.controls.offsets, .value(.init(shiftLeftDots: 0, labelTopDots: 0)))
        let bytes = try ResolvedJobTicketJSON.encode(ticket)
        XCTAssertEqual(try ResolvedJobTicketJSON.decode(bytes, queueReference: reference, queueDefinition: queue,
            workflowProfile: workflow, printerProfile: printer), ticket)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for bad in [["mode": "value", "value": "directThermal"] as [String: Any],
                    ["mode": "leaveUnchanged", "value": NSNull()]] {
            var changed = root
            var controls = try XCTUnwrap(root["controls"] as? [String: Any])
            controls["thermalMethod"] = bad; changed["controls"] = controls
            XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(JSONSerialization.data(withJSONObject: changed),
                queueReference: reference, queueDefinition: queue, workflowProfile: workflow, printerProfile: printer))
        }
        for version in [2, 3, 4, 5, 6, 8] {
            var changed = root; changed["schemaVersion"] = version
            XCTAssertThrowsError(try ResolvedJobTicketJSON.decode(JSONSerialization.data(withJSONObject: changed),
                queueReference: reference, queueDefinition: queue, workflowProfile: workflow, printerProfile: printer))
        }
        let queueBytes = try VirtualQueueJSON.encode(queue)
        XCTAssertEqual(try VirtualQueueJSON.decode(queueBytes, validatingAgainst: printer), queue)
        let queueRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: queueBytes) as? [String: Any])
        let defaults = try XCTUnwrap(queueRoot["defaults"] as? [String: Any])
        XCTAssertTrue(defaults["thermalMethod"] is NSNull)
        var changed = queueRoot; var changedDefaults = defaults
        changedDefaults["thermalMethod"] = "directThermal"; changed["defaults"] = changedDefaults
        XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: changed), validatingAgainst: printer))
        for version in [1, 2, 3, 4, 5, 7] {
            changed = queueRoot; changed["schemaVersion"] = version
            XCTAssertThrowsError(try VirtualQueueJSON.decode(JSONSerialization.data(withJSONObject: changed), validatingAgainst: printer))
        }
    }

}
