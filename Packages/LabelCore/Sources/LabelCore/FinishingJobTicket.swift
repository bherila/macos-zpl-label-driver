import Foundation

/// Which bound preparation field disagreed with the accepted finishing ticket.
/// Preparation never replaces an accepted value; a disagreement is an error.
public enum FinishingPreparationField: String, Equatable, Sendable {
    case acceptanceID
    case cancellation
    case queue
    case printerProfile
    case physicalDevice
    case canvas
    case controls
    case source
    case outputOrder
    case cutSchedule
}

/// Distinct typed failures for the offline finishing admission role. No case is
/// reachable by clamping, defaulting or silently coercing a rejected value, and
/// an unknown declaration is never treated as supported, zero or completed.
public enum FinishingJobTicketError: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidQueueReference
    case invalidWorkflowReference
    case invalidPrinterReference
    /// The finishing role refuses an ordinary printer-profile schema, and the
    /// ordinary role separately refuses schema8. Neither direction is widened.
    case ordinaryRoleRejected(Int)
    case invalidDeviceIdentity
    case unverifiedNativePitch
    case invalidPitchProvenance
    case modelPitchMismatch
    case canvasMismatch
    case stockMismatch
    /// A complete workflow or printer snapshot no longer reproduces the bound
    /// queue policy, even when its identifier and revision are unchanged.
    case snapshotMismatch
    case selectionMismatch
    case scheduleMismatch
    case invalidSource
    case invalidIntake
    case invalidPlan
    case invalidCopyOwnership
    case invalidControls
    case invalidImaging
    case preparationMismatch(FinishingPreparationField)
}

/// Separate offline finishing-policy reference. It is deliberately a different
/// type from `ImmutableProfileReference` so an ordinary queue, workflow or
/// printer reference cannot be substituted in the finishing queue slot.
public struct FinishingQueuePolicyReference: Equatable, Sendable {
    public let id: String
    public let revision: Int
    public let sha256: String

    public init(id: String, revision: Int, sha256: String) throws {
        guard VirtualQueueDefinition.isSelector(id), revision > 0,
              VirtualQueueDefinition.isSHA256(sha256) else {
            throw FinishingJobTicketError.invalidQueueReference
        }
        self.id = id
        self.revision = revision
        self.sha256 = sha256
    }
}

/// Portable device identity plus explicitly evidenced native pitch. Documentary
/// model facts and a reported installation are retained distinctly; neither
/// proves a discovered unit, physical qualification or transmission authority.
/// Canonical reference-digest verification stays the store's responsibility.
public struct FinishingDeviceBinding: Equatable, Sendable {
    public let printerProfile: ImmutableProfileReference
    public let physicalDevice: PhysicalDeviceCoordinationID
    public let nativePitch: Observation<DotResolution>
    public let resolution: DotResolution

    public init(printerProfile: ImmutableProfileReference,
                physicalDevice: PhysicalDeviceCoordinationID,
                nativePitch: Observation<DotResolution>,
                validatingPrinter printer: PrinterProfile) throws {
        guard printerProfile.schemaVersion == 8 else {
            throw FinishingJobTicketError.ordinaryRoleRejected(printerProfile.schemaVersion)
        }
        guard printer.schemaVersion == 8, printerProfile.revision == printer.revision,
              printer.finishingConfiguration != nil else {
            throw FinishingJobTicketError.invalidPrinterReference
        }
        guard case let .observed(resolution, evidence) = nativePitch, evidence != .unobserved else {
            throw FinishingJobTicketError.unverifiedNativePitch
        }
        if case let .documentedModel(sourceID) = evidence {
            guard Self.isDocumentedSource(sourceID) else {
                throw FinishingJobTicketError.invalidPitchProvenance
            }
        }
        // Model-documented native pitch is the geometric truth; the nominal
        // integer203DPI shorthand never substitutes for documented8dots/mm.
        if printer.capabilities.model == "GC420d" {
            guard resolution.xDotsPerMillimeter == 8, resolution.yDotsPerMillimeter == 8 else {
                throw FinishingJobTicketError.modelPitchMismatch
            }
        }
        self.printerProfile = printerProfile
        self.physicalDevice = physicalDevice
        self.nativePitch = nativePitch
        self.resolution = resolution
    }

