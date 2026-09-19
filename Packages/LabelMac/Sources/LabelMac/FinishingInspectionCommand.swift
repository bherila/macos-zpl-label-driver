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
    /// The verified inspection result. Its context is reusable by the remaining
    /// steps of the same command and is not delivery or replay authority.
    public struct Inspection: Sendable {
        public let json: Data
        public let context: ValidatedAcceptedFinishingContext
        public let recovery: AcceptedFinishingRecovery
    }
    public func report(workerExecutable: URL, cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Data {
        try observe(workerExecutable: workerExecutable, deadline: FinishingDeadline(cancellation: cancellation)).json
    }
    /// One caller-supplied budget governs every step, so a command that also
    /// prepares and exports does not run a second independent sixty-second clock.
    public func observe(workerExecutable: URL, deadline: FinishingDeadline) throws -> Inspection {
        let before = try catalogIdentity()
        let accepted = try AcceptedFinishingJobStore(root: root)
        let context = try accepted.validatedContext(reference: reference, queueStore: FinishingQueueStore(root: root),
            workflowStore: WorkflowProfileStore(root: root), printerStore: PrinterProfileStore(root: root),
            workerExecutable: workerExecutable, deadline: deadline)
        let recovery = try AcceptedFinishingRecovery.inspect(validated: context,
            attemptStore: AcceptedFinishingAttemptStore(root: root),
            cancellationStore: AcceptedFinishingCancellationStore(root: root), deadline: deadline)
        let requested: Bool, intent: String
        switch recovery.observation {
        case let .noRecordedIntent(value): requested = value; intent = "no-recorded-intent"
        case let .uncertainAfterRecordedIntent(value): requested = value; intent = "uncertain-after-recorded-intent"
        }
        try deadline.check()
        guard try catalogIdentity() == before else { throw Error.catalogChanged }
        let job = context.job
        let result: [String:Any] = ["status":"observed", "schemaVersion":1,
            "acceptedRecordSHA256":reference.sha256, "sourceSHA256":job.sourceSHA256,
            "sourceByteCount":job.originalPDF.count, "outputLabelCount":job.extraction.outputLabels.count,
            "canvasWidthDots":job.canvas.width, "canvasHeightDots":job.canvas.height,
            "localIntent":intent, "cancellationRequested":requested,
            "hardwareCompletion":"unknown", "automaticReplayAuthorized":false]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        return Inspection(json: json, context: context, recovery: recovery)
    }
    private struct Identity: Equatable { let device: dev_t, inode: ino_t }
    private func catalogIdentity() throws -> Identity {
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else { throw Error.catalogUnavailable }
        return Identity(device:info.st_dev,inode:info.st_ino)
    }
}
