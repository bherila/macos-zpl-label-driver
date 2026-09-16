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

    public init(
        activeQueueStore: ActiveVirtualQueueStore,
        queueStore: VirtualQueueStore,
        workflowStore: WorkflowProfileStore,
        printerStore: PrinterProfileStore,
        acceptedJobStore: AcceptedJobStore,
        leaseDirectory: URL
    ) {
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
    }

    public func run(
        queueID: String,
        sourcePDFDescriptor: Int32,
        acceptanceID: String,
        cancellationToken: Data,
        scenario: InertDeliveryScenario
    ) throws -> SyntheticInertJobResult {
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
            guard printer.capabilities.model == "GC420d" else {
                throw Error.configurationUnavailable
            }
            configuration = (selection, selection.queue, queue, workflow, printer)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.configurationUnavailable
        }
        let (selection, queueReference, queue, workflow, printer) = configuration

        let plan: ExtractionPlan
        do {
            let boxes = try QuartzPDFRenderer.documentPageBoxes(
                originalPDF: sourcePDF,
                maximumInputBytes: ResolvedJobTicket.maximumSourceBytes,
                maximumSourcePages: ResolvedJobTicket.maximumSourcePages
            )
            let rules = Dictionary(uniqueKeysWithValues: workflow.pageRules.map {
                ($0.sourcePage, $0)
            })
            let analyzed = try boxes.enumerated().map { index, box in
                let page = index + 1
                if let rule = rules[page], !rule.structuralAnchors.isEmpty {
                    return try QuartzStructuralAnalyzer.analyzeBorders(
                        originalPDF: sourcePDF,
                        pageNumber: page,
                        maximumInputBytes: ResolvedJobTicket.maximumSourceBytes,
                        maximumSourcePages: ResolvedJobTicket.maximumSourcePages
                    )
                }
                return try AnalyzedSourcePage(pageBox: box, anchors: nil)
            }
            plan = try ExtractionPlanner.plan(
                analyzedPages: analyzed,
                profile: workflow,
                copyPolicy: .alreadyExpanded,
                maximumOutputLabels: ResolvedJobTicket.maximumOutputLabels
            )
        } catch {
            throw Error.layoutRejected
        }

        let ticket: ResolvedJobTicket
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

        let payload: PreparedJobPayload
        do {
            let canvas = try DotCanvas(
                physicalSize: workflow.outputStock,
                resolution: DotResolution(
                    xDotsPerMillimeter: 8, yDotsPerMillimeter: 8
                ),
                maximumByteCount: 64 * 1024 * 1024
            )
            let encoder = try ZPLPreparedLabelEncoder()
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
            let labels = try zip(plan.outputLabels, ticket.outputLabels).map {
                planned, output in
                let rendered = try QuartzPlannedExtraction.prepare(
                    originalPDF: sourcePDF,
                    label: planned,
                    canvas: canvas,
                    conversion: ticket.monochromeConversion,
                    maximumInputBytes: ResolvedJobTicket.maximumSourceBytes,
                    maximumSourcePages: ResolvedJobTicket.maximumSourcePages
                )
                let prepared = try encoder.prepare(
                    bitmap: rendered.bitmap,
                    profile: printer,
                    workflowDefaults: defaults
                )
                return PreparedOutputLabel(output: output, prepared: prepared)
            }
            payload = try PreparedJobPayload(
                labels: labels,
                expectedOutputLabels: ticket.outputLabels,
                monochromeConversion: ticket.monochromeConversion
            )
        } catch {
            throw Error.preparationFailed
        }

        do {
            let accepted = try states.load(
                acceptanceID: acceptanceID, queueStore: queues,
                workflowStore: workflows, printerStore: printers
            )
            _ = try states.publishPrepared(
                acceptanceID: acceptanceID, expected: accepted, payload: payload,
                queueStore: queues, workflowStore: workflows,
                printerStore: printers
            )
        } catch AcceptedJobStateStore.Error.commitUncertain {
            throw Error.stateCommitUncertain
        } catch {
            throw Error.preparationFailed
        }

        let outcome: InertPersistedDeliveryOutcome
        do {
            outcome = try delivery.deliver(
                acceptanceID: acceptanceID, scenario: scenario
            )
        } catch InertPersistedDelivery.Error.stateCommitUncertain {
            throw Error.stateCommitUncertain
        } catch {
            throw Error.deliveryFailed
        }
        return SyntheticInertJobResult(
            acceptanceID: acceptanceID,
            outputLabelCount: ticket.outputLabels.count,
            preparedByteCount: payload.bytes.count,
            delivery: outcome
        )
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
