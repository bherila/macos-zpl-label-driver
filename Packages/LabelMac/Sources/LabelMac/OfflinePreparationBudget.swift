import Foundation

extension SyntheticInertJobPipeline {
    /// One monotonic admission budget, never renewed for subsequent labels.
    /// Filesystem calls are checked on return, not forcibly interrupted.
    struct PreparationBudget {
        let cancellation: OfflineRenderWorkerCancellation
        private let deadline: ContinuousClock.Instant
        private let now: @Sendable () -> ContinuousClock.Instant

        init(seconds: Double, cancellation: OfflineRenderWorkerCancellation,
             now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) throws {
            guard seconds.isFinite, seconds > 0,
                  seconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else {
                throw SyntheticInertJobPipeline.Error.invalidPreparationDeadline
            }
            self.cancellation = cancellation
            self.now = now
            deadline = now().advanced(by: .nanoseconds(Int64(seconds * 1_000_000_000)))
        }

        func check() throws {
            if cancellation.isCancelled { throw SyntheticInertJobPipeline.Error.processingCancelled }
            if now() >= deadline { throw SyntheticInertJobPipeline.Error.preparationDeadlineExceeded }
        }

        func remainingSeconds() throws -> Double {
            try check()
            let parts = now().duration(to: deadline).components
            let value = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            guard value > 0 else { throw SyntheticInertJobPipeline.Error.preparationDeadlineExceeded }
            return min(value, OfflineRenderWorkerProcess.defaultDeadlineSeconds)
        }
    }
}
