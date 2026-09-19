import CryptoKit
import Darwin
import Foundation
import LabelCore

public struct AcceptedFinishingReference: Equatable, Sendable, RedactedDiagnosticValue {
    public let acceptanceID: String
    public let sha256: String
    public init(acceptanceID: String, sha256: String) throws {
        _ = try ImmutableProfileReference(id: acceptanceID, revision: 1, sha256: sha256)
        self.acceptanceID = acceptanceID; self.sha256 = sha256
    }
}

/// One verified reopen of an accepted record, reusable by the remaining steps of
/// the same command so its original PDF is analyzed once instead of four times.
/// Construction is available only through the store's own verified load path; it
/// is not device delivery, replay, cancellation or completion authority.
public struct ValidatedAcceptedFinishingContext: Equatable, Sendable {
    public let catalogRoot: URL
    public let reference: AcceptedFinishingReference
    public let job: AcceptedFinishingJob
    fileprivate init(catalogRoot: URL, reference: AcceptedFinishingReference, job: AcceptedFinishingJob) {
        self.catalogRoot = catalogRoot; self.reference = reference; self.job = job
    }
    /// In-process binding only. It records which catalog root produced this
    /// context and is not a fresh filesystem identity or ancestry attestation.
    func bound(to root: URL) -> Bool {
        catalogRoot.standardizedFileURL.path == root.standardizedFileURL.path
    }
}