    /// Rebuilds the exact output canvas from the queue's bound printer/device
    /// identity, the complete snapshots and the reported nominal stock. It
    /// allocates nothing and is not evidence of a printable physical region.
    public func canvas(for queue: FinishingQueueDefinition, workflow: WorkflowProfile,
                       printer: PrinterProfile,
                       maximumPackedBytes: Int = FinishingDeviceBinding.maximumPackedBytes) throws -> DotCanvas {
        guard queue.printerProfile == printerProfile else {
            throw FinishingJobTicketError.invalidPrinterReference
        }
        guard queue.physicalDevice == physicalDevice else {
            throw FinishingJobTicketError.invalidDeviceIdentity
        }
        guard printer.schemaVersion == 8, printer.revision == printerProfile.revision else {
            throw FinishingJobTicketError.invalidPrinterReference
        }
        // Also revalidates the complete workflow/printer snapshots, the
        // qualified defaults and one whole mode/schedule selection.
        _ = try queue.resolve(outputLabelCount: 1, workflow: workflow, printer: printer)
        guard case let .observed(stock, evidence) = printer.media.nominalLabelFace,
              evidence == .reportedInstallation, stock == workflow.outputStock else {
            throw FinishingJobTicketError.stockMismatch
        }
        guard (1...Self.maximumPackedBytes).contains(maximumPackedBytes) else {
            throw FinishingJobTicketError.canvasMismatch
        }
        return try DotCanvas(physicalSize: stock, resolution: resolution,
                             maximumByteCount: maximumPackedBytes)
    }

    public static let maximumPackedBytes = 512 * 1024 * 1024

    var pitchEvidence: CapabilityEvidence {
        if case let .observed(_, evidence) = nativePitch { return evidence }
        return .unobserved
    }

    private static func isDocumentedSource(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        func alphanumeric(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        guard let first = bytes.first, alphanumeric(first), bytes.count <= 128 else { return false }
        return bytes.allSatisfy { alphanumeric($0) || [45, 46, 95].contains($0) }
    }
}

/// The exact accepted context a later raster preparation must retain. It is a
/// comparison value only: it carries no bytes, transport, lease or authority.
public struct FinishingPreparationBinding: Equatable, Sendable {
    public let acceptanceID: String
    public let cancellationSHA256: String
    public let queue: FinishingQueuePolicyReference
    public let printerProfile: ImmutableProfileReference
    public let physicalDevice: PhysicalDeviceCoordinationID
    public let canvas: DotCanvas
    public let controls: ResolvedPrinterControls
    public let sourceDocumentSHA256: String
    public let sourceByteCount: Int
    public let outputLabels: [ResolvedOutputLabel]
    public let cutAfterOutputLabels: [Int]

    public init(acceptanceID: String, cancellationSHA256: String,
                queue: FinishingQueuePolicyReference, printerProfile: ImmutableProfileReference,
                physicalDevice: PhysicalDeviceCoordinationID, canvas: DotCanvas,
                controls: ResolvedPrinterControls, sourceDocumentSHA256: String,
                sourceByteCount: Int, outputLabels: [ResolvedOutputLabel],
                cutAfterOutputLabels: [Int]) {
        self.acceptanceID = acceptanceID
        self.cancellationSHA256 = cancellationSHA256
        self.queue = queue
        self.printerProfile = printerProfile
        self.physicalDevice = physicalDevice
        self.canvas = canvas
        self.controls = controls
        self.sourceDocumentSHA256 = sourceDocumentSHA256
        self.sourceByteCount = sourceByteCount
        self.outputLabels = outputLabels
        self.cutAfterOutputLabels = cutAfterOutputLabels
    }
}

/// Immutable offline finishing admission. It binds the finishing queue policy,
/// the workflow and schema8 printer revisions, the coordination domain, the
/// evidenced native pitch and its canvas, the whole mode/schedule selection,
/// the complete expanded output order, the original source and the
/// cancellation identity. It is not an installed queue, scheduler acceptance,
/// hardware receipt or authority to transmit anything to a device.
public struct ResolvedFinishingJobTicket: Equatable, Sendable {
    public static let schemaVersion = 1

