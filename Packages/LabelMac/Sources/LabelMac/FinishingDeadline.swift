import Foundation

/// One wall-clock budget shared by every step of a single finishing command.
///
/// `finishing-preview` previously started one clock inside inspection and a
/// second inside preparation, so two sixty-second budgets drained in parallel
/// and a document whose single analysis fits inside the budget could still fail
/// as `timedOut`. One deadline now governs inspection, preparation and export.
/// Expiry fails closed: an exhausted budget yields no preview, and the budget
/// bounds offline work only. It is never delivery, replay or completion evidence.
public struct FinishingDeadline: Sendable {
    public static let maximumSeconds = OfflineRenderWorkerProcess.defaultDeadlineSeconds
    public let cancellation: OfflineRenderWorkerCancellation
    private let expiry: ContinuousClock.Instant
    private let now: @Sendable () -> ContinuousClock.Instant
    public init(seconds: Double = FinishingDeadline.maximumSeconds,
                cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        try self.init(seconds: seconds, cancellation: cancellation, now: { .now })
    }
    init(seconds: Double, cancellation: OfflineRenderWorkerCancellation,
         now: @escaping @Sendable () -> ContinuousClock.Instant) throws {
        guard seconds.isFinite, seconds > 0, seconds <= Self.maximumSeconds else {
            throw AcceptedFinishingJob.Error.invalidLimit
        }
        self.cancellation = cancellation; self.now = now
        expiry = now().advanced(by: .nanoseconds(Int64(seconds * 1_000_000_000)))
    }
    /// The budget left for this step, capped by the worker limit. Cancellation is
    /// observed first so a cancelled command never reports a mere timeout.
    public func remaining() throws -> Double {
        guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
        let parts = now().duration(to: expiry).components
        let value = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        guard value > 0 else { throw AcceptedFinishingJob.Error.timedOut }
        return min(value, Self.maximumSeconds)
    }
    public func check() throws { _ = try remaining() }
}
