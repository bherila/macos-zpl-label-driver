import Combine
import Foundation
import LabelCore

/// User-session editor intake only. No scheduler, printer or privilege API.
@MainActor
public final class WorkflowDocumentOpeningModel: ObservableObject {
    @Published public private(set) var editor: WorkflowEditorModel?
    @Published public private(set) var error: String?
    @Published public private(set) var isOpening = false
    @Published public private(set) var savedWorkflows: [WorkflowProfileStore.CatalogEntry] = []
    @Published public private(set) var savedWorkflowError: String?
    @Published public private(set) var isRefreshingSavedWorkflows = false
    @Published public private(set) var isTransferringProfile = false
    @Published public private(set) var profileTransferStatus: String?
    @Published public private(set) var uncertainImportedProfile: WorkflowProfile?

    private var catalogRequest: UUID?

    private let store: WorkflowProfileStore
    private let workerExecutable: URL
    private let afterAnalysis: @Sendable () async -> Void
    private var request: UUID?
    private var cancellation: OfflineRenderWorkerCancellation?
    private var task: Task<Void, Never>?
    var currentOpeningTask: Task<Void, Never>? { task }

    public init(store: WorkflowProfileStore, workerExecutable: URL) {
        self.store = store
        self.workerExecutable = workerExecutable
        afterAnalysis = {}
    }

    init(store: WorkflowProfileStore, workerExecutable: URL,
         afterAnalysis: @escaping @Sendable () async -> Void) {
        self.store = store
        self.workerExecutable = workerExecutable
        self.afterAnalysis = afterAnalysis
    }

    public func cancelOpening() {
        cancellation?.cancel()
        task?.cancel()
        cancellation = nil
        task = nil
        request = nil
        isOpening = false
    }

    public func reportImportFailure() { error = "The PDF could not be opened." }

