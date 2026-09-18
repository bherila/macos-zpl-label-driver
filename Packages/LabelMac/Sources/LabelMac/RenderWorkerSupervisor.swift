import Darwin
import Foundation

/// Child-owned, finite supervision independent of the parent's event loop.
/// The dedicated thread never acquires locks held across native rendering.
public final class RenderWorkerSupervisor: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private let marker: Int32

    public init(parentPID: Int32, deadlineSeconds: Double,
                scratchDirectory: URL? = nil, ownershipToken: String? = nil) throws {
        guard parentPID > 1, getppid() == parentPID, deadlineSeconds.isFinite,
              deadlineSeconds > 0, deadlineSeconds <= 60 else {
            throw OfflineRenderWorkerProcess.Error.invalidDeadline
        }
        if let ownershipToken, let scratchDirectory {
            marker = try RenderWorkerScratch.hold(in: scratchDirectory, parentPID: parentPID, token: ownershipToken)
        } else {
            guard ownershipToken == nil, scratchDirectory == nil else {
                throw OfflineRenderWorkerProcess.Error.scratchUnavailable
            }
            marker = -1
        }
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(deadlineSeconds * 1e9)))
        Thread.detachNewThread { [self] in
            defer { if marker >= 0 { close(marker) } }
            while true {
                lock.lock()
                let finished = stopped
                lock.unlock()
                if finished { return }
                if getppid() != parentPID { _exit(125) }
                if ContinuousClock.now >= deadline { _exit(124) }
                usleep(20_000)
            }
        }
    }

    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
