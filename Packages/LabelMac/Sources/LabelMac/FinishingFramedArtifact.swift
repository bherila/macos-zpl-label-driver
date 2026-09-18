import CryptoKit
import Foundation
import LabelCore

/// Versioned archive of exact context and ordered files/status requirements.
/// Reopening requires independently reconstructed immutable context. No decoder
/// manufactures a job, status receipt, accepted ticket or replay authority.
public struct FinishingFramedArtifact: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimit, byteLimit, invalidMetadata, bindingMismatch, cancelled, timedOut
    }
    public static let maximumBytes = 96 * 1024 * 1024
    public let bytes: Data
    public let sha256: String

    public static func encode(_ output: FinishingFramedOutput, maximumBytes: Int = Self.maximumBytes,
                              deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                              cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Self {
        guard (1...Self.maximumBytes).contains(maximumBytes), deadlineSeconds.isFinite,
              deadlineSeconds > 0, deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else {
            throw Error.invalidLimit
        }
        let started = DispatchTime.now().uptimeNanoseconds
        func check() throws {
            guard !cancellation.isCancelled else { throw Error.cancelled }
            guard Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000 < deadlineSeconds else {
                throw Error.timedOut
            }
        }
        var data = Data()
        func append(_ bytes: Data) throws {
            try check()
            guard bytes.count <= maximumBytes - data.count else { throw Error.byteLimit }
            data.append(bytes)
        }
        func scalar(_ value: UInt64) throws {
            var little = value.littleEndian
            try withUnsafeBytes(of: &little) { try append(Data($0)) }
        }
        func integer(_ value: Int) throws {
            guard value >= 0 else { throw Error.invalidMetadata }
            try scalar(UInt64(value))
        }
        func blob(_ value: Data) throws { try integer(value.count); try append(value) }
        func string(_ value: String) throws {
            guard value.utf8.count <= 32 * 1024 else { throw Error.invalidMetadata }
            try blob(Data(value.utf8))
        }
        func real(_ value: Double) throws {
            guard value.isFinite else { throw Error.invalidMetadata }
            // Preserve explicit IEEE-754 geometry rather than decimal rounding.
            try scalar(value.bitPattern)
        }
        func evidence(_ value: CapabilityEvidence) throws {
            switch value {
            case let .documentedModel(id): try integer(1); try string(id)
            case .reportedInstallation: try integer(2)
            case .unobserved: try integer(0)
            }
        }
        try append(Data("label-finishing-framed-artifact-v1\0".utf8))
        let p = output.preparation, job = p.binding.job, ref = job.printer.reference
        try string(ref.id); try integer(ref.schemaVersion); try integer(ref.revision); try string(ref.sha256)
        try blob(PrinterProfileJSON.encode(job.printer.profile))
        try string(p.sourceSHA256); try integer(p.sourceByteCount)
        let extraction = p.extraction
        try integer(extraction.sourcePageCount); try string(extraction.profileID); try integer(extraction.profileRevision)
        try integer(extraction.outputLabels.count)
        for label in extraction.outputLabels {
            try integer(label.sourcePage); try integer(label.regionIndex); try string(label.regionID)
            for v in [label.normalizedRect.x, label.normalizedRect.y, label.normalizedRect.width,
                      label.normalizedRect.height, label.sourceRect.x, label.sourceRect.y,
                      label.sourceRect.width, label.sourceRect.height] { try real(v) }
            try integer(label.rotation.rawValue); try string(label.scalePolicy.rawValue)
            try string(label.outputStockID); try real(label.outputStock.width.value); try real(label.outputStock.height.value)
            try string(label.profileID); try integer(label.profileRevision)
        }
        try integer(extraction.skippedPages.count)
        for page in extraction.skippedPages { try integer(page.sourcePage); try string(page.reason.rawValue) }
        try real(p.canvas.physicalSize.width.value); try real(p.canvas.physicalSize.height.value)
        try real(p.canvas.resolution.xDotsPerMillimeter); try real(p.canvas.resolution.yDotsPerMillimeter)
        try integer(p.canvas.width); try integer(p.canvas.height)
        switch p.conversion {
        case let .textAndBarcodeThreshold(cutoff): try integer(0); try integer(Int(cutoff))
        case .photographicOrderedDither4x4: try integer(1)
        }
        try string(p.binding.orderedRasterSHA256); try integer(p.binding.totalPackedBytes)
        try string(job.plan.mode.rawValue); try integer(job.plan.outputLabelCount)
        switch job.plan.schedule {
        case nil: try integer(0)
        case .everyLabel: try integer(1)
        case let .batch(size, remainder): try integer(2); try integer(size); try integer(remainder ? 1 : 0)
        case .endOfJob: try integer(3)
        }
        try integer(job.plan.cutAfterOutputLabels.count)
        for boundary in job.plan.cutAfterOutputLabels { try integer(boundary) }
        try blob(p.normalization.bytes)
        let q = output.qualification
        try string(q.model)
        for fact in [q.quantityOne, q.labelCompletion, q.rfid, q.delayedCutter,
                     q.delayedCutReadiness, q.cutCompletion, q.peelLabelTaken, q.prepeel] {
            try string(fact.state.rawValue); try evidence(fact.evidence)
        }
        switch q.completeFileDelivery {
        case .unobserved: try integer(0)
        case let .observed(value, source): try integer(1); try integer(value ? 1 : 0); try evidence(source)
        }
        try integer(output.totalEncodedBytes); try integer(output.steps.count)
        for step in output.steps {
            switch step {
            case let .formatFile(label, bytes): try integer(1); try integer(label); try blob(bytes)
            case let .awaitLabelPrinted(label): try integer(2); try integer(label)
            case let .awaitDelayedCutReady(label): try integer(3); try integer(label)
            case let .delayedCutFile(label, bytes): try integer(4); try integer(label); try blob(bytes)
            case let .awaitCutCompleted(label): try integer(5); try integer(label)
            case let .awaitLabelTaken(label): try integer(6); try integer(label)
            }
        }
        try check()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try check()
        return Self(bytes: data, sha256: digest)
    }

    /// Compares every archive byte, including unknown/trailing/missing fields,
    /// to canonical independently supplied context. It never trusts an external
    /// length prefix or allocates from an external count. Safe on corrupt data.
    public static func reopen(_ bytes: Data, against output: FinishingFramedOutput,
                              deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
                              cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw Error.byteLimit }
        let started = DispatchTime.now().uptimeNanoseconds
        let expected = try encode(output, deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        let matches = expected.bytes == bytes
        guard Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000 < deadlineSeconds else {
            throw Error.timedOut
        }
        guard matches else { throw Error.bindingMismatch }
        guard !cancellation.isCancelled else { throw Error.cancelled }
        return expected
    }
}
