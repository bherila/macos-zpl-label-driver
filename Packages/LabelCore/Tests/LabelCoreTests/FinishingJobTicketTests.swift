import Foundation
import XCTest
@testable import LabelCore

/// Offline finishing admission only. Nothing here installs a queue, admits a
/// scheduler job, observes a device or authorizes transmission.
final class FinishingJobTicketTests: XCTestCase {
    // MARK: - Fixtures

    private let queueDigest = String(repeating: "d", count: 64)
    private let workflowDigest = String(repeating: "b", count: 64)
    private let printerDigest = String(repeating: "c", count: 64)
    private let deviceDigest = String(repeating: "a", count: 64)
    private let sourceDigest = String(repeating: "e", count: 64)
    private let cancellationDigest = String(repeating: "f", count: 64)
    private let documented = CapabilityFact(state: .supported,
                                            evidence: .documentedModel(sourceID: "R26"))

    private struct Context {
        let queueReference: FinishingQueuePolicyReference
        let queue: FinishingQueueDefinition
        let device: FinishingDeviceBinding
        let workflow: WorkflowProfile
        let printer: PrinterProfile
        let plan: ExtractionPlan
    }

    private func printerProfile(
        maximumBatch: Int = 3,
        revision: Int = 11,
        model: String = "GC420d",
        stock: Observation<Bool> = .observed(true, evidence: .reportedInstallation)
    ) throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(revision: revision)
        let modes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]
        return try .init(
            schemaVersion: 8, revision: revision,
            capabilities: .init(model: model, thermalTransfer: base.capabilities.thermalTransfer,
                cutter: documented, peeler: documented, rewind: documented,
                tracking: base.capabilities.tracking,
                printSpeedChoicesIps: base.capabilities.printSpeedChoicesIps,
                darkness: documented, directThermal: documented),
            installedHardware: .init(transport: .usb, selectedFinishing: .tearOff,
                cutter: .init(state: .supported, evidence: .reportedInstallation),
                peeler: .init(state: .supported, evidence: .reportedInstallation),
                observedSpeedIps: nil, observedDarkness: nil, observedTracking: nil),
            media: base.media, connection: base.connection,
            configuredDefaults: .init(thermalMethod: .directThermal),
            thermalMedia: .init(method: .observed(.directThermal, evidence: .reportedInstallation),
                                ribbonPresent: .observed(false, evidence: .reportedInstallation)),
            finishingConfiguration: .init(
                finishing: .init(
                    modes: Dictionary(uniqueKeysWithValues: modes.map { ($0, documented) }),
                    enabledModes: Set(modes),
                    installed: .init(cutter: .observed(true, evidence: .reportedInstallation),
                                     peeler: .observed(true, evidence: .reportedInstallation),
                                     rewinder: .observed(true, evidence: .reportedInstallation))),
                stock: .init(media: base.media, compatibleModes:
                    Dictionary(uniqueKeysWithValues: modes.map { ($0, stock) })),
                schedules: .init(everyLabel: documented, batch: documented, endOfJob: documented,
                                 maximumBatchSize: maximumBatch)))
    }

    private func workflowProfile(
        cutoff: UInt8 = 128, revision: Int = 3
    ) throws -> WorkflowProfile {
        let page = try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        return try WorkflowProfile(
            schemaVersion: 2, id: "letter-two-labels", revision: revision,
            outputStockID: "nominal-4x6",
            outputStock: PhysicalSize(width: Millimeters.inches(4), height: Millimeters.inches(6)),
            monochromeConversion: .textAndBarcodeThreshold(cutoff: cutoff),
            pageRules: [
                try WorkflowPageRule(
                    sourcePage: 1,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: page.effectivePhysicalSize()),
                    disposition: .extract([
                        try ExtractionRegion(id: "label-a",
                            normalizedRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
                            outputOrder: 0),
                        try ExtractionRegion(id: "label-b",
                            normalizedRect: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1),
                            outputOrder: 1),
                    ])),
                try WorkflowPageRule(
                    sourcePage: 2,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: page.effectivePhysicalSize()),
                    disposition: .skip(.instructions)),
            ])
    }

    private func makeContext(
        selection: FinishingQueueSelection = .init(mode: .cut,
            schedule: .batch(size: 3, cutRemainderAtJobEnd: true)),
        defaults: PrinterControlDefaults = .init(printSpeedIps: 3),
        pitch: Observation<DotResolution>? = nil,
        deviceSHA256: String? = nil,
        printer overridePrinter: PrinterProfile? = nil,
        workflow overrideWorkflow: WorkflowProfile? = nil,
        copyPolicy: LabelOrderPlan.CopyPolicy = .engine(copies: 2, collated: true)
    ) throws -> Context {
        let printer = try overridePrinter ?? printerProfile()
        let workflow = try overrideWorkflow ?? workflowProfile()
        let workflowReference = try ImmutableProfileReference(
            id: workflow.id, schemaVersion: workflow.schemaVersion,
            revision: workflow.revision, sha256: workflowDigest)
        let printerReference = try ImmutableProfileReference(
            id: "synthetic-printer", schemaVersion: 8, revision: printer.revision,
            sha256: printerDigest)
        let device = try PhysicalDeviceCoordinationID(sha256: deviceSHA256 ?? deviceDigest)
        let queue = try FinishingQueueDefinition(
            id: "synthetic-finishing", revision: 2, displayName: "Synthetic finishing",
            physicalDevice: device, workflowProfile: workflowReference,
            printerProfile: printerReference, defaultSelection: selection,
            workflowDefaults: defaults, validatingWorkflow: workflow, validatingPrinter: printer)
        let binding = try FinishingDeviceBinding(
            printerProfile: printerReference, physicalDevice: device,
            nativePitch: pitch ?? .observed(DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8),
                                            evidence: .documentedModel(sourceID: "R26")),
            validatingPrinter: printer)
        let page = try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)
        let plan = try ExtractionPlanner.plan(sourcePages: [page, page], profile: workflow,
                                              copyPolicy: copyPolicy)
        return Context(
            queueReference: try FinishingQueuePolicyReference(
                id: queue.id, revision: queue.revision, sha256: queueDigest),
            queue: queue, device: binding, workflow: workflow, printer: printer, plan: plan)
    }

    private func accept(
        _ context: Context,
        acceptanceID: String = "finishing-accepted-1",
        cancellation: String? = nil,
        sourceByteCount: Int = 4_096,
        intake: JobIntakeProvenance = .offlineCLI,
        selection: FinishingQueueSelection? = nil,
        explicitControls: PrinterControlRequest = .init(),
        copyOwnership: JobCopyOwnership = .engine(copies: 2, collated: true),
        pageRangeOwnership: JobPageRangeOwnership = .engine(selectedSourcePages: [1, 2])
    ) throws -> ResolvedFinishingJobTicket {
        try ResolvedFinishingJobTicket.accept(
            acceptanceID: acceptanceID, cancellationSHA256: cancellation ?? cancellationDigest,
            queueReference: context.queueReference, queueDefinition: context.queue,
            device: context.device, workflow: context.workflow, printer: context.printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: sourceByteCount,
            intakeProvenance: intake, plan: context.plan, copyOwnership: copyOwnership,
            pageRangeOwnership: pageRangeOwnership, selection: selection,
            explicitControls: explicitControls)
    }

    /// Rebuilds one accepted ticket with a single substituted field so each
    /// reference, identity and ownership binding is exercised independently.
    private func rebuild(
        _ ticket: ResolvedFinishingJobTicket, in context: Context,
        acceptanceID: String? = nil, cancellation: String? = nil,
        queue: FinishingQueuePolicyReference? = nil,
        workflowProfile: ImmutableProfileReference? = nil,
        printerProfile: ImmutableProfileReference? = nil,
        physicalDevice: PhysicalDeviceCoordinationID? = nil,
        nativePitch: Observation<DotResolution>? = nil,
        canvas: DotCanvas? = nil,
        selection: FinishingQueueSelection? = nil,
        cutAfterOutputLabels: [Int]? = nil,
        sourceDocumentSHA256: String? = nil, sourceByteCount: Int? = nil,
        sourcePageCount: Int? = nil, intake: JobIntakeProvenance? = nil,
        copyOwnership: JobCopyOwnership? = nil,
        pageRangeOwnership: JobPageRangeOwnership? = nil,
        transformOwnership: JobTransformOwnership? = nil,
        monochromeConversion: MonochromeConversion? = nil,
        controls: ResolvedPrinterControls? = nil,
        outputLabels: [ResolvedOutputLabel]? = nil,
        skippedPages: [ResolvedSkippedPage]? = nil,
        queueDefinition: FinishingQueueDefinition? = nil,
        device: FinishingDeviceBinding? = nil,
        workflow: WorkflowProfile? = nil,
        printer: PrinterProfile? = nil
    ) throws -> ResolvedFinishingJobTicket {
        try ResolvedFinishingJobTicket(
            acceptanceID: acceptanceID ?? ticket.acceptanceID,
            cancellationSHA256: cancellation ?? ticket.cancellationSHA256,
            queue: queue ?? ticket.queue,
            workflowProfile: workflowProfile ?? ticket.workflowProfile,
            printerProfile: printerProfile ?? ticket.printerProfile,
            physicalDevice: physicalDevice ?? ticket.physicalDevice,
            nativePitch: nativePitch ?? ticket.nativePitch,
            canvas: canvas ?? ticket.canvas,
            selection: selection ?? ticket.selection,
            cutAfterOutputLabels: cutAfterOutputLabels ?? ticket.cutAfterOutputLabels,
            sourceDocumentSHA256: sourceDocumentSHA256 ?? ticket.sourceDocumentSHA256,
            sourceByteCount: sourceByteCount ?? ticket.sourceByteCount,
            sourcePageCount: sourcePageCount ?? ticket.sourcePageCount,
            intakeProvenance: intake ?? ticket.intakeProvenance,
            copyOwnership: copyOwnership ?? ticket.copyOwnership,
            pageRangeOwnership: pageRangeOwnership ?? ticket.pageRangeOwnership,
            transformOwnership: transformOwnership ?? ticket.transformOwnership,
            monochromeConversion: monochromeConversion ?? ticket.monochromeConversion,
            controls: controls ?? ticket.controls,
            outputLabels: outputLabels ?? ticket.outputLabels,
            skippedPages: skippedPages ?? ticket.skippedPages,
            queueDefinition: queueDefinition ?? context.queue,
            device: device ?? context.device,
            workflow: workflow ?? context.workflow,
            printer: printer ?? context.printer)
    }

    private func assertTicketError(
        _ expected: FinishingJobTicketError, _ line: UInt = #line,
        _ body: () throws -> ResolvedFinishingJobTicket
    ) {
        XCTAssertThrowsError(try body(), line: line) {
            XCTAssertEqual($0 as? FinishingJobTicketError, expected, line: line)
        }
    }

    // MARK: - Positive admission, store/load and preparation

    func testEveryModeAndScheduleBindsCanonicalRecordAndPreparation() throws {
        let schedules: [FinishingMode: CutSchedule?] = [
            .tearOff: nil, .peel: nil, .rewind: nil,
            .cut: .batch(size: 3, cutRemainderAtJobEnd: true),
        ]
        for (mode, schedule) in schedules {
            let selection = FinishingQueueSelection(mode: mode, schedule: schedule)
            let context = try makeContext(selection: selection)
            let ticket = try accept(context)
            XCTAssertEqual(ticket.selection.mode, mode)
            XCTAssertEqual(ticket.controls.finishing, .value(mode))
            XCTAssertEqual(ticket.controls.profileSchemaVersion, 8)
            XCTAssertEqual(ticket.outputLabels.map(\.regionID),
                           ["label-a", "label-b", "label-a", "label-b"])
            XCTAssertEqual(ticket.skippedPages, [ResolvedSkippedPage(sourcePage: 2, reason: .instructions)])
            // Documented8dots/mm, not the nominal integer203DPI shorthand.
            XCTAssertEqual(ticket.canvas.width, 813)
            XCTAssertEqual(ticket.canvas.height, 1219)
            XCTAssertEqual(ticket.cutAfterOutputLabels, mode == .cut ? [3, 4] : [])
            XCTAssertEqual(ticket.intakeProvenance, .offlineCLI)

            let bytes = try FinishingJobTicketJSON.encode(ticket)
            let references = try FinishingJobTicketJSON.references(in: bytes)
            XCTAssertEqual(references.queue, context.queueReference)
            XCTAssertEqual(references.workflow, context.queue.workflowProfile)
            XCTAssertEqual(references.printer, context.queue.printerProfile)
            XCTAssertEqual(try FinishingJobTicketJSON.acceptanceID(in: bytes), ticket.acceptanceID)
            let loaded = try FinishingJobTicketJSON.decode(
                bytes, queueReference: context.queueReference, queue: context.queue,
                device: context.device, workflow: context.workflow, printer: context.printer)
            XCTAssertEqual(loaded, ticket)
            XCTAssertEqual(try FinishingJobTicketJSON.encode(loaded), bytes)
            XCTAssertNoThrow(try loaded.validate(preparation: ticket.preparationBinding))
        }
    }

    func testEveryCutScheduleBindsItsOwnBoundariesWithoutClamping() throws {
        let expected: [(CutSchedule, [Int])] = [
            (.everyLabel, [1, 2, 3, 4]),
            (.endOfJob, [4]),
            (.batch(size: 3, cutRemainderAtJobEnd: true), [3, 4]),
            (.batch(size: 3, cutRemainderAtJobEnd: false), [3]),
        ]
        for (schedule, boundaries) in expected {
            let context = try makeContext(selection: .init(mode: .cut, schedule: schedule))
            let ticket = try accept(context)
            XCTAssertEqual(ticket.cutAfterOutputLabels, boundaries)
            assertTicketError(.scheduleMismatch) {
                try rebuild(ticket, in: context, cutAfterOutputLabels: boundaries + [4])
            }
        }
        // An unqualified batch size fails instead of being reduced to the limit.
        XCTAssertThrowsError(try makeContext(selection: .init(mode: .cut,
            schedule: .batch(size: 4, cutRemainderAtJobEnd: true))))
    }

    func testCopiesRangesAndOrderKeepOneOwnerThroughLoad() throws {
        let uncollated = try makeContext(copyPolicy: .engine(copies: 2, collated: false))
        let ticket = try accept(uncollated, copyOwnership: .engine(copies: 2, collated: false))
        XCTAssertEqual(ticket.outputLabels.map(\.regionID),
                       ["label-a", "label-a", "label-b", "label-b"])
        let selected = try makeContext(copyPolicy: .alreadyExpanded)
        let single = try ResolvedFinishingJobTicket.accept(
            acceptanceID: "finishing-accepted-2", cancellationSHA256: cancellationDigest,
            queueReference: selected.queueReference, queueDefinition: selected.queue,
            device: selected.device, workflow: selected.workflow, printer: selected.printer,
            sourceDocumentSHA256: sourceDigest, sourceByteCount: 4_096,
            plan: try ExtractionPlanner.plan(
                sourcePages: [try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792),
                              try PDFPageBox(originX: 0, originY: 0, width: 612, height: 792)],
                profile: selected.workflow, selectedSourcePages: [1], copyPolicy: .alreadyExpanded),
            copyOwnership: .upstreamAlreadyExpanded,
            pageRangeOwnership: .engine(selectedSourcePages: [1]))
        XCTAssertEqual(single.outputLabels.count, 2)
        XCTAssertTrue(single.skippedPages.isEmpty)
        XCTAssertEqual(single.cutAfterOutputLabels, [2])
        // A second expansion of an already expanded list is rejected.
        assertTicketError(.invalidPlan) {
            try rebuild(single, in: selected, copyOwnership: .engine(copies: 2, collated: true))
        }
        assertTicketError(.invalidPlan) {
            try rebuild(ticket, in: uncollated,
                        outputLabels: ticket.outputLabels.reversed())
        }
        assertTicketError(.invalidPlan) {
            try rebuild(ticket, in: uncollated, pageRangeOwnership: .engine(selectedSourcePages: [1]))
        }
        assertTicketError(.invalidCopyOwnership) {
            try rebuild(ticket, in: uncollated, copyOwnership: .engine(copies: 0, collated: false))
        }
        assertTicketError(.invalidPlan) {
            try rebuild(ticket, in: uncollated, skippedPages: [])
        }
    }

    // MARK: - Role boundaries

    func testOrdinaryQueueAndTicketRolesStillRejectFinishingProfileEight() throws {
        let context = try makeContext()
        let printerReference = context.queue.printerProfile
        XCTAssertEqual(printerReference.schemaVersion, 8)
        let workflowReference = context.queue.workflowProfile
        for version in 1...6 {
            XCTAssertThrowsError(try VirtualQueueDefinition(
                schemaVersion: version, id: "ordinary-queue", revision: 1,
                displayName: "Ordinary", physicalDevice: context.queue.physicalDevice,
                workflowProfile: workflowReference, printerProfile: printerReference,
                workflowDefaults: .init(thermalMethod: .directThermal, finishing: .tearOff),
                validatingAgainst: context.printer)) {
                    XCTAssertEqual($0 as? VirtualQueueError, .invalidDefaults)
                }
        }
        // The ordinary resolver and encoder remain closed to schema8 as well.
        XCTAssertThrowsError(try context.printer.resolveControls(job: .init())) {
            XCTAssertEqual($0 as? PrinterProfileError, .invalidProfileVersion)
        }
        let ticket = try accept(context)
        XCTAssertThrowsError(try ZPLControlEncoder().encode(ticket.controls))
        // An ordinary resolved ticket cannot carry a schema8 printer reference.
        XCTAssertThrowsError(try ResolvedJobTicket(
            schemaVersion: 7, acceptanceID: ticket.acceptanceID,
            cancellationSHA256: ticket.cancellationSHA256, activeSelectionGeneration: 1,
            queue: ImmutableProfileReference(id: "ordinary-queue", schemaVersion: 6,
                revision: 1, sha256: queueDigest),
            workflowProfile: workflowReference, printerProfile: printerReference,
            physicalDevice: ticket.physicalDevice,
            sourceDocumentSHA256: ticket.sourceDocumentSHA256, sourceByteCount: 4_096,
            sourcePageCount: 2, intakeProvenance: .cupsScheduler,
            copyOwnership: ticket.copyOwnership, pageRangeOwnership: ticket.pageRangeOwnership,
            transformOwnership: .workflowProfile,
            monochromeConversion: ticket.monochromeConversion, controls: ticket.controls,
            outputLabels: ticket.outputLabels, skippedPages: ticket.skippedPages)) {
                XCTAssertEqual($0 as? ResolvedJobTicketError, .invalidReference)
            }
    }

    func testFinishingAndOrdinaryRecordNamespacesNeverInterchange() throws {
        let context = try makeContext()
        let ticket = try accept(context)
        let bytes = try FinishingJobTicketJSON.encode(ticket)
        XCTAssertThrowsError(try ResolvedJobTicketJSON.queueReference(bytes))
        XCTAssertThrowsError(try VirtualQueueJSON.decode(bytes, validatingAgainst: context.printer))
        let policy = try FinishingQueueJSON.encode(context.queue)
        XCTAssertThrowsError(try FinishingJobTicketJSON.references(in: policy)) {
            XCTAssertEqual($0 as? FinishingJobTicketJSONError, .missingField("acceptanceID"))
        }
        XCTAssertThrowsError(try FinishingJobTicketJSON.decode(
            policy, queueReference: context.queueReference, queue: context.queue,
            device: context.device, workflow: context.workflow, printer: context.printer))
        // An ordinary profile cannot back a finishing device binding.
        XCTAssertThrowsError(try FinishingDeviceBinding(
            printerProfile: ImmutableProfileReference(id: "ordinary-printer", schemaVersion: 7,
                revision: 1, sha256: printerDigest),
            physicalDevice: context.queue.physicalDevice,
            nativePitch: .observed(DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8),
                                   evidence: .documentedModel(sourceID: "R26")),
            validatingPrinter: try PrinterProfile.gc420dUSBReference())) {
                XCTAssertEqual($0 as? FinishingJobTicketError, .ordinaryRoleRejected(7))
            }
        assertTicketError(.ordinaryRoleRejected(7)) {
            try rebuild(ticket, in: context, printerProfile:
                ImmutableProfileReference(id: "synthetic-printer", schemaVersion: 7,
                                          revision: context.printer.revision, sha256: printerDigest))
        }
    }

    // MARK: - Reference, device and pitch bindings

    func testEveryReferenceSubstitutionFailsClosed() throws {
        let context = try makeContext()
        let ticket = try accept(context)
        assertTicketError(.invalidQueueReference) {
            try rebuild(ticket, in: context, queue:
                FinishingQueuePolicyReference(id: "other-finishing", revision: 2, sha256: queueDigest))
        }
        assertTicketError(.invalidQueueReference) {
            try rebuild(ticket, in: context, queue:
                FinishingQueuePolicyReference(id: ticket.queue.id, revision: 3, sha256: queueDigest))
        }
        assertTicketError(.invalidWorkflowReference) {
            try rebuild(ticket, in: context, workflowProfile:
                ImmutableProfileReference(id: ticket.workflowProfile.id, schemaVersion: 2,
                    revision: ticket.workflowProfile.revision,
                    sha256: String(repeating: "9", count: 64)))
        }
        assertTicketError(.invalidPrinterReference) {
            try rebuild(ticket, in: context, printerProfile:
                ImmutableProfileReference(id: "synthetic-printer", schemaVersion: 8,
                    revision: ticket.printerProfile.revision,
                    sha256: String(repeating: "9", count: 64)))
        }
        assertTicketError(.invalidDeviceIdentity) {
            try rebuild(ticket, in: context, physicalDevice:
                PhysicalDeviceCoordinationID(sha256: String(repeating: "7", count: 64)))
        }
        // A different coordination domain cannot reuse the same queue policy.
        let otherDevice = try makeContext(deviceSHA256: String(repeating: "8", count: 64))
        assertTicketError(.invalidDeviceIdentity) {
            try rebuild(ticket, in: context, device: otherDevice.device)
        }
        // Same revision, different stored policy is still a snapshot change.
        assertTicketError(.snapshotMismatch) {
            try rebuild(ticket, in: context, printer: try printerProfile(maximumBatch: 4))
        }
        assertTicketError(.invalidImaging) {
            try rebuild(ticket, in: context, workflow: try workflowProfile(cutoff: 99))
        }
        assertTicketError(.invalidWorkflowReference) {
            try rebuild(ticket, in: context, workflow: try workflowProfile(revision: 4))
        }
    }

    func testQualifiedNativePitchProvenanceAndCanvasCannotBeInvented() throws {
        let context = try makeContext()
        let ticket = try accept(context)
        let printer = try printerProfile()
        let reference = context.queue.printerProfile
        let device = context.queue.physicalDevice
        for pitch in [Observation<DotResolution>.unobserved,
                      .observed(try DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8),
                                evidence: .unobserved)] {
            XCTAssertThrowsError(try FinishingDeviceBinding(printerProfile: reference,
                physicalDevice: device, nativePitch: pitch, validatingPrinter: printer)) {
                    XCTAssertEqual($0 as? FinishingJobTicketError, .unverifiedNativePitch)
                }
        }
        // Nominal203DPI is not the documented GC420d geometric truth.
        XCTAssertThrowsError(try FinishingDeviceBinding(printerProfile: reference,
            physicalDevice: device,
            nativePitch: .observed(try DotResolution(xDotsPerMillimeter: 203 / 25.4,
                                                     yDotsPerMillimeter: 203 / 25.4),
                                   evidence: .documentedModel(sourceID: "R26")),
            validatingPrinter: printer)) {
                XCTAssertEqual($0 as? FinishingJobTicketError, .modelPitchMismatch)
            }
        XCTAssertThrowsError(try FinishingDeviceBinding(printerProfile: reference,
            physicalDevice: device,
            nativePitch: .observed(try DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8),
                                   evidence: .documentedModel(sourceID: "../etc/passwd")),
            validatingPrinter: printer)) {
                XCTAssertEqual($0 as? FinishingJobTicketError, .invalidPitchProvenance)
            }
        // A non-GC420d model keeps its own evidenced pitch and canvas.
        let wide = try makeContext(
            pitch: .observed(try DotResolution(xDotsPerMillimeter: 12, yDotsPerMillimeter: 12),
                             evidence: .reportedInstallation),
            printer: try printerProfile(model: "synthetic-finishing"))
        let wideTicket = try accept(wide)
        XCTAssertEqual(wideTicket.canvas.width, 1219)
        XCTAssertEqual(wideTicket.canvas.height, 1829)
        assertTicketError(.unverifiedNativePitch) {
            try rebuild(ticket, in: context, nativePitch: wide.device.nativePitch)
        }
        assertTicketError(.canvasMismatch) {
            try rebuild(ticket, in: context, canvas: wideTicket.canvas)
        }
        // A workflow whose stock differs from the reported installed face fails.
        let mismatched = try WorkflowProfile(
            schemaVersion: 2, id: context.workflow.id, revision: context.workflow.revision,
            outputStockID: context.workflow.outputStockID,
            outputStock: PhysicalSize(width: try Millimeters.inches(3),
                                      height: try Millimeters.inches(6)),
            monochromeConversion: context.workflow.monochromeConversion,
            pageRules: context.workflow.pageRules)
        XCTAssertThrowsError(try context.device.canvas(for: context.queue, workflow: mismatched,
                                                       printer: context.printer))
    }

    // MARK: - Source, cancellation and intake

    func testSourceCancellationAndIntakeBoundsFailInsteadOfDefaulting() throws {
        let context = try makeContext()
        let ticket = try accept(context)
        assertTicketError(.invalidIdentity) {
            try rebuild(ticket, in: context, acceptanceID: "Finishing/Accepted")
        }
        assertTicketError(.invalidIdentity) {
            try rebuild(ticket, in: context, cancellation: String(repeating: "g", count: 64))
        }
        assertTicketError(.invalidSource) {
            try rebuild(ticket, in: context, sourceDocumentSHA256: String(repeating: "z", count: 64))
        }
        for count in [0, -1, ResolvedJobTicket.maximumSourceBytes + 1] {
            assertTicketError(.invalidSource) {
                try rebuild(ticket, in: context, sourceByteCount: count)
            }
        }
        assertTicketError(.invalidPlan) {
            try rebuild(ticket, in: context, sourcePageCount: 3)
        }
        assertTicketError(.invalidIntake) {
            try rebuild(ticket, in: context, intake: .cupsScheduler)
        }
        XCTAssertThrowsError(try accept(context, intake: .cupsScheduler)) {
            XCTAssertEqual($0 as? FinishingJobTicketError, .invalidIntake)
        }
    }

    // MARK: - Selection, controls and preparation

    func testSelectionAndEffectiveControlsCannotBeForgedOnLoad() throws {
        let context = try makeContext(defaults: .init(printSpeedIps: 3, darkness: 9))
        let ticket = try accept(context, explicitControls: .init(darkness: 0))
        XCTAssertEqual(ticket.controls.darkness, .value(0))
        XCTAssertEqual(try accept(context).controls.darkness, .value(9))
        assertTicketError(.selectionMismatch) {
            try rebuild(ticket, in: context, selection: .init(mode: .peel))
        }
        assertTicketError(.scheduleMismatch) {
            try rebuild(ticket, in: context,
                        selection: .init(mode: .cut, schedule: .endOfJob))
        }
        // A qualified alternative value re-resolves as an explicit job choice,
        // exactly like the ordinary ticket. Record integrity against the stored
        // bytes is the store's digest, not this re-resolution.
        let explicitChoice = ResolvedPrinterControls(
            profileSchemaVersion: ticket.controls.profileSchemaVersion,
            profileRevision: ticket.controls.profileRevision,
            thermalMethod: ticket.controls.thermalMethod, finishing: ticket.controls.finishing,
            printSpeedIps: .value(4), darkness: ticket.controls.darkness,
            tracking: ticket.controls.tracking, mediaGeometry: ticket.controls.mediaGeometry,
            offsets: ticket.controls.offsets)
        XCTAssertEqual(try rebuild(ticket, in: context, controls: explicitChoice).controls,
                       explicitChoice)
        let wrongRevision = ResolvedPrinterControls(
            profileSchemaVersion: 8, profileRevision: ticket.controls.profileRevision + 1,
            thermalMethod: ticket.controls.thermalMethod, finishing: ticket.controls.finishing,
            printSpeedIps: ticket.controls.printSpeedIps, darkness: ticket.controls.darkness,
            tracking: ticket.controls.tracking, mediaGeometry: ticket.controls.mediaGeometry,
            offsets: ticket.controls.offsets)
        assertTicketError(.invalidControls) { try rebuild(ticket, in: context, controls: wrongRevision) }
        let unsupported = ResolvedPrinterControls(
            profileSchemaVersion: 8, profileRevision: ticket.controls.profileRevision,
            thermalMethod: ticket.controls.thermalMethod, finishing: ticket.controls.finishing,
            printSpeedIps: .value(9), darkness: ticket.controls.darkness,
            tracking: ticket.controls.tracking, mediaGeometry: ticket.controls.mediaGeometry,
            offsets: ticket.controls.offsets)
        assertTicketError(.invalidControls) { try rebuild(ticket, in: context, controls: unsupported) }
        XCTAssertThrowsError(try accept(context, explicitControls: .init(finishing: .peel)))
        XCTAssertThrowsError(try accept(context, explicitControls: .init(printSpeedIps: 9)))
    }

    func testPreparationBindingRejectsEveryChangedField() throws {
        let context = try makeContext()
        let ticket = try accept(context)
        let base = ticket.preparationBinding
        XCTAssertNoThrow(try ticket.validate(preparation: base))
        let other = try accept(try makeContext(deviceSHA256: String(repeating: "8", count: 64)))
        let mutations: [(FinishingPreparationField, FinishingPreparationBinding)] = [
            (.acceptanceID, binding(base, acceptanceID: "finishing-other")),
            (.cancellation, binding(base, cancellation: String(repeating: "0", count: 64))),
            (.queue, binding(base, queue: try FinishingQueuePolicyReference(
                id: "other-finishing", revision: 2, sha256: queueDigest))),
            (.printerProfile, binding(base, printerProfile: try ImmutableProfileReference(
                id: "other-printer", schemaVersion: 8, revision: 11, sha256: printerDigest))),
            (.physicalDevice, binding(base, physicalDevice: other.physicalDevice)),
            (.canvas, binding(base, canvas: try DotCanvas(
                physicalSize: PhysicalSize(width: try Millimeters.inches(4),
                                           height: try Millimeters.inches(6)),
                resolution: try DotResolution(xDotsPerMillimeter: 12, yDotsPerMillimeter: 12)))),
            (.source, binding(base, sourceByteCount: base.sourceByteCount + 1)),
            (.outputOrder, binding(base, outputLabels: Array(base.outputLabels.dropLast()))),
            (.cutSchedule, binding(base, cutAfterOutputLabels: [4])),
        ]
        for (field, mutated) in mutations {
            XCTAssertThrowsError(try ticket.validate(preparation: mutated)) {
                XCTAssertEqual($0 as? FinishingJobTicketError, .preparationMismatch(field))
            }
        }
    }

    private func binding(
        _ base: FinishingPreparationBinding, acceptanceID: String? = nil,
        cancellation: String? = nil, queue: FinishingQueuePolicyReference? = nil,
        printerProfile: ImmutableProfileReference? = nil,
        physicalDevice: PhysicalDeviceCoordinationID? = nil, canvas: DotCanvas? = nil,
        controls: ResolvedPrinterControls? = nil, sourceByteCount: Int? = nil,
        outputLabels: [ResolvedOutputLabel]? = nil, cutAfterOutputLabels: [Int]? = nil
    ) -> FinishingPreparationBinding {
        FinishingPreparationBinding(
            acceptanceID: acceptanceID ?? base.acceptanceID,
            cancellationSHA256: cancellation ?? base.cancellationSHA256,
            queue: queue ?? base.queue, printerProfile: printerProfile ?? base.printerProfile,
            physicalDevice: physicalDevice ?? base.physicalDevice, canvas: canvas ?? base.canvas,
            controls: controls ?? base.controls,
            sourceDocumentSHA256: base.sourceDocumentSHA256,
            sourceByteCount: sourceByteCount ?? base.sourceByteCount,
            outputLabels: outputLabels ?? base.outputLabels,
            cutAfterOutputLabels: cutAfterOutputLabels ?? base.cutAfterOutputLabels)
    }

    // MARK: - Canonical record bytes

    func testCanonicalRecordRejectsDuplicateKeysAndAlternateEncodings() throws {
        let context = try makeContext()
        let ticket = try accept(context)
        let bytes = try FinishingJobTicketJSON.encode(ticket)
        let text = String(decoding: bytes, as: UTF8.self)
        func decode(_ data: Data) throws -> ResolvedFinishingJobTicket {
            try FinishingJobTicketJSON.decode(data, queueReference: context.queueReference,
                queue: context.queue, device: context.device, workflow: context.workflow,
                printer: context.printer)
        }
        XCTAssertThrowsError(try decode(Data(("{\"acceptanceID\":\"other\"," + text.dropFirst()).utf8)))
        XCTAssertThrowsError(try decode(bytes + Data([32])))
        XCTAssertThrowsError(try decode(Data(repeating: 32, count: FinishingJobTicketJSON.maximumBytes + 1))) {
            XCTAssertEqual($0 as? FinishingJobTicketJSONError, .inputTooLarge)
        }
        for (before, after) in [
            ("\"kind\":\"offlineFinishingJobTicket\"", "\"kind\":\"offlineFinishingQueue\""),
            ("\"schemaVersion\":1,", "\"schemaVersion\":2,"),
            ("\"widthDots\":813", "\"widthDots\":812"),
            ("\"heightDots\":1219", "\"heightDots\":true"),
            ("\"byteCount\":4096", "\"byteCount\":0"),
            ("\"intake\":\"offlineCLI\"", "\"intake\":\"cupsScheduler\""),
            ("\"evidence\":\"documentedModel\"", "\"evidence\":\"reportedInstallation\""),
            ("\"sourceID\":\"R26\"", "\"sourceID\":\"R27\""),
            ("\"cutAfterOutputLabels\":[3,4]", "\"cutAfterOutputLabels\":[3]"),
            ("\"mode\":\"cut\"", "\"mode\":\"peel\""),
            ("\"format\":\"application\\/pdf\"", "\"format\":\"application\\/zpl\""),
        ] {
            XCTAssertTrue(text.contains(before), before)
            XCTAssertThrowsError(try decode(Data(
                text.replacingOccurrences(of: before, with: after).utf8)), before)
        }
        // A record whose queue reference does not match the supplied one fails.
        XCTAssertThrowsError(try FinishingJobTicketJSON.decode(bytes,
            queueReference: try FinishingQueuePolicyReference(
                id: context.queueReference.id, revision: context.queueReference.revision,
                sha256: String(repeating: "1", count: 64)),
            queue: context.queue, device: context.device, workflow: context.workflow,
            printer: context.printer)) {
                XCTAssertEqual($0 as? FinishingJobTicketJSONError, .invalidValue("queue"))
            }
    }

    func testExactIntegerIdentityAcrossLargeFinishingTicketCounts() throws {
        let context = try makeContext()
        let ticket = try accept(context)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try FinishingJobTicketJSON.encode(ticket)) as? [String: Any])
        var source = try XCTUnwrap(root["source"] as? [String: Any])
        source["byteCount"] = 9_007_199_254_740_993
        root["source"] = source
        let bytes = try JSONSerialization.data(withJSONObject: root, options: .sortedKeys)
        XCTAssertThrowsError(try FinishingJobTicketJSON.decode(bytes,
            queueReference: context.queueReference, queue: context.queue,
            device: context.device, workflow: context.workflow, printer: context.printer)) {
                XCTAssertEqual($0 as? FinishingJobTicketError, .invalidSource)
            }
    }
}
