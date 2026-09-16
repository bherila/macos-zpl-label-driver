import Foundation
import LabelCore

/// Finite fault controls for the connected persisted-delivery simulator. This
/// type can only discard bytes; it has no transport endpoint or device handle.
public struct InertDeliveryScenario: Equatable, Sendable {
    public enum ValidationError: Swift.Error, Equatable, Sendable {
        case invalidChunkSize
        case invalidAmbiguityOffset
        case conflictingFaults
    }

    public let maximumChunkBytes: Int
    public let failBeforeTransmission: Bool
    public let becomeAmbiguousAfterBytes: Int?

    public init(
        maximumChunkBytes: Int = 64 * 1024,
        failBeforeTransmission: Bool = false,
        becomeAmbiguousAfterBytes: Int? = nil
    ) throws {
        guard maximumChunkBytes > 0,
              maximumChunkBytes <= PreparedJobPayload.maximumBytes else {
            throw ValidationError.invalidChunkSize
        }
        if let becomeAmbiguousAfterBytes,
           becomeAmbiguousAfterBytes < 0 {
            throw ValidationError.invalidAmbiguityOffset
        }
        if failBeforeTransmission, becomeAmbiguousAfterBytes != nil {
            throw ValidationError.conflictingFaults
        }
        self.maximumChunkBytes = maximumChunkBytes
        self.failBeforeTransmission = failBeforeTransmission
        self.becomeAmbiguousAfterBytes = becomeAmbiguousAfterBytes
    }
}

public enum InertPersistedDeliveryOutcome: Equatable, Sendable {
    case transmitted(byteCount: Int)
    case failedBeforeTransmission
    case uncertain(bytesAccepted: Int)
    case deviceBusy

    public var mayRetryAutomatically: Bool {
        switch self {
        case .failedBeforeTransmission, .deviceBusy: true
        case .transmitted, .uncertain: false
        }
    }
}

