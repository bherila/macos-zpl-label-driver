import Combine
import Foundation

public struct FinishingInspectionSummary: Decodable, Equatable, Sendable {
    public let outputLabelCount: Int
    public let canvasWidthDots: Int
    public let canvasHeightDots: Int
    public let localIntent: String
    public let cancellationRequested: Bool
    public let hardwareCompletion: String
    public let automaticReplayAuthorized: Bool
}

/// User-session inspection/export only; stale requests cannot publish UI state.
@MainActor
public final class FinishingInspectionModel: ObservableObject {
    @Published public private(set) var summary: FinishingInspectionSummary?
    @Published public private(set) var isBusy = false
    @Published public private(set) var status: String?
    private var selected: SelectedAcceptedFinishingRecord?
    private var request: UUID?
    private var cancellation: OfflineRenderWorkerCancellation?
    private let inspect: @Sendable (URL, OfflineRenderWorkerCancellation) throws -> (SelectedAcceptedFinishingRecord, FinishingInspectionSummary)
    private let export: @Sendable (SelectedAcceptedFinishingRecord, URL, OfflineRenderWorkerCancellation) throws -> Void

    public init(workerExecutable: URL) {
        inspect = { file, cancellation in
            let selected = try AcceptedFinishingJobStore.selectedRecord(at: file)
            let command = try FinishingInspectionCommand(arguments: ["--catalog", selected.catalogRoot.path,
                "--accepted-id", selected.reference.acceptanceID, "--accepted-sha", selected.reference.sha256])
            let report = try command.report(workerExecutable: workerExecutable, cancellation: cancellation)
            let summary = try JSONDecoder().decode(FinishingInspectionSummary.self, from: report)
            return (selected, summary)
        }
        export = { selected, destination, cancellation in
            let command = try FinishingPreviewCommand(arguments: ["--catalog", selected.catalogRoot.path,
                "--accepted-id", selected.reference.acceptanceID, "--accepted-sha", selected.reference.sha256,
                "--preview-dir", destination.path])
            _ = try command.run(workerExecutable: workerExecutable, cancellation: cancellation)
        }
    }
    init(inspect: @escaping @Sendable (URL, OfflineRenderWorkerCancellation) throws -> (SelectedAcceptedFinishingRecord, FinishingInspectionSummary),
         export: @escaping @Sendable (SelectedAcceptedFinishingRecord, URL, OfflineRenderWorkerCancellation) throws -> Void) {
        self.inspect = inspect; self.export = export
    }
    public func cancel() {
        cancellation?.cancel(); cancellation = nil; request = nil; isBusy = false
        status = String(localized: "Operation cancelled. Existing exported files are preserved.")
    }
    /// A chooser failure is not a verified selection. Invalidate pending work and
    /// discard the previous export authority without displaying private error data.
    public func selectionFailed() {
        cancel(); selected = nil; summary = nil
        status = String(localized: "Saved job could not be opened. Choose the file again. No printer action was taken.")
    }
    public func open(_ file: URL) async {
        cancel(); selected = nil; summary = nil; status = nil
        let token = UUID(), cancellation = OfflineRenderWorkerCancellation()
        self.request = token; self.cancellation = cancellation; isBusy = true
        defer { if request == token { request = nil; self.cancellation = nil; isBusy = false } }
        let inspect = self.inspect
        let operation = Task.detached { try inspect(file, cancellation) }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await operation.value }, onCancel: { cancellation.cancel(); operation.cancel() })
            try Task.checkCancellation()
            guard request == token else { return }
            selected = result.0; summary = result.1
            status = String(localized: "Saved job verified. Hardware completion is unknown.")
        } catch {
            guard request == token else { return }
            status = String(localized: "Saved job could not be verified. No printer action was taken.")
        }
    }
    public func exportPreviews(toNewDirectory destination: URL) async {
        guard !isBusy, let selected else { return }
        let token = UUID(), cancellation = OfflineRenderWorkerCancellation()
        request = token; self.cancellation = cancellation; isBusy = true; status = nil
        defer { if request == token { request = nil; self.cancellation = nil; isBusy = false } }
        let export = self.export
        let operation = Task.detached { try export(selected, destination, cancellation) }
        do {
            try await withTaskCancellationHandler(operation: { try await operation.value }, onCancel: { cancellation.cancel(); operation.cancel() })
            try Task.checkCancellation()
            guard request == token else { return }
            status = String(localized: "Exact packed previews exported. Nothing was printed.")
        } catch {
            guard request == token else { return }
            if error as? PackedFinishingPreviewExport.Error == .commitUncertain {
                status = String(localized: "Export durability is uncertain. Preserve the output and review it before retrying.")
            } else {
                status = String(localized: "Preview export did not complete. Existing output is preserved.")
            }
        }
    }
}
