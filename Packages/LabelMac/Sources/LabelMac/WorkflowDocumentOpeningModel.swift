import Combine
import Foundation

/// User-session editor intake only. No scheduler, printer or privilege API.
@MainActor
public final class WorkflowDocumentOpeningModel: ObservableObject {
    @Published public private(set) var editor: WorkflowEditorModel?
    @Published public private(set) var error: String?
    @Published public private(set) var isOpening = false

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

    public func open(_ url: URL, mode: WorkflowOpeningMode = .assisted) {
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
                let data = try await withTaskCancellationHandler {
                    try await Task.detached {
                        try BoundedRegularFile.read(url, maximumBytes: 100 * 1024 * 1024)
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
                    deadlineSeconds: min(remaining, 60), cancellation: cancellation, mode: mode)
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
                    case WorkflowEditorBootstrap.Error.unsupportedPageGeometry:
                        self.error = "Unsupported page size. Use native 4×6, Letter or A4 input."
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
