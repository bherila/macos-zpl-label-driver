import CryptoKit
import Foundation
import LabelCore

/// Result of the finite synthetic intake pipeline. `transmitted` means only
/// that the prepared bytes reached the in-memory discard sink.
public struct SyntheticInertJobResult: Equatable, Sendable {
    public let acceptanceID: String
    public let outputLabelCount: Int
    public let preparedByteCount: Int
    public let delivery: InertPersistedDeliveryOutcome
}

/// Connects scheduler-shaped, descriptor-bound PDF intake to immutable job
/// acceptance, native rendering, complete prepared-byte publication, and the
/// inert persisted-delivery path. It has no CUPS API, transport endpoint, or
/// printer handle and cannot deliver outside the in-memory discard sink.
///
/// This first connected reference path is intentionally limited to the
/// documented GC420d pitch of 8 dots/mm. That is model documentation, not a
/// claim about measured printable bounds or physical placement.
public struct SyntheticInertJobPipeline: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidRequest
        case invalidPreparationDeadline
        case processingCancelled
        case preparationDeadlineExceeded
        case inputUnavailable
        case configurationUnavailable
        case layoutRejected
        case acceptanceFailed
        case acceptanceCommitUncertain
        case preparationFailed
        case stateCommitUncertain
        case deliveryFailed
    }

    private let activeQueues: ActiveVirtualQueueStore
    private let queues: VirtualQueueStore
    private let workflows: WorkflowProfileStore
    private let printers: PrinterProfileStore
    private let acceptedJobs: AcceptedJobStore
    private let states: AcceptedJobStateStore
    private let delivery: InertPersistedDelivery
    private let maximumPreparedBytes: Int
    private let workerExecutable: URL

    public init(
        activeQueueStore: ActiveVirtualQueueStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore,
        acceptedJobStore: AcceptedJobStore,
        leaseDirectory: URL,
        workerExecutable: URL
    ) {
        self.init(
            activeQueueStore: activeQueueStore,
            queueStore: queueStore,
            workflowStore: workflowStore,
            printerStore: printerStore,
            acceptedJobStore: acceptedJobStore,
            leaseDirectory: leaseDirectory,
            workerExecutable: workerExecutable,
            maximumPreparedBytes: PreparedJobPayload.maximumBytes
        )
    }

    init(
        activeQueueStore: ActiveVirtualQueueStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore,
        acceptedJobStore: AcceptedJobStore,
        leaseDirectory: URL,
        workerExecutable: URL,
        maximumPreparedBytes: Int
    ) {
        precondition((8...PreparedJobPayload.maximumBytes).contains(maximumPreparedBytes))
        activeQueues = activeQueueStore
        queues = queueStore
        workflows = workflowStore
        printers = printerStore
        acceptedJobs = acceptedJobStore
        states = AcceptedJobStateStore(acceptedJobStore: acceptedJobStore)
        delivery = InertPersistedDelivery(
            acceptedJobStore: acceptedJobStore,
            queueStore: queueStore,
            workflowStore: workflowStore,
            printerStore: printerStore,
            leaseDirectory: leaseDirectory
        )
        self.maximumPreparedBytes = maximumPreparedBytes
        self.workerExecutable = workerExecutable
    }

    /// One cooperative preparation deadline covers analysis and all labels.
    /// Processing cancellation interrupts workers, not the persisted lifecycle;
    /// use the separately authorized state-store API for job cancellation.
    /// This is not transport admission arbitration or a filesystem timeout.
    public func run(
        queueID: String,
        sourcePDFDescriptor: Int32,
        acceptanceID: String,
        cancellationToken: Data,
        scenario: InertDeliveryScenario,
        preparationDeadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        processingCancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> SyntheticInertJobResult {
        let budget = try PreparationBudget(seconds: preparationDeadlineSeconds,
                                           cancellation: processingCancellation)
        try budget.check()
        guard !cancellationToken.isEmpty, cancellationToken.count <= 256 else {
            throw Error.invalidRequest
        }
        let sourcePDF: Data
        do {
            sourcePDF = try BoundedRegularFile.read(
                openFileDescriptor: sourcePDFDescriptor,
                maximumBytes: ResolvedJobTicket.maximumSourceBytes
            )
        } catch {
            throw Error.inputUnavailable
        }
        try budget.check()

        do {
            if let existing = try acceptedJobs.loadIfPresent(
                acceptanceID: acceptanceID, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            ) {
                return try resume(
                    existing: existing, suppliedSourcePDF: sourcePDF,
                    requestedQueueID: queueID,
                    cancellationToken: cancellationToken, scenario: scenario,
                    budget: budget
                )
            }
        } catch let error as Error {
            throw error
        } catch AcceptedJobStore.Error.commitUncertain {
            throw Error.acceptanceCommitUncertain
        } catch {
            throw Error.acceptanceFailed
        }

        let configuration: (
            ActiveVirtualQueueSelection, ImmutableProfileReference,
            VirtualQueueDefinition, WorkflowProfile, PrinterProfile
        )
        do {
            guard let selection = try activeQueues.load(
                queueID: queueID, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            ) else { throw Error.configurationUnavailable }
            let queue = try queues.load(
                reference: selection.queue, workflowStore: workflows,
                printerStore: printers
            )
            let workflow = try workflows.load(
                profileID: queue.workflowProfile.id,
                revision: queue.workflowProfile.revision
            )
            let printer = try printers.load(reference: queue.printerProfile)
            try validateReferenceConfiguration(workflow: workflow, printer: printer)
            configuration = (selection, selection.queue, queue, workflow, printer)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.configurationUnavailable
        }
        let (selection, queueReference, queue, workflow, printer) = configuration

        let plan: ExtractionPlan
        do {
            plan = try extractionPlan(sourcePDF: sourcePDF, workflow: workflow, budget: budget)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.layoutRejected
        }

        let ticket: ResolvedJobTicket
        try budget.check()
        do {
            ticket = try ResolvedJobTicket.accept(
                acceptanceID: acceptanceID,
                cancellationSHA256: Self.digest(cancellationToken),
                activeSelection: selection,
                queueReference: queueReference,
                queueDefinition: queue,
                workflowProfile: workflow,
                printerProfile: printer,
                sourceDocumentSHA256: Self.digest(sourcePDF),
                sourceByteCount: sourcePDF.count,
                intakeProvenance: .cupsScheduler,
                plan: plan,
                copyOwnership: .upstreamAlreadyExpanded,
                pageRangeOwnership: .upstreamAlreadyApplied
            )
            try acceptedJobs.save(
                ticket, sourcePDF: sourcePDF, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            )
        } catch AcceptedJobStore.Error.commitUncertain {
            throw Error.acceptanceCommitUncertain
        } catch {
            throw Error.acceptanceFailed
        }

        let state: AcceptedJobStateRecord
        do {
            state = try states.load(
                acceptanceID: acceptanceID, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            )
        } catch {
            throw Error.preparationFailed
        }

        let preparedByteCount: Int
        switch state.phase {
        case .accepted:
            let payload = try prepare(
                sourcePDF: sourcePDF, plan: plan, ticket: ticket,
                workflow: workflow, queue: queue, printer: printer, budget: budget
            )
            try budget.check()
            do {
                _ = try states.publishPrepared(
                    acceptanceID: acceptanceID, expected: state, payload: payload,
                    queueStore: queues, workflowStore: workflows,
                    printerStore: printers
                )
            } catch AcceptedJobStateStore.Error.commitUncertain {
                throw Error.stateCommitUncertain
            } catch {
                throw Error.preparationFailed
            }
            preparedByteCount = payload.bytes.count
        case .prepared, .waiting:
            do {
                preparedByteCount = try states.loadPrepared(
                    acceptanceID: acceptanceID, queueStore: queues,
                    workflowStore: workflows, printerStore: printers
                ).bytes.count
            } catch {
                throw Error.preparationFailed
            }
        default:
            throw Error.deliveryFailed
        }

        try budget.check()
        return try deliverResult(
            ticket: ticket,
            preparedByteCount: preparedByteCount,
            scenario: scenario
        )
    }

    private func resume(
        existing: AcceptedJobBundle,
        suppliedSourcePDF: Data,
        requestedQueueID: String,
        cancellationToken: Data,
        scenario: InertDeliveryScenario,
        budget: PreparationBudget
    ) throws -> SyntheticInertJobResult {
        guard existing.ticket.queue.id == requestedQueueID,
              existing.sourcePDF == suppliedSourcePDF,
              Self.constantTimeEqual(
                  Self.digestBytes(cancellationToken),
                  Self.hexBytes(existing.ticket.cancellationSHA256)
              ) else {
            throw Error.acceptanceFailed
        }
        let queue: VirtualQueueDefinition
        let workflow: WorkflowProfile
        let printer: PrinterProfile
        do {
            queue = try queues.load(
                reference: existing.ticket.queue, workflowStore: workflows,
                printerStore: printers
            )
            workflow = try workflows.load(
                profileID: existing.ticket.workflowProfile.id,
                revision: existing.ticket.workflowProfile.revision
            )
            printer = try printers.load(reference: existing.ticket.printerProfile)
            try validateReferenceConfiguration(workflow: workflow, printer: printer)
            // An exact retry repeats the accepted-bundle durability barrier
            // before prior uncertainty can become permission to proceed.
            try acceptedJobs.save(
                existing.ticket, sourcePDF: suppliedSourcePDF,
                queueStore: queues, workflowStore: workflows,
                printerStore: printers
            )
        } catch AcceptedJobStore.Error.commitUncertain {
            throw Error.acceptanceCommitUncertain
        } catch let error as Error {
            throw error
        } catch {
            throw Error.acceptanceFailed
        }

        let state: AcceptedJobStateRecord
        do {
            state = try states.load(
                acceptanceID: existing.ticket.acceptanceID,
                queueStore: queues, workflowStore: workflows,
                printerStore: printers
            )
        } catch {
            throw Error.preparationFailed
        }
        let preparedByteCount: Int
        switch state.phase {
        case .accepted:
            let plan: ExtractionPlan
            do {
                plan = try extractionPlan(
                    sourcePDF: suppliedSourcePDF, workflow: workflow, budget: budget
                )
            } catch let error as Error {
                throw error
            } catch {
                throw Error.layoutRejected
            }
            guard plan.outputLabels.count == existing.ticket.outputLabels.count,
                  zip(plan.outputLabels, existing.ticket.outputLabels).allSatisfy({
                      $0.sourcePage == $1.sourcePage && $0.regionID == $1.regionID
                  }) else {
                throw Error.layoutRejected
            }
            let payload = try prepare(
                sourcePDF: suppliedSourcePDF, plan: plan,
                ticket: existing.ticket, workflow: workflow,
                queue: queue, printer: printer, budget: budget
            )
            try budget.check()
            do {
                _ = try states.publishPrepared(
                    acceptanceID: existing.ticket.acceptanceID,
                    expected: state, payload: payload,
                    queueStore: queues, workflowStore: workflows,
                    printerStore: printers
                )
            } catch AcceptedJobStateStore.Error.commitUncertain {
                throw Error.stateCommitUncertain
            } catch {
                throw Error.preparationFailed
            }
            preparedByteCount = payload.bytes.count
        case .prepared, .waiting:
            do {
                preparedByteCount = try states.loadPrepared(
                    acceptanceID: existing.ticket.acceptanceID,
                    queueStore: queues, workflowStore: workflows,
                    printerStore: printers
                ).bytes.count
            } catch {
                throw Error.preparationFailed
            }
        case let .uncertain(_, byteCount, bytesAccepted):
            try validateStoredPayload(
                acceptanceID: existing.ticket.acceptanceID,
                expectedByteCount: byteCount
            )
            return SyntheticInertJobResult(
                acceptanceID: existing.ticket.acceptanceID,
                outputLabelCount: existing.ticket.outputLabels.count,
                preparedByteCount: byteCount,
                delivery: .uncertain(bytesAccepted: bytesAccepted)
            )
        case let .transmitted(_, byteCount):
            try validateStoredPayload(
                acceptanceID: existing.ticket.acceptanceID,
                expectedByteCount: byteCount
            )
            return SyntheticInertJobResult(
                acceptanceID: existing.ticket.acceptanceID,
                outputLabelCount: existing.ticket.outputLabels.count,
                preparedByteCount: byteCount,
                delivery: .transmitted(byteCount: byteCount)
            )
        default:
            throw Error.deliveryFailed
        }
        try budget.check()
        return try deliverResult(
            ticket: existing.ticket,
            preparedByteCount: preparedByteCount,
            scenario: scenario
        )
    }

    private func validateStoredPayload(
        acceptanceID: String, expectedByteCount: Int
    ) throws {
        do {
            let stored = try states.loadPrepared(
                acceptanceID: acceptanceID,
                queueStore: queues, workflowStore: workflows,
                printerStore: printers
            )
            guard stored.bytes.count == expectedByteCount else {
                throw Error.preparationFailed
            }
        } catch let error as Error {
            throw error
        } catch {
            throw Error.preparationFailed
        }
    }

    private func extractionPlan(
        sourcePDF: Data, workflow: WorkflowProfile, budget: PreparationBudget
    ) throws -> ExtractionPlan {
        let analyzed: [AnalyzedSourcePage]
        do {
            analyzed = try OfflineLayoutWorker.analyze(
                originalPDF: sourcePDF,
                structuralPages: workflow.pageRules.filter { !$0.structuralAnchors.isEmpty }.map(\.sourcePage),
                workerExecutable: workerExecutable,
                barcodePages: workflow.pageRules.filter { rule in
                    rule.structuralAnchors.contains { $0.kind == .barcodeLike }
                }.map(\.sourcePage),
                deadlineSeconds: budget.remainingSeconds(), cancellation: budget.cancellation
            )
        } catch OfflineRenderWorkerProcess.Error.cancelled {
            throw Error.processingCancelled
        } catch OfflineRenderWorkerProcess.Error.timedOut {
            throw Error.preparationDeadlineExceeded
        }
        try budget.check()
        return try ExtractionPlanner.plan(
            analyzedPages: analyzed,
            profile: workflow,
            copyPolicy: .alreadyExpanded,
            maximumOutputLabels: ResolvedJobTicket.maximumOutputLabels
        )
    }

    private func validateReferenceConfiguration(
        workflow: WorkflowProfile, printer: PrinterProfile
    ) throws {
        guard printer.capabilities.model == "GC420d",
              case let .observed(loadedStock, evidence: _) =
                  printer.media.nominalLabelFace,
              loadedStock == workflow.outputStock else {
            throw Error.configurationUnavailable
        }
    }

    private func deliverResult(
        ticket: ResolvedJobTicket,
        preparedByteCount: Int,
        scenario: InertDeliveryScenario
    ) throws -> SyntheticInertJobResult {
        let outcome: InertPersistedDeliveryOutcome
        do {
            outcome = try delivery.deliver(
                acceptanceID: ticket.acceptanceID, scenario: scenario
            )
        } catch InertPersistedDelivery.Error.stateCommitUncertain {
            throw Error.stateCommitUncertain
        } catch {
            throw Error.deliveryFailed
        }
        return SyntheticInertJobResult(
            acceptanceID: ticket.acceptanceID,
            outputLabelCount: ticket.outputLabels.count,
            preparedByteCount: preparedByteCount,
            delivery: outcome
        )
    }

    private func prepare(
        sourcePDF: Data,
        plan: ExtractionPlan,
        ticket: ResolvedJobTicket,
        workflow: WorkflowProfile,
        queue: VirtualQueueDefinition,
        printer: PrinterProfile,
        budget: PreparationBudget
    ) throws -> PreparedJobPayload {
        do {
            let canvas = try DotCanvas(
                physicalSize: workflow.outputStock,
                resolution: DotResolution(
                    xDotsPerMillimeter: 8, yDotsPerMillimeter: 8
                ),
                maximumByteCount: maximumPreparedBytes
            )
            let defaults = PrinterControlDefaults(
                thermalMethod: queue.workflowDefaults.thermalMethod,
                finishing: queue.workflowDefaults.finishing,
                printSpeedIps: queue.workflowDefaults.printSpeedIps,
                darkness: queue.workflowDefaults.darkness,
                tracking: queue.workflowDefaults.tracking,
                mediaGeometry: queue.workflowDefaults.mediaGeometry
            )
            guard plan.outputLabels.count == ticket.outputLabels.count else {
                throw Error.preparationFailed
            }
            var totalBytes = 0
            var labels: [PreparedOutputLabel] = []
            labels.reserveCapacity(plan.outputLabels.count)
            for (planned, output) in zip(plan.outputLabels, ticket.outputLabels) {
                let remaining = maximumPreparedBytes - totalBytes
                guard remaining >= 8 else { throw Error.preparationFailed }
                let bitmap = try OfflineExtractionWorker.render(
                    originalPDF: sourcePDF,
                    label: planned,
                    canvas: canvas,
                    conversion: ticket.monochromeConversion,
                    workerExecutable: workerExecutable,
                    deadlineSeconds: budget.remainingSeconds(), cancellation: budget.cancellation
                )
                try budget.check()
                let prepared = try ZPLPreparedLabelEncoder(
                    maxOutputBytes: remaining
                ).prepare(
                    bitmap: bitmap,
                    profile: printer,
                    workflowDefaults: defaults
                )
                let (nextTotal, overflow) = totalBytes.addingReportingOverflow(
                    prepared.bytes.count
                )
                guard !overflow, nextTotal <= maximumPreparedBytes else {
                    throw Error.preparationFailed
                }
                labels.append(PreparedOutputLabel(output: output, prepared: prepared))
                totalBytes = nextTotal
            }
            return try PreparedJobPayload(
                labels: labels,
                expectedOutputLabels: ticket.outputLabels,
                monochromeConversion: ticket.monochromeConversion,
                maximumBytes: maximumPreparedBytes
            )
        } catch OfflineRenderWorkerProcess.Error.cancelled {
            throw Error.processingCancelled
        } catch OfflineRenderWorkerProcess.Error.timedOut {
            throw Error.preparationDeadlineExceeded
        } catch let error as Error {
            throw error
        } catch {
            throw Error.preparationFailed
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func digestBytes(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private static func hexBytes(_ value: String) -> [UInt8] {
        guard value.utf8.count == 64 else { return [] }
        var result: [UInt8] = []
        result.reserveCapacity(32)
        var index = value.startIndex
        for _ in 0..<32 {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return [] }
            result.append(byte)
            index = next
        }
        return result
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }
}