    public let acceptanceID: String
    public let cancellationSHA256: String
    public let queue: FinishingQueuePolicyReference
    public let workflowProfile: ImmutableProfileReference
    public let printerProfile: ImmutableProfileReference
    public let physicalDevice: PhysicalDeviceCoordinationID
    public let nativePitch: Observation<DotResolution>
    public let canvas: DotCanvas
    public let selection: FinishingQueueSelection
    public let cutAfterOutputLabels: [Int]
    public let sourceDocumentSHA256: String
    public let sourceByteCount: Int
    public let sourcePageCount: Int
    public let intakeProvenance: JobIntakeProvenance
    public let copyOwnership: JobCopyOwnership
    public let pageRangeOwnership: JobPageRangeOwnership
    public let transformOwnership: JobTransformOwnership
    public let monochromeConversion: MonochromeConversion
    public let controls: ResolvedPrinterControls
    public let outputLabels: [ResolvedOutputLabel]
    public let skippedPages: [ResolvedSkippedPage]

    /// Accepts an already validated extraction plan for the finishing role.
    /// Copies and page ranges keep their single declared owner; this layer
    /// never expands, reorders or discards labels.
    public static func accept(
        acceptanceID: String,
        cancellationSHA256: String,
        queueReference: FinishingQueuePolicyReference,
        queueDefinition: FinishingQueueDefinition,
        device: FinishingDeviceBinding,
        workflow: WorkflowProfile,
        printer: PrinterProfile,
        sourceDocumentSHA256: String,
        sourceByteCount: Int,
        intakeProvenance: JobIntakeProvenance = .offlineCLI,
        plan: ExtractionPlan,
        copyOwnership: JobCopyOwnership,
        pageRangeOwnership: JobPageRangeOwnership,
        selection: FinishingQueueSelection? = nil,
        explicitControls: PrinterControlRequest = .init()
    ) throws -> ResolvedFinishingJobTicket {
        do {
            try validatePlan(plan, workflowProfile: workflow, copyOwnership: copyOwnership,
                             pageRangeOwnership: pageRangeOwnership)
        } catch { throw Self.mapPlan(error) }
        let selected = selection ?? queueDefinition.defaultSelection
        let outputLabels = plan.outputLabels.map {
            ResolvedOutputLabel(sourcePage: $0.sourcePage, regionID: $0.regionID)
        }
        guard !outputLabels.isEmpty, outputLabels.count <= ResolvedJobTicket.maximumOutputLabels else {
            throw FinishingJobTicketError.invalidPlan
        }
        let resolved: (plan: FinishingJobPlan, controls: ResolvedPrinterControls)
        do {
            resolved = try queueDefinition.resolve(outputLabelCount: outputLabels.count,
                workflow: workflow, printer: printer, selection: selected, job: explicitControls)
        } catch { throw Self.mapResolution(error) }
        return try ResolvedFinishingJobTicket(
            acceptanceID: acceptanceID,
            cancellationSHA256: cancellationSHA256,
            queue: queueReference,
            workflowProfile: queueDefinition.workflowProfile,
            printerProfile: queueDefinition.printerProfile,
            physicalDevice: queueDefinition.physicalDevice,
            nativePitch: device.nativePitch,
            canvas: device.canvas(for: queueDefinition, workflow: workflow, printer: printer),
            selection: selected,
            cutAfterOutputLabels: resolved.plan.cutAfterOutputLabels,
            sourceDocumentSHA256: sourceDocumentSHA256,
            sourceByteCount: sourceByteCount,
            sourcePageCount: plan.sourcePageCount,
            intakeProvenance: intakeProvenance,
            copyOwnership: copyOwnership,
            pageRangeOwnership: pageRangeOwnership,
            transformOwnership: .workflowProfile,
            monochromeConversion: workflow.monochromeConversion,
            controls: resolved.controls,
            outputLabels: outputLabels,
            skippedPages: plan.skippedPages.map {
                ResolvedSkippedPage(sourcePage: $0.sourcePage, reason: $0.reason)
            },
            queueDefinition: queueDefinition,
            device: device,
            workflow: workflow,
            printer: printer
        )
    }

