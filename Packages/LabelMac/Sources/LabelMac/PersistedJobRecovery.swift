import Foundation
import LabelCore

/// A restart-time classification derived from the persisted accepted-job
/// bundle. Recovery never sends bytes and never turns transmission ambiguity
/// into permission to retry.
public enum PersistedJobRecoveryOutcome: Equatable, Sendable {
    case acceptedNeedsPreparation
    case readyForDelivery
    case physicalDeviceBusy
    case transmitted(byteCount: Int)
    case deviceConfirmed(byteCount: Int)
    case uncertain(bytesAccepted: Int)
    case failedBeforeTransmission
    case cancelledBeforeTransmission
}

/// Reconciles one known accepted job after process restart. A persisted
/// `transmitting` record is made terminally uncertain only after acquiring the
/// same ticket-derived physical-device lease used by delivery. If another
/// process still owns that lease, its state is left untouched.
public struct PersistedJobRecovery: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case stateUnavailable
        case stateCommitUncertain
        case leaseUnavailable
        case invalidState
    }

    enum Event: Equatable, Sendable {
        case initialStateLoaded
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

    public func reconcile(
        acceptanceID: String
    ) throws -> PersistedJobRecoveryOutcome {
        let state = try loadState(acceptanceID: acceptanceID)
        observe(.initialStateLoaded)
        return try reconcile(
            acceptanceID: acceptanceID,
            observed: state,
            remainingStateReads: 8
        )
    }

    private func reconcile(
        acceptanceID: String,
        observed state: AcceptedJobStateRecord,
        remainingStateReads: Int
    ) throws -> PersistedJobRecoveryOutcome {
        switch state.phase {
        case .accepted:
            return .acceptedNeedsPreparation
        case .failedBeforeTransmission:
            return .failedBeforeTransmission
        case .cancelledBeforeTransmission:
            return .cancelledBeforeTransmission
        case .prepared, .waiting, .transmitted, .deviceConfirmed, .uncertain:
            let prepared: StoredPreparedJob
            do {
                prepared = try loadPrepared(acceptanceID: acceptanceID)
            } catch Error.invalidState {
                // A cooperative writer may have removed deliverability by
                // publishing cancellation or pre-send failure after our first
                // read. Reclassify a bounded number of monotonic transitions.
                guard remainingStateReads > 0 else { throw Error.stateUnavailable }
                return try reconcile(
                    acceptanceID: acceptanceID,
                    observed: loadState(acceptanceID: acceptanceID),
                    remainingStateReads: remainingStateReads - 1
                )
            }
            if case .transmitting = prepared.state.phase {
                return try reconcileTransmission(
                    acceptanceID: acceptanceID, initial: prepared
                )
            }
            return try classify(prepared)
        case .transmitting:
            return try reconcileTransmission(acceptanceID: acceptanceID)
        }
    }

    private func reconcileTransmission(
        acceptanceID: String,
        initial suppliedInitial: StoredPreparedJob? = nil
    ) throws -> PersistedJobRecoveryOutcome {
        let initial = try suppliedInitial ?? loadPrepared(acceptanceID: acceptanceID)
        guard case .transmitting = initial.state.phase else {
            return try classify(initial)
        }

        let lease: PhysicalDeviceLease
        do {
            lease = try PhysicalDeviceLease(
                acquiring: PhysicalDeviceIdentity(
                    coordinationID: initial.physicalDevice
                ),
                inExistingDirectory: leaseDirectory
            )
        } catch PhysicalDeviceLeaseError.alreadyHeld {
            return .physicalDeviceBusy
        } catch {
            throw Error.leaseUnavailable
        }
        defer { lease.release() }

        // Reload under the device lease. The former owner may have completed
        // and released between the first read and our acquisition.
        let current = try loadPrepared(acceptanceID: acceptanceID)
        guard case let .transmitting(hash, count, accepted) = current.state.phase else {
            return try classify(current)
        }
        do {
            _ = try states.compareAndSwap(
                acceptanceID: acceptanceID,
                expected: current.state,
                next: .uncertain(
                    payloadSHA256: hash,
                    byteCount: count,
                    bytesAccepted: accepted
                ),
                queueStore: queues,
                workflowStore: workflows,
                printerStore: printers
            )
            return .uncertain(bytesAccepted: accepted)
        } catch AcceptedJobStateStore.Error.commitUncertain {
            throw Error.stateCommitUncertain
        } catch {
            throw Error.stateUnavailable
        }
    }

    private func classify(
        _ prepared: StoredPreparedJob
    ) throws -> PersistedJobRecoveryOutcome {
        switch prepared.state.phase {
        case .prepared, .waiting:
            return .readyForDelivery
        case let .transmitted(_, count):
            return .transmitted(byteCount: count)
        case let .deviceConfirmed(_, count):
            return .deviceConfirmed(byteCount: count)
        case let .uncertain(_, _, accepted):
            return .uncertain(bytesAccepted: accepted)
        case .transmitting:
            throw Error.invalidState
        case .accepted, .failedBeforeTransmission, .cancelledBeforeTransmission:
            throw Error.invalidState
        }
    }

    private func loadState(
        acceptanceID: String
    ) throws -> AcceptedJobStateRecord {
        do {
            return try states.load(
                acceptanceID: acceptanceID,
                queueStore: queues,
                workflowStore: workflows,
                printerStore: printers
            )
        } catch AcceptedJobStateStore.Error.commitUncertain {
            throw Error.stateCommitUncertain
        } catch {
            throw Error.stateUnavailable
        }
    }

    private func loadPrepared(
        acceptanceID: String
    ) throws -> StoredPreparedJob {
        do {
            return try states.loadPrepared(
                acceptanceID: acceptanceID,
                queueStore: queues,
                workflowStore: workflows,
                printerStore: printers
            )
        } catch AcceptedJobStateStore.Error.commitUncertain {
            throw Error.stateCommitUncertain
        } catch AcceptedJobStateStore.Error.preparedPayloadUnavailable {
            throw Error.invalidState
        } catch {
            throw Error.stateUnavailable
        }
    }
}