    public func importProfileDefinition(_ url: URL) async {
        guard !isTransferringProfile, uncertainImportedProfile == nil else { return }
        isTransferringProfile = true
        profileTransferStatus = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
            isTransferringProfile = false
        }
        do {
            let profile = try await Task.detached { try WorkflowProfileTransfer.readImport(url) }.value
            try Task.checkCancellation()
            await publishImportedProfile(profile)
        } catch is CancellationError {
            profileTransferStatus = "Import cancelled before publication."
        } catch {
            profileTransferStatus = "Workflow import failed. The current editor and earlier workflows were kept."
        }
    }

    public func reconcileProfileImport() async {
        guard !isTransferringProfile, let candidate = uncertainImportedProfile else { return }
        isTransferringProfile = true
        defer { isTransferringProfile = false }
        await publishImportedProfile(candidate)
    }

    private func publishImportedProfile(_ profile: WorkflowProfile) async {
        let store = self.store
        do {
            // Once publication is admitted, finishing/reporting its outcome is
            // safer than interpreting task cancellation as evidence of absence.
            try await Task.detached { try store.save(profile) }.value
            uncertainImportedProfile = nil
            profileTransferStatus = "Imported as a new local workflow without unattended approval. Open with an original PDF to review."
            await refreshSavedWorkflows()
        } catch WorkflowProfileStore.Error.commitUncertain {
            uncertainImportedProfile = profile
            profileTransferStatus = "Import may be visible, but its durability is unconfirmed. Reconcile Import checks this exact candidate and its publication barrier; do not create a new import."
        } catch WorkflowProfileStore.Error.catalogCapacityReached {
            profileTransferStatus = "The workflow catalog is full. No new revision was published; earlier workflows and the current editor were kept."
        } catch WorkflowProfileStore.Error.publicationBusy {
            profileTransferStatus = "Another workflow publication is in progress. No new revision was published by this attempt. Retry explicitly after it finishes."
        } catch {
            profileTransferStatus = uncertainImportedProfile == nil
                ? "Workflow import failed. The current editor and earlier workflows were kept."
                : "Import reconciliation failed. The exact candidate was retained; no new import was created."
        }
    }

    public func prepareProfileExport(_ snapshot: WorkflowProfile) async -> WorkflowProfileExportDocument? {
        guard !isTransferringProfile else { return nil }
        isTransferringProfile = true
        profileTransferStatus = nil
        defer { isTransferringProfile = false }
        do {
            let store = self.store
            let data = try await Task.detached { try WorkflowProfileTransfer.exportSnapshot(snapshot, store: store) }.value
            try Task.checkCancellation()
            return WorkflowProfileExportDocument(verifiedCanonicalDefinition: data)
        } catch {
            profileTransferStatus = "The selected saved revision could not be verified for export. Nothing was exported."
            return nil
        }
    }

    public func reportProfileTransferFailure() { profileTransferStatus = "Workflow file transfer did not complete." }
    public func reportProfileExportCompletion() { profileTransferStatus = "Workflow definition exported. Review identifiers and layout settings before sharing." }

    public func refreshSavedWorkflows() async {
        let id = UUID()
        catalogRequest = id
        isRefreshingSavedWorkflows = true
        savedWorkflowError = nil
        defer {
            if catalogRequest == id { catalogRequest = nil; isRefreshingSavedWorkflows = false }
        }
        let store = self.store
        do {
            let entries = try await Task.detached { try store.savedWorkflows() }.value
            guard catalogRequest == id, !Task.isCancelled else { return }
            savedWorkflows = entries
        } catch {
            guard catalogRequest == id, !Task.isCancelled else { return }
            savedWorkflowError = "Saved workflows could not be listed. Nothing was removed."
        }
    }

    public func open(_ url: URL, mode: WorkflowOpeningMode = .assisted) {
        beginOpening(url, mode: mode, savedProfile: nil)
    }

    public func openSavedWorkflow(_ url: URL, profile: WorkflowProfile) {
        beginOpening(url, mode: .manual, savedProfile: profile)
    }

    private func beginOpening(_ url: URL, mode: WorkflowOpeningMode, savedProfile: WorkflowProfile?) {
        cancelOpening()
        editor?.cancelPreview()
        editor?.cancelSourcePreview()
        error = nil
        let id = UUID()
        let cancellation = OfflineRenderWorkerCancellation()
        request = id
        self.cancellation = cancellation
        isOpening = true
        task = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let start = clock.now
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
                if self.request == id {
                    self.request = nil
                    self.cancellation = nil
                    self.task = nil
                    self.isOpening = false
                }
            }
            do {
                try Task.checkCancellation()
                let store = self.store
                let data = try await withTaskCancellationHandler {
                    try await Task.detached {
                        if let savedProfile {
                            let stored = try store.load(profileID: savedProfile.id, revision: savedProfile.revision)
                            guard stored == savedProfile else { throw WorkflowProfileStore.Error.profileConflict }
                        }
                        return try BoundedRegularFile.read(url, maximumBytes: 100 * 1024 * 1024)
                    }.value
                } onCancel: {
                    cancellation.cancel()
                }
                try Task.checkCancellation()
                let elapsed = start.duration(to: clock.now).components
                let remaining = 60 - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18
                guard remaining > 0 else { throw OfflineRenderWorkerProcess.Error.timedOut }
                let model = try await WorkflowEditorBootstrap.makeModelUsingWorker(
                    originalPDF: data, store: self.store, workerExecutable: self.workerExecutable,
                    deadlineSeconds: min(remaining, 60), cancellation: cancellation, mode: mode,
                    savedProfile: savedProfile)
                await self.afterAnalysis()
                guard self.request == id, !Task.isCancelled, !cancellation.isCancelled else { return }
                guard clock.now < start.advanced(by: .seconds(60)) else {
                    throw OfflineRenderWorkerProcess.Error.timedOut
                }
                self.editor = model
            } catch {
                guard self.request == id else { return }
                if !Task.isCancelled && !cancellation.isCancelled {
                    switch error {
                    case is ExtractionPlanError:
                        self.error = "This PDF does not match the saved workflow's pages or layout. The current draft was kept."
                    case is WorkflowProfileStore.Error, is WorkflowProfileJSONError:
                        self.error = "The saved workflow changed or could not be verified. Refresh the saved workflow list."
                    case WorkflowEditorBootstrap.Error.unsupportedPageGeometry:
                        self.error = "Unsupported page size. Use native 4×6, Letter or A4 input."
                    case WorkflowEditorBootstrap.Error.unsupportedOutputStock:
                        self.error = "This saved workflow uses different output stock. The current setup is 4×6 tear-off."
                    case WorkflowEditorBootstrap.Error.unsupportedLayoutDetector:
                        self.error = "This saved workflow requires a layout detector unavailable in this build. The current draft was kept."
                    case WorkflowEditorBootstrap.Error.ambiguousBorderCandidates:
                        self.error = "Competing label regions require a manual extraction workflow."
                    case WorkflowEditorBootstrap.Error.noBorderCandidate:
                        self.error = "No label border found. A manual extraction workflow is required."
                    case WorkflowEditorBootstrap.Error.mixedReferenceGeometry:
                        self.error = "Mixed page sizes require a page-specific workflow."
                    case OfflineRenderWorkerProcess.Error.timedOut:
                        self.error = "PDF preparation exceeded its time limit."
                    default:
                        self.reportImportFailure()
                    }
                }
            }
        }
    }
}