/// One immutable bounded binary transaction contains manifest and original PDF.
/// Reopen reconstructs through original-source acceptance and verifies the complete
/// recorded context. It does not authorize device delivery or clear attempt intent.
public struct AcceptedFinishingJobStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidRecord, referenceMismatch, contextMismatch, conflict, cannotRead, cannotWrite
        case unsafeStore, capacityReached, publicationBusy, commitUncertain(AcceptedFinishingReference)
    }
    public static let maximumMetadataBytes = 16 * 1024 * 1024
    public static let maximumBytes = maximumMetadataBytes + ResolvedJobTicket.maximumSourceBytes + 16
    public let root: URL
    private let storage: PrivateImmutableDirectory
    private static let magic = Data("AFJOB001".utf8)
    public init(root: URL) throws {
        self.root = root
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Self.map(error) }
    }
    init(root: URL, storage: PrivateImmutableDirectory) { self.root = root; self.storage = storage }

    @discardableResult
    public func save(_ job: AcceptedFinishingJob) throws -> AcceptedFinishingReference {
        let metadata = try Self.json(Manifest(job))
        guard metadata.count <= Self.maximumMetadataBytes else { throw Error.invalidRecord }
        var bytes = Self.magic
        let length = UInt64(metadata.count)
        for shift in stride(from: 0, through: 56, by: 8) { bytes.append(UInt8(truncatingIfNeeded: length >> shift)) }
        bytes.append(metadata); bytes.append(job.originalPDF)
        guard bytes.count <= Self.maximumBytes else { throw Error.invalidRecord }
        let ref = try AcceptedFinishingReference(acceptanceID: job.acceptanceID, sha256: Self.hash(bytes))
        do {
            try storage.publish(bytes, directory: "accepted-finishing-jobs", fileName: Self.fileName(ref),
                maximumBytes: Self.maximumBytes, maximumRecords: 4, recordFormat: .binary)
        } catch PrivateImmutableDirectory.Error.commitUncertain { throw Error.commitUncertain(ref) }
        catch { throw Self.map(error) }
        return ref
    }

    public func load(reference: AcceptedFinishingReference, queueStore: FinishingQueueStore,
                     workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore,
                     workerExecutable: URL,
                     deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                     cancellation: OfflineRenderWorkerCancellation = .init()) throws -> AcceptedFinishingJob {
        guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
        guard deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else { throw AcceptedFinishingJob.Error.invalidLimit }
        let start = DispatchTime.now().uptimeNanoseconds
        let bytes: Data
        do { bytes = try storage.read(directory: "accepted-finishing-jobs", fileName: Self.fileName(reference), maximumBytes: Self.maximumBytes) }
        catch { throw Self.map(error) }
        guard Self.hash(bytes) == reference.sha256 else { throw Error.referenceMismatch }
        let (manifest, boundary) = try Self.parseRecord(bytes)
        guard manifest.acceptanceID == reference.acceptanceID else { throw Error.invalidRecord }
        let printer = try printerStore.load(id: manifest.printerID, revision: manifest.printerRevision)
        guard printer.reference.sha256 == manifest.printerSHA256 else { throw Error.referenceMismatch }
        let geometry = try FinishingDeviceGeometry(printer: printer,
            physicalDevice: .init(sha256: manifest.deviceSHA256), nativePitch: manifest.pitch())
        let remaining = deadlineSeconds - Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        guard remaining > 0 else { throw AcceptedFinishingJob.Error.timedOut }
        let job = try AcceptedFinishingJob.accept(acceptanceID: manifest.acceptanceID,
            cancellationSHA256: manifest.cancellationSHA256,
            queueReference: .init(id: manifest.queueID, revision: manifest.queueRevision, sha256: manifest.queueSHA256),
            queueStore: queueStore, workflowStore: workflowStore, printerStore: printerStore,
            geometry: geometry, originalPDF: bytes.subdata(in: boundary..<bytes.count),
            copyOwnership: manifest.copies(), pageRangeOwnership: manifest.pages.map { .engine(selectedSourcePages: $0) } ?? .upstreamAlreadyApplied,
            selection: manifest.selection(), controls: manifest.request.value(), workerExecutable: workerExecutable,
            deadlineSeconds: remaining, cancellation: cancellation)
        guard try Self.context(job) == manifest.context else { throw Error.contextMismatch }
        guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
        guard Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000 < deadlineSeconds else { throw AcceptedFinishingJob.Error.timedOut }
        return job
    }

    /// Reopen once under the command's shared budget and keep the verified
    /// context, so later steps observe recovery state and render without
    /// re-deriving the extraction plan from the same original PDF.
    public func validatedContext(reference: AcceptedFinishingReference, queueStore: FinishingQueueStore,
                                 workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore,
                                 workerExecutable: URL,
                                 deadline: FinishingDeadline) throws -> ValidatedAcceptedFinishingContext {
        let job = try load(reference: reference, queueStore: queueStore, workflowStore: workflowStore,
            printerStore: printerStore, workerExecutable: workerExecutable,
            deadlineSeconds: deadline.remaining(), cancellation: deadline.cancellation)
        try deadline.check()
        return ValidatedAcceptedFinishingContext(catalogRoot: root, reference: reference, job: job)
    }

    private static func parseRecord(_ bytes: Data) throws -> (Manifest, Int) {
        guard bytes.count >= 16, bytes.prefix(8) == magic else { throw Error.invalidRecord }
        var length: UInt64 = 0
        for (i, byte) in bytes[8..<16].enumerated() { length |= UInt64(byte) << (i * 8) }
        guard length <= UInt64(maximumMetadataBytes), length <= UInt64(bytes.count - 16) else { throw Error.invalidRecord }
        let boundary = 16 + Int(length)
        let sourceCount = bytes.count - boundary
        guard (1...ResolvedJobTicket.maximumSourceBytes).contains(sourceCount) else { throw Error.invalidRecord }
        let metadata = bytes.subdata(in: 16..<boundary)
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: metadata) }
        catch { throw Error.invalidRecord }
        guard try json(manifest) == metadata, manifest.version == 1 else { throw Error.invalidRecord }
        return (manifest, boundary)
    }

    static func fileName(_ ref: AcceptedFinishingReference) -> String { "\(hash(Data(ref.acceptanceID.utf8))).bin" }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private static func context(_ job: AcceptedFinishingJob) throws -> Data {
        let normalization = try ZPLControlEncoder().prepareFinishingNormalization(profile: job.geometry.printer.profile,
            plan: job.job.plan, job: job.controlRequest, workflowDefaults: job.queueDefinition.workflowDefaults)
        let labels: [[String: Any]] = job.extraction.outputLabels.map { label in
            ["page": label.sourcePage, "region": label.regionID, "regionIndex": label.regionIndex,
             "normalized": [label.normalizedRect.x, label.normalizedRect.y, label.normalizedRect.width, label.normalizedRect.height],
             "source": [label.sourceRect.x, label.sourceRect.y, label.sourceRect.width, label.sourceRect.height],
             "rotation": label.rotation.rawValue, "scaling": label.scalePolicy.rawValue,
             "stockID": label.outputStockID, "stock": [label.outputStock.width.value, label.outputStock.height.value],
             "profileID": label.profileID, "profileRevision": label.profileRevision]
        }
        let object: [String: Any] = ["sourceHash": job.sourceSHA256, "sourceBytes": job.originalPDF.count,
            "sourcePages": job.extraction.sourcePageCount, "labels": labels,
            "skipped": job.extraction.skippedPages.map { ["page": $0.sourcePage, "reason": $0.reason.rawValue] as [String: Any] },
            "queue": try FinishingQueueJSON.encode(job.queueDefinition).base64EncodedString(),
            "workflow": try WorkflowProfileJSON.encode(job.workflow).base64EncodedString(),
            "printer": try PrinterProfileJSON.encode(job.geometry.printer.profile).base64EncodedString(),
            "canvas": [job.canvas.width, job.canvas.height], "prefix": normalization.bytes.base64EncodedString(),
            "cuts": job.job.plan.cutAfterOutputLabels, "mode": job.job.plan.mode.rawValue]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private static func map(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .conflict: .conflict
        case .recordCapacityReached: .capacityReached
        case .publicationBusy: .publicationBusy
        case .cannotRead, .notFound: .cannotRead
        case .cannotWrite, .commitUncertain: .cannotWrite
        case .cannotCreate, .cannotOpen, .unsafeDirectory, .none: .unsafeStore
        }
    }

    private struct Manifest: Codable {
        let version: Int
        let acceptanceID, cancellationSHA256, queueID, queueSHA256, printerID, printerSHA256, deviceSHA256: String
        let queueRevision, printerRevision: Int
        let pitchX, pitchY: Double
        let pitchEvidence: String
        let pitchSource: String?
        let copyCount: Int?
        let collated: Bool?
        let pages: [Int]?
        let mode: String
        let schedule: String?
        let batchSize: Int?
        let remainder: Bool?
        let request: Request
        let context: Data
        init(_ job: AcceptedFinishingJob) throws {
            version = 1; acceptanceID = job.acceptanceID; cancellationSHA256 = job.cancellationSHA256
            queueID = job.queueReference.id; queueRevision = job.queueReference.revision; queueSHA256 = job.queueReference.sha256
            printerID = job.geometry.printer.reference.id; printerRevision = job.geometry.printer.reference.revision
            printerSHA256 = job.geometry.printer.reference.sha256; deviceSHA256 = job.geometry.physicalDevice.sha256
            pitchX = job.geometry.resolution.xDotsPerMillimeter; pitchY = job.geometry.resolution.yDotsPerMillimeter
            guard case let .observed(_, evidence) = job.geometry.nativePitch else { throw Error.invalidRecord }
            switch evidence {
            case let .documentedModel(sourceID): pitchEvidence = "documented"; pitchSource = sourceID
            case .reportedInstallation: pitchEvidence = "reported"; pitchSource = nil
            case .unobserved: throw Error.invalidRecord
            }
            switch job.copyOwnership {
            case let .engine(n, c): copyCount = n; collated = c
            case .upstreamAlreadyExpanded: copyCount = nil; collated = nil
            }
            switch job.pageRangeOwnership {
            case let .engine(selected): pages = selected
            case .upstreamAlreadyApplied: pages = nil
            }
            mode = job.job.plan.mode.rawValue
            switch job.job.plan.schedule {
            case .none: schedule = nil; batchSize = nil; remainder = nil
            case .everyLabel: schedule = "everyLabel"; batchSize = nil; remainder = nil
            case .endOfJob: schedule = "endOfJob"; batchSize = nil; remainder = nil
            case let .batch(n, r): schedule = "batch"; batchSize = n; remainder = r
            }
            request = Request(job.controlRequest); context = try AcceptedFinishingJobStore.context(job)
        }
        func pitch() throws -> Observation<DotResolution> {
            let pitch = try DotResolution(xDotsPerMillimeter: pitchX, yDotsPerMillimeter: pitchY)
            if pitchEvidence == "documented", let pitchSource { return .observed(pitch, evidence: .documentedModel(sourceID: pitchSource)) }
            if pitchEvidence == "reported", pitchSource == nil { return .observed(pitch, evidence: .reportedInstallation) }
            throw Error.invalidRecord
        }
        func copies() throws -> JobCopyOwnership {
            if let copyCount, let collated { return .engine(copies: copyCount, collated: collated) }
            guard copyCount == nil, collated == nil else { throw Error.invalidRecord }; return .upstreamAlreadyExpanded
        }
        func selection() throws -> FinishingQueueSelection {
            guard let mode = FinishingMode(rawValue: mode) else { throw Error.invalidRecord }
            let cut: CutSchedule?
            switch schedule {
            case nil: guard batchSize == nil, remainder == nil else { throw Error.invalidRecord }; cut = nil
            case "everyLabel": guard batchSize == nil, remainder == nil else { throw Error.invalidRecord }; cut = .everyLabel
            case "endOfJob": guard batchSize == nil, remainder == nil else { throw Error.invalidRecord }; cut = .endOfJob
            case "batch": guard let batchSize, let remainder else { throw Error.invalidRecord }; cut = .batch(size: batchSize, cutRemainderAtJobEnd: remainder)
            default: throw Error.invalidRecord
            }
            return .init(mode: mode, schedule: cut)
        }
    }
    private struct Request: Codable {
        let thermal, finishing, tracking: String?
        let printSpeed, feedSpeed, backfeedSpeed, darkness: Int?
        let geometry, offsets: [Int?]?
        init(_ value: PrinterControlRequest) {
            thermal = value.thermalMethod?.rawValue; finishing = value.finishing?.rawValue; tracking = value.tracking?.rawValue
            printSpeed = value.printSpeedIps; feedSpeed = value.feedSpeedIps; backfeedSpeed = value.backfeedSpeedIps; darkness = value.darkness
            geometry = value.mediaGeometry.map { [$0.widthDots, $0.lengthDots, $0.originXDot, $0.originYDot] }
            offsets = value.offsets.map { [$0.blackMarkOffsetDots, $0.shiftLeftDots, $0.labelTopDots] }
        }
        func value() throws -> PrinterControlRequest {
            func decode<T: RawRepresentable>(_ raw: String?, _ type: T.Type) throws -> T? where T.RawValue == String {
                guard let raw else { return nil }; guard let value = T(rawValue: raw) else { throw Error.invalidRecord }; return value
            }
            let g: MediaGeometryRequest?
            if let geometry { guard geometry.count == 4 else { throw Error.invalidRecord }; g = try .init(widthDots: geometry[0], lengthDots: geometry[1], originXDot: geometry[2], originYDot: geometry[3]) } else { g = nil }
            let o: OffsetControlRequest?
            if let offsets { guard offsets.count == 3 else { throw Error.invalidRecord }; o = .init(blackMarkOffsetDots: offsets[0], shiftLeftDots: offsets[1], labelTopDots: offsets[2]) } else { o = nil }
            return try .init(thermalMethod: decode(thermal, ThermalMethod.self), finishing: decode(finishing, FinishingMode.self),
                printSpeedIps: printSpeed, feedSpeedIps: feedSpeed, backfeedSpeedIps: backfeedSpeed, darkness: darkness,
                tracking: decode(tracking, MediaTracking.self), mediaGeometry: g, offsets: o)
        }
    }
}