    /// One validation path for construction and for decoding a stored record.
    /// Every reference, the device identity, the qualified pitch, the whole
    /// mode/schedule selection, the expanded order and the effective controls
    /// are rechecked against the supplied immutable context.
    init(
        acceptanceID: String,
        cancellationSHA256: String,
        queue: FinishingQueuePolicyReference,
        workflowProfile: ImmutableProfileReference,
        printerProfile: ImmutableProfileReference,
        physicalDevice: PhysicalDeviceCoordinationID,
        nativePitch: Observation<DotResolution>,
        canvas: DotCanvas,
        selection: FinishingQueueSelection,
        cutAfterOutputLabels: [Int],
        sourceDocumentSHA256: String,
        sourceByteCount: Int,
        sourcePageCount: Int,
        intakeProvenance: JobIntakeProvenance,
        copyOwnership: JobCopyOwnership,
        pageRangeOwnership: JobPageRangeOwnership,
        transformOwnership: JobTransformOwnership,
        monochromeConversion: MonochromeConversion,
        controls: ResolvedPrinterControls,
        outputLabels: [ResolvedOutputLabel],
        skippedPages: [ResolvedSkippedPage],
        queueDefinition: FinishingQueueDefinition,
        device: FinishingDeviceBinding,
        workflow: WorkflowProfile,
        printer: PrinterProfile
    ) throws {
        guard VirtualQueueDefinition.isSelector(acceptanceID),
              VirtualQueueDefinition.isSHA256(cancellationSHA256) else {
            throw FinishingJobTicketError.invalidIdentity
        }
        guard queue.id == queueDefinition.id, queue.revision == queueDefinition.revision else {
            throw FinishingJobTicketError.invalidQueueReference
        }
        guard workflowProfile == queueDefinition.workflowProfile,
              (2...3).contains(workflowProfile.schemaVersion),
              workflowProfile.schemaVersion == workflow.schemaVersion,
              workflowProfile.id == workflow.id,
              workflowProfile.revision == workflow.revision else {
            throw FinishingJobTicketError.invalidWorkflowReference
        }
        guard printerProfile.schemaVersion == 8 else {
            throw FinishingJobTicketError.ordinaryRoleRejected(printerProfile.schemaVersion)
        }
        guard printerProfile == queueDefinition.printerProfile,
              printerProfile == device.printerProfile,
              printer.schemaVersion == 8, printer.revision == printerProfile.revision else {
            throw FinishingJobTicketError.invalidPrinterReference
        }
        guard physicalDevice == queueDefinition.physicalDevice,
              physicalDevice == device.physicalDevice else {
            throw FinishingJobTicketError.invalidDeviceIdentity
        }
        guard nativePitch == device.nativePitch else {
            throw FinishingJobTicketError.unverifiedNativePitch
        }
        // Offline finishing intake only. Installed scheduler admission is a
        // separate contract and cannot be claimed by a stored provenance value.
        guard intakeProvenance == .offlineCLI else { throw FinishingJobTicketError.invalidIntake }
        guard transformOwnership == .workflowProfile else { throw FinishingJobTicketError.invalidPlan }
        guard monochromeConversion == workflow.monochromeConversion else {
            throw FinishingJobTicketError.invalidImaging
        }
        guard VirtualQueueDefinition.isSHA256(sourceDocumentSHA256),
              (1...ResolvedJobTicket.maximumSourceBytes).contains(sourceByteCount),
              (1...ResolvedJobTicket.maximumSourcePages).contains(sourcePageCount) else {
            throw FinishingJobTicketError.invalidSource
        }
        guard !outputLabels.isEmpty,
              outputLabels.count <= ResolvedJobTicket.maximumOutputLabels else {
            throw FinishingJobTicketError.invalidPlan
        }
        do {
            try validatePlanMapping(
                sourcePageCount: sourcePageCount, outputLabels: outputLabels,
                skippedPages: skippedPages, workflowProfile: workflow,
                copyOwnership: copyOwnership, pageRangeOwnership: pageRangeOwnership
            )
        } catch { throw Self.mapPlan(error) }
        let expectedCanvas: DotCanvas
        do { expectedCanvas = try device.canvas(for: queueDefinition, workflow: workflow, printer: printer) }
        catch { throw Self.mapResolution(error) }
        guard canvas == expectedCanvas else { throw FinishingJobTicketError.canvasMismatch }
        let resolved: (plan: FinishingJobPlan, controls: ResolvedPrinterControls)
        do {
            resolved = try queueDefinition.resolve(
                outputLabelCount: outputLabels.count, workflow: workflow, printer: printer,
                selection: selection, job: ResolvedJobTicketJSON.controlRequest(controls))
        } catch { throw Self.mapResolution(error) }
        guard resolved.plan.mode == selection.mode, resolved.plan.schedule == selection.schedule else {
            throw FinishingJobTicketError.selectionMismatch
        }
        guard resolved.plan.cutAfterOutputLabels == cutAfterOutputLabels else {
            throw FinishingJobTicketError.scheduleMismatch
        }
        guard resolved.controls == controls, controls.profileSchemaVersion == 8,
              controls.profileRevision == printerProfile.revision else {
            throw FinishingJobTicketError.invalidControls
        }
        self.acceptanceID = acceptanceID
        self.cancellationSHA256 = cancellationSHA256
        self.queue = queue
        self.workflowProfile = workflowProfile
        self.printerProfile = printerProfile
        self.physicalDevice = physicalDevice
        self.nativePitch = nativePitch
        self.canvas = canvas
        self.selection = selection
        self.cutAfterOutputLabels = cutAfterOutputLabels
        self.sourceDocumentSHA256 = sourceDocumentSHA256
        self.sourceByteCount = sourceByteCount
        self.sourcePageCount = sourcePageCount
        self.intakeProvenance = intakeProvenance
        self.copyOwnership = copyOwnership
        self.pageRangeOwnership = pageRangeOwnership
        self.transformOwnership = transformOwnership
        self.monochromeConversion = monochromeConversion
        self.controls = controls
        self.outputLabels = outputLabels
        self.skippedPages = skippedPages
    }

