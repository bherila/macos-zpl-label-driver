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
        try run(workerExecutable: workerExecutable, deadline: FinishingDeadline(cancellation: cancellation))
    }
    /// One budget governs inspection, preparation and export. Inspection enforces
    /// existing private catalog identity and exposes no permission to deliver;
    /// preparation then reuses only its exact verified reference and bytes, so
    /// the accepted original PDF is analyzed once rather than four times.
    public func run(workerExecutable: URL, deadline: FinishingDeadline) throws -> Data {
        let inspected = try inspection.observe(workerExecutable: workerExecutable, deadline: deadline)
        let prepared = try AcceptedFinishingJobStore(root: inspection.root).prepare(validated: inspected.context,
            workerExecutable: workerExecutable, deadline: deadline)
        try PackedFinishingPreviewExport.write(prepared, toNewDirectory: destination, deadline: deadline)
        return try JSONSerialization.data(withJSONObject:["status":"exported", "kind":"packed-preview",
            "acceptedRecordSHA256":prepared.reference.sha256,"outputLabelCount":prepared.preparation.rasters.count,
            "hardwareCompletion":"unknown","automaticReplayAuthorized":false],options:[.sortedKeys])
    }
}
