import Darwin
import Foundation

/// Bounded offline inspection. This command publishes no job, intent, or
/// cancellation record and grants no device delivery or replay authority.
public struct FinishingInspectionCommand: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable { case usage, catalogUnavailable, catalogChanged }
    public let root: URL
    public let reference: AcceptedFinishingReference
    public let json: Bool
    public init(arguments: [String]) throws {
        guard arguments.count <= 7 else { throw Error.usage }
        var options: [String:String] = [:], json = false, index = 0
        while index < arguments.count {
            let key = arguments[index]
            if key == "--json" {
                guard !json else { throw Error.usage }; json = true; index += 1; continue
            }
            guard ["--catalog", "--accepted-id", "--accepted-sha"].contains(key), options[key] == nil,
                  index + 1 < arguments.count, !arguments[index + 1].isEmpty,
                  arguments[index + 1].utf8.count <= 4096 else { throw Error.usage }
            options[key] = arguments[index + 1]; index += 2
        }
        guard let path = options["--catalog"], let id = options["--accepted-id"], let sha = options["--accepted-sha"] else { throw Error.usage }
        do { reference = try AcceptedFinishingReference(acceptanceID: id, sha256: sha) }
        catch { throw Error.usage }
        root = URL(fileURLWithPath: path, isDirectory: true); self.json = json
    }
    public func report(workerExecutable: URL, cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Data {
        let start = DispatchTime.now().uptimeNanoseconds
        let before = try catalogIdentity()
        let queues = try FinishingQueueStore(root: root), workflows = try WorkflowProfileStore(root: root)
        let printers = try PrinterProfileStore(root: root), accepted = try AcceptedFinishingJobStore(root: root)
        func remaining() throws -> Double {
            guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
            let value = 60 - Double(DispatchTime.now().uptimeNanoseconds-start) / 1_000_000_000
            guard value > 0 else { throw AcceptedFinishingJob.Error.timedOut }; return value
        }
        let job = try accepted.load(reference: reference, queueStore: queues, workflowStore: workflows,
            printerStore: printers, workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
        let recovery = try AcceptedFinishingRecovery.inspect(reference: reference, against: job,
            attemptStore: AcceptedFinishingAttemptStore(root: root), cancellationStore: AcceptedFinishingCancellationStore(root: root),
            queueStore: queues, workflowStore: workflows, printerStore: printers, workerExecutable: workerExecutable,
            deadlineSeconds: remaining(), cancellation: cancellation)
        let requested: Bool, intent: String
        switch recovery.observation {
        case let .noRecordedIntent(value): requested = value; intent = "no-recorded-intent"
        case let .uncertainAfterRecordedIntent(value): requested = value; intent = "uncertain-after-recorded-intent"
        }
        _ = try remaining()
        guard try catalogIdentity() == before else { throw Error.catalogChanged }
        let result: [String:Any] = ["status":"observed", "schemaVersion":1,
            "acceptedRecordSHA256":reference.sha256, "sourceSHA256":job.sourceSHA256,
            "sourceByteCount":job.originalPDF.count, "outputLabelCount":job.extraction.outputLabels.count,
            "canvasWidthDots":job.canvas.width, "canvasHeightDots":job.canvas.height,
            "localIntent":intent, "cancellationRequested":requested,
            "hardwareCompletion":"unknown", "automaticReplayAuthorized":false]
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }
    private struct Identity: Equatable { let device: dev_t, inode: ino_t }
    private func catalogIdentity() throws -> Identity {
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else { throw Error.catalogUnavailable }
        return Identity(device:info.st_dev,inode:info.st_ino)
    }
}