/// A lookup result, not accepted context or delivery permission.
public struct SelectedAcceptedFinishingRecord: Equatable, Sendable {
    public let catalogRoot: URL
    public let reference: AcceptedFinishingReference
    fileprivate init(catalogRoot: URL, reference: AcceptedFinishingReference) {
        self.catalogRoot = catalogRoot; self.reference = reference
    }
}

public extension AcceptedFinishingJobStore {
    /// Full store reopen must follow selection before displaying validated state.
    static func selectedRecord(at file: URL) throws -> SelectedAcceptedFinishingRecord {
        guard file.isFileURL, file.deletingLastPathComponent().lastPathComponent == "accepted-finishing-jobs" else { throw Error.invalidRecord }
        let root = file.deletingLastPathComponent().deletingLastPathComponent()
        var before = stat()
        guard lstat(root.path, &before) == 0, before.st_mode & S_IFMT == S_IFDIR,
              before.st_uid == getuid(), before.st_mode & 0o777 == 0o700 else { throw Error.unsafeStore }
        let store = try Self(root: root)
        let bytes: Data
        do {
            bytes = try store.storage.read(directory: "accepted-finishing-jobs", fileName: file.lastPathComponent,
                maximumBytes: maximumBytes, createDirectoryIfMissing: false)
        } catch { throw Self.map(error) }
        let (manifest, _) = try parseRecord(bytes)
        let reference = try AcceptedFinishingReference(acceptanceID: manifest.acceptanceID, sha256: hash(bytes))
        guard file.lastPathComponent == fileName(reference) else { throw Error.referenceMismatch }
        var after = stat()
        guard lstat(root.path, &after) == 0, before.st_dev == after.st_dev,
              before.st_ino == after.st_ino, before.st_uid == after.st_uid,
              before.st_mode == after.st_mode else { throw Error.unsafeStore }
        return SelectedAcceptedFinishingRecord(catalogRoot: root, reference: reference)
    }
}
