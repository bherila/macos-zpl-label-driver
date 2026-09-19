import Foundation
import LabelCore

/// Requirements for a future qualified sender, not observations or receipts.
/// File cases must remain complete files; they cannot be flattened for raw TCP.
public enum FinishingOutputStep: Equatable, Sendable {
    case formatFile(outputLabel: Int, bytes: Data)
    case awaitLabelPrinted(outputLabel: Int)
    case awaitDelayedCutReady(afterOutputLabel: Int)
    case delayedCutFile(afterOutputLabel: Int, bytes: Data)
    case awaitCutCompleted(afterOutputLabel: Int)
    case awaitLabelTaken(outputLabel: Int)
}

/// Bounded in-memory output plan from actual original-source packed inputs.
/// No adapter consumes this as device-write authority. Accepted ticket/device,
/// status correlation, lease lifetime and uncertain-delivery integration remain.
public struct FinishingFramedOutput: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimit, contextMismatch, outputLimit, cancelled, timedOut
    }
    public static let maximumBytes = 64 * 1024 * 1024
    public let preparation: FinishingRasterPreparation
    public let qualification: FinishingOutputQualification
    public let steps: [FinishingOutputStep]
    public let totalEncodedBytes: Int

    public static func prepare(
        _ preparation: FinishingRasterPreparation, qualification: FinishingOutputQualification,
        maximumBytes: Int = Self.maximumBytes,
        deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> Self {
        guard (1...Self.maximumBytes).contains(maximumBytes), deadlineSeconds.isFinite,
              deadlineSeconds > 0, deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else {
            throw Error.invalidLimit
        }
        let start = DispatchTime.now().uptimeNanoseconds
        func check() throws {
            guard !cancellation.isCancelled else { throw Error.cancelled }
            guard Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000 < deadlineSeconds else {
                throw Error.timedOut
            }
        }
        try check()
        let job = preparation.binding.job
        guard preparation.normalization.profile == job.printer.profile,
              preparation.normalization.plan == job.plan else { throw Error.contextMismatch }
        let policy = try qualification.validate(preparation.normalization)
        try preparation.binding.validate(job: job, orderedRasters: preparation.rasters, cancellation: cancellation)
        // The capability gate above decided the policy; the bytes for it come
        // from the one authoritative LabelCore mapping, never restated here.
        let mode = ZPLFinishingControlLiteral.framedMode(of: policy).line
        // Exactly one already-expanded label per format. RFID is independently
        // excluded; no guessed void-label cutter semantics are applied.
        let tail = Data("^PQ1\n^XZ\n".utf8)
        var steps: [FinishingOutputStep] = [], total = 0
        let cuts = Set(job.plan.cutAfterOutputLabels)
        for (index, bitmap) in preparation.rasters.enumerated() {
            try check()
            var format = Data("^XA\n".utf8)
            format.append(preparation.normalization.bytes); format.append(mode)
            let overhead = format.count + tail.count
            let remaining = maximumBytes - total
            guard remaining > overhead else { throw Error.outputLimit }
            let graphics = try ZPLGraphicEncoder(maxOutputBytes: remaining - overhead)
            try graphics.writeGraphicFields(bitmap) { bytes in
                try check(); format.append(bytes)
            }
            format.append(tail)
            let (next, overflow) = total.addingReportingOverflow(format.count)
            guard !overflow, next <= maximumBytes else { throw Error.outputLimit }
            total = next
            let ordinal = index + 1
            steps.append(.formatFile(outputLabel: ordinal, bytes: format))
            steps.append(.awaitLabelPrinted(outputLabel: ordinal))
            if cuts.contains(ordinal) {
                let trigger = ZPLFinishingControlLiteral.delayedCutTrigger.line
                let (next, overflow) = total.addingReportingOverflow(trigger.count)
                guard !overflow, next <= maximumBytes else { throw Error.outputLimit }
                total = next
                steps.append(.awaitDelayedCutReady(afterOutputLabel: ordinal))
                steps.append(.delayedCutFile(afterOutputLabel: ordinal, bytes: trigger))
                steps.append(.awaitCutCompleted(afterOutputLabel: ordinal))
            }
            if job.plan.mode == .peel { steps.append(.awaitLabelTaken(outputLabel: ordinal)) }
        }
        try check()
        return Self(preparation: preparation, qualification: qualification,
            steps: steps, totalEncodedBytes: total)
    }
}