    /// The exact context a later preparation must reproduce.
    public var preparationBinding: FinishingPreparationBinding {
        FinishingPreparationBinding(
            acceptanceID: acceptanceID, cancellationSHA256: cancellationSHA256,
            queue: queue, printerProfile: printerProfile, physicalDevice: physicalDevice,
            canvas: canvas, controls: controls, sourceDocumentSHA256: sourceDocumentSHA256,
            sourceByteCount: sourceByteCount, outputLabels: outputLabels,
            cutAfterOutputLabels: cutAfterOutputLabels
        )
    }

    /// Fails closed on the first disagreeing field, naming it. A preparation
    /// result never replaces, reorders or defaults an accepted value.
    public func validate(preparation: FinishingPreparationBinding) throws {
        let expected = preparationBinding
        let checks: [(FinishingPreparationField, Bool)] = [
            (.acceptanceID, preparation.acceptanceID == expected.acceptanceID),
            (.cancellation, preparation.cancellationSHA256 == expected.cancellationSHA256),
            (.queue, preparation.queue == expected.queue),
            (.printerProfile, preparation.printerProfile == expected.printerProfile),
            (.physicalDevice, preparation.physicalDevice == expected.physicalDevice),
            (.canvas, preparation.canvas == expected.canvas),
            (.controls, preparation.controls == expected.controls),
            (.source, preparation.sourceDocumentSHA256 == expected.sourceDocumentSHA256
                && preparation.sourceByteCount == expected.sourceByteCount),
            (.outputOrder, preparation.outputLabels == expected.outputLabels),
            (.cutSchedule, preparation.cutAfterOutputLabels == expected.cutAfterOutputLabels),
        ]
        for (field, satisfied) in checks where !satisfied {
            throw FinishingJobTicketError.preparationMismatch(field)
        }
    }

    /// Keeps a queue-policy rejection distinct from an unsupported control, so
    /// no failure is reported as a generic or clamped value.
    private static func mapResolution(_ error: Swift.Error) -> FinishingJobTicketError {
        if let error = error as? FinishingJobTicketError { return error }
        switch error as? FinishingQueueDefinition.Error {
        case .selectionMismatch: return .selectionMismatch
        case .snapshotMismatch: return .snapshotMismatch
        case .stockMismatch, .unverifiedStock: return .stockMismatch
        case .invalidReference: return .invalidPrinterReference
        case .invalidIdentity, .defaultModeMismatch, .none: return .invalidControls
        }
    }

    private static func mapPlan(_ error: Swift.Error) -> FinishingJobTicketError {
        switch error as? ResolvedJobTicketError {
        case .invalidCopyOwnership: .invalidCopyOwnership
        default: .invalidPlan
        }
    }
}