/// Connects the immutable prepared artifact, persisted lifecycle, and shared
/// device lease without contacting a printer. It exists to exercise ordering
/// and recovery contracts before a production scheduler/transport adapter is
/// admitted by M1 evidence.
public struct InertPersistedDelivery: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidState
        case stateUnavailable
        case stateCommitUncertain
        case leaseUnavailable
        case invalidScenario
    }

    enum Event: Equatable, Sendable {
        case sendAttemptPersisted
        case bytesDiscarded(Int)
    }

    private let states: AcceptedJobStateStore
    private let queues: VirtualQueueStore
    private let workflows: WorkflowProfileStore
    private let printers: PrinterProfileStore
    private let leaseDirectory: URL
    private let observe: @Sendable (Event) -> Void

    public init(
        acceptedJobStore: AcceptedJobStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore,
        leaseDirectory: URL
    ) {
        states = AcceptedJobStateStore(acceptedJobStore: acceptedJobStore)
        queues = queueStore
        workflows = workflowStore
        printers = printerStore
        self.leaseDirectory = leaseDirectory
        observe = { _ in }
    }

    init(
        acceptedJobStore: AcceptedJobStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore,
        leaseDirectory: URL,
        observe: @escaping @Sendable (Event) -> Void
    ) {
        states = AcceptedJobStateStore(acceptedJobStore: acceptedJobStore)
        queues = queueStore
        workflows = workflowStore
        printers = printerStore
        self.leaseDirectory = leaseDirectory
        self.observe = observe
    }

    public func deliver(
        acceptanceID: String,
        scenario: InertDeliveryScenario
    ) throws -> InertPersistedDeliveryOutcome {
        let prepared = try loadPrepared(acceptanceID: acceptanceID)
        if let fault = scenario.becomeAmbiguousAfterBytes,
           fault > prepared.bytes.count {
            throw Error.invalidScenario
        }
        var state = prepared.state
        let payloadSHA256: String
        let byteCount: Int
        let needsWaitingTransition: Bool
        switch state.phase {
        case let .prepared(hash, count):
            payloadSHA256 = hash
            byteCount = count
            needsWaitingTransition = true
        case let .waiting(hash, count):
            payloadSHA256 = hash
            byteCount = count
            needsWaitingTransition = false
        default:
            throw Error.invalidState
        }
        guard byteCount == prepared.bytes.count else { throw Error.invalidState }
        let lease: PhysicalDeviceLease
        do {
            lease = try PhysicalDeviceLease(
                acquiring: PhysicalDeviceIdentity(
                    coordinationID: prepared.physicalDevice
                ),
                inExistingDirectory: leaseDirectory
            )
        } catch PhysicalDeviceLeaseError.alreadyHeld {
            return .deviceBusy
        } catch {
            throw Error.leaseUnavailable
        }
        defer { lease.release() }

        if needsWaitingTransition {
            state = try transition(
                acceptanceID: acceptanceID, expected: state,
                next: .waiting(payloadSHA256: payloadSHA256, byteCount: byteCount)
            )
        }
        if scenario.failBeforeTransmission {
            _ = try transition(
                acceptanceID: acceptanceID, expected: state,
                next: .failedBeforeTransmission
            )
            return .failedBeforeTransmission
        }

        state = try transition(
            acceptanceID: acceptanceID, expected: state,
            next: .transmitting(
                payloadSHA256: payloadSHA256, byteCount: byteCount, bytesAccepted: 0
            )
        )
        observe(.sendAttemptPersisted)
        if scenario.becomeAmbiguousAfterBytes == 0 {
            _ = try transition(
                acceptanceID: acceptanceID, expected: state,
                next: .uncertain(
                    payloadSHA256: payloadSHA256, byteCount: byteCount, bytesAccepted: 0
                )
            )
            return .uncertain(bytesAccepted: 0)
        }

        var accepted = 0
        while accepted < prepared.bytes.count {
            var count = min(scenario.maximumChunkBytes, prepared.bytes.count - accepted)
            if let fault = scenario.becomeAmbiguousAfterBytes, fault > accepted {
                count = min(count, fault - accepted)
            }
            accepted += count
            observe(.bytesDiscarded(count))
            state = try transition(
                acceptanceID: acceptanceID, expected: state,
                next: .transmitting(
                    payloadSHA256: payloadSHA256,
                    byteCount: byteCount, bytesAccepted: accepted
                )
            )
            if scenario.becomeAmbiguousAfterBytes == accepted {
                _ = try transition(
                    acceptanceID: acceptanceID, expected: state,
                    next: .uncertain(
                        payloadSHA256: payloadSHA256,
                        byteCount: byteCount, bytesAccepted: accepted
                    )
                )
                return .uncertain(bytesAccepted: accepted)
            }
        }
        _ = try transition(
            acceptanceID: acceptanceID, expected: state,
            next: .transmitted(payloadSHA256: payloadSHA256, byteCount: byteCount)
        )
        return .transmitted(byteCount: accepted)
    }

    private func loadPrepared(acceptanceID: String) throws -> StoredPreparedJob {
        do {
            return try states.loadPrepared(
                acceptanceID: acceptanceID, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            )
        } catch AcceptedJobStateStore.Error.commitUncertain {
            throw Error.stateCommitUncertain
        } catch AcceptedJobStateStore.Error.preparedPayloadUnavailable {
            throw Error.invalidState
        } catch {
            throw Error.stateUnavailable
        }
    }

    private func transition(
        acceptanceID: String,
        expected: AcceptedJobStateRecord,
        next: AcceptedJobPhase
    ) throws -> AcceptedJobStateRecord {
        do {
            return try states.compareAndSwap(
                acceptanceID: acceptanceID, expected: expected, next: next,
                queueStore: queues, workflowStore: workflows,
                printerStore: printers
            )
        } catch AcceptedJobStateStore.Error.commitUncertain {
            throw Error.stateCommitUncertain
        } catch AcceptedJobStateStore.Error.invalidTransition,
                AcceptedJobStateStore.Error.stateConflict {
            throw Error.invalidState
        } catch {
            throw Error.stateUnavailable
        }
    }
}
