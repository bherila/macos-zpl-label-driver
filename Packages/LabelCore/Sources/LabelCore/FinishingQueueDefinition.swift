import Foundation

/// Explicit mechanical intention. Validation requires the bound profile's mode,
/// accessory, stock and schedule declarations; construction is not admission.
public struct FinishingQueueSelection: Equatable, Sendable {
    public let mode: FinishingMode
    public let schedule: CutSchedule?
    public init(mode: FinishingMode, schedule: CutSchedule? = nil) {
        self.mode = mode; self.schedule = schedule
    }
}

/// Offline queue policy in a distinct typed namespace. It is not an installed
/// VirtualQueueDefinition, accepted ticket or permission for device I/O. A store
/// must independently verify reference digests before trusting these values.
public struct FinishingQueueDefinition: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidIdentity, invalidReference, unverifiedStock, stockMismatch
        case defaultModeMismatch, selectionMismatch, snapshotMismatch
    }
    public let id: String
    public let revision: Int
    public let displayName: String
    public let physicalDevice: PhysicalDeviceCoordinationID
    public let workflowProfile: ImmutableProfileReference
    public let printerProfile: ImmutableProfileReference
    public let defaultSelection: FinishingQueueSelection
    public let workflowDefaults: PrinterControlDefaults
    private let workflowSnapshot: WorkflowProfile
    private let printerSnapshot: PrinterProfile

    public init(id: String, revision: Int, displayName: String,
                physicalDevice: PhysicalDeviceCoordinationID,
                workflowProfile: ImmutableProfileReference, printerProfile: ImmutableProfileReference,
                defaultSelection: FinishingQueueSelection, workflowDefaults: PrinterControlDefaults,
                validatingWorkflow workflow: WorkflowProfile, validatingPrinter printer: PrinterProfile) throws {
        guard VirtualQueueDefinition.isSelector(id), revision > 0,
              !displayName.isEmpty, displayName.utf8.count <= 128,
              displayName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw Error.invalidIdentity
        }
        guard workflowProfile.schemaVersion == 2, workflowProfile.id == workflow.id,
              workflowProfile.revision == workflow.revision, printerProfile.schemaVersion == 8,
              printer.schemaVersion == 8, printerProfile.revision == printer.revision else {
            throw Error.invalidReference
        }
        guard case let .observed(stock, evidence) = printer.media.nominalLabelFace,
              evidence == .reportedInstallation else { throw Error.unverifiedStock }
        guard stock == workflow.outputStock else { throw Error.stockMismatch }
        guard workflowDefaults.finishing == nil || workflowDefaults.finishing == defaultSelection.mode else {
            throw Error.defaultModeMismatch
        }
        self.id = id; self.revision = revision; self.displayName = displayName
        self.physicalDevice = physicalDevice; self.workflowProfile = workflowProfile
        self.printerProfile = printerProfile; self.defaultSelection = defaultSelection
        self.workflowDefaults = workflowDefaults
        workflowSnapshot = workflow; printerSnapshot = printer
        // Check default policy and every effective control combination before a
        // queue intention can be retained. Actual ordered output count is later.
        _ = try resolve(outputLabelCount: 1, workflow: workflow, printer: printer)
    }

    /// Resolves one complete engine-expanded count without expanding copies or
    /// changing order. Selection overrides explicitly replace the whole mode/
    /// schedule pair, so a cut schedule never leaks into a peel/tear-off override.
    public func resolve(outputLabelCount: Int, workflow: WorkflowProfile, printer: PrinterProfile,
                        selection: FinishingQueueSelection? = nil,
                        job: PrinterControlRequest = .init()) throws -> (plan: FinishingJobPlan, controls: ResolvedPrinterControls) {
        guard workflow == workflowSnapshot, printer == printerSnapshot else { throw Error.snapshotMismatch }
        let selected = selection ?? defaultSelection
        guard job.finishing == nil || job.finishing == selected.mode else { throw Error.selectionMismatch }
        guard let configuration = printer.finishingConfiguration else { throw Error.invalidReference }
        let plan = try FinishingJobPlan(mode: selected.mode, outputLabelCount: outputLabelCount,
            media: printer.media, stock: configuration.stock, finishing: configuration.finishing,
            schedule: selected.schedule, scheduleQualification: configuration.schedules)
        var effectiveJob = job
        // The explicit selection owns finishing; all other fields retain the
        // shared job/workflow/configured precedence, including explicit zero.
        effectiveJob.finishing = selected.mode
        let controls = try printer.resolveFinishingControls(plan: plan, job: effectiveJob,
                                                           workflowDefaults: workflowDefaults)
        return (plan, controls)
    }
}
