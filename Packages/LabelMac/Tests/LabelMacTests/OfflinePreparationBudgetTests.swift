import Foundation
import XCTest
@testable import LabelMac

final class OfflinePreparationBudgetTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = ContinuousClock.now
        func now() -> ContinuousClock.Instant {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func advance(_ seconds: Int) {
            lock.lock(); defer { lock.unlock() }
            value = value.advanced(by: .seconds(seconds))
        }
    }

    func testSubsequentLabelsNeverRenewSharedDeadline() throws {
        let clock = Clock()
        let budget = try SyntheticInertJobPipeline.PreparationBudget(seconds: 10,
            cancellation: .init(), now: { clock.now() })
        XCTAssertEqual(try budget.remainingSeconds(), 10, accuracy: 0.001)
        clock.advance(3)
        XCTAssertEqual(try budget.remainingSeconds(), 7, accuracy: 0.001)
        clock.advance(7)
        XCTAssertThrowsError(try budget.remainingSeconds()) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .preparationDeadlineExceeded)
        }
    }

    func testCancellationAndInvalidLimitsAreExplicit() throws {
        let cancellation = OfflineRenderWorkerCancellation()
        let budget = try SyntheticInertJobPipeline.PreparationBudget(seconds: 1,
            cancellation: cancellation)
        cancellation.cancel()
        XCTAssertThrowsError(try budget.check()) {
            XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .processingCancelled)
        }
        for seconds in [Double.nan, .infinity, 0, -1, 61] {
            XCTAssertThrowsError(try SyntheticInertJobPipeline.PreparationBudget(seconds: seconds,
                cancellation: .init())) {
                XCTAssertEqual($0 as? SyntheticInertJobPipeline.Error, .invalidPreparationDeadline)
            }
        }
    }
}
