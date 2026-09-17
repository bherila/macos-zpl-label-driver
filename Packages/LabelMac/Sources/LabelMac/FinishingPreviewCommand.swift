import Foundation

/// Offline packed-preview export, with no printer payload or send authority.
public struct FinishingPreviewCommand: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable { case usage }
    public let inspection: FinishingInspectionCommand
    public let destination: URL
    public init(arguments: [String]) throws {
        guard arguments.count <= 9 else { throw Error.usage }
        var remaining = arguments, output: String?
        if let index = remaining.firstIndex(of: "--preview-dir") {
            guard index + 1 < remaining.count else { throw Error.usage }
            output = remaining[index + 1]; remaining.removeSubrange(index...(index+1))
        }
        guard let output, !output.isEmpty, output.utf8.count <= 4096,
              !remaining.contains("--preview-dir") else { throw Error.usage }
        do { inspection = try FinishingInspectionCommand(arguments: remaining) }
        catch { throw Error.usage }
        destination = URL(fileURLWithPath: output, isDirectory: true)
    }
    public func run(workerExecutable: URL, cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Data {
        let start = DispatchTime.now().uptimeNanoseconds
        func remaining() throws -> Double {
            guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
            let value = 60 - Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000_000
            guard value > 0 else { throw AcceptedFinishingJob.Error.timedOut }; return value
        }
        // Inspection enforces existing private catalog identity and exposes no
        // permission to deliver. Preparation then uses only its exact reference.
        _ = try inspection.report(workerExecutable: workerExecutable, cancellation: cancellation)
        let root = inspection.root
        let prepared = try AcceptedFinishingJobStore(root: root).prepare(reference: inspection.reference,
            queueStore: FinishingQueueStore(root: root), workflowStore: WorkflowProfileStore(root: root),
            printerStore: PrinterProfileStore(root: root), workerExecutable: workerExecutable,
            deadlineSeconds: remaining(), cancellation: cancellation)
        try PackedFinishingPreviewExport.write(prepared,toNewDirectory: destination,
            deadlineSeconds: remaining(), cancellation: cancellation)
        return try JSONSerialization.data(withJSONObject:["status":"exported", "kind":"packed-preview",
            "acceptedRecordSHA256":prepared.reference.sha256,"outputLabelCount":prepared.preparation.rasters.count,
            "hardwareCompletion":"unknown","automaticReplayAuthorized":false],options:[.sortedKeys])
    }
}
