import CryptoKit
import Foundation
import LabelCore

/// Immutable unprivileged acceptance from original PDF bytes. This is not
/// scheduler admission, hardware qualification or permission for transmission.
public struct AcceptedFinishingJob: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidIdentity, invalidSource, invalidOwnership, invalidLimit, cancelled, timedOut, bindingMismatch
    }
    public let acceptanceID: String
    public let cancellationSHA256: String
    public let queueReference: FinishingQueueReference
    public let queueDefinition: FinishingQueueDefinition
    public let workflow: WorkflowProfile
    public let geometry: FinishingDeviceGeometry
    public let originalPDF: Data
    public let sourceSHA256: String
    public let extraction: ExtractionPlan
    public let copyOwnership: JobCopyOwnership
    public let pageRangeOwnership: JobPageRangeOwnership
    public let canvas: DotCanvas
    public let job: ProfileBoundFinishingJobPlan
    public let controls: ResolvedPrinterControls
    public let controlRequest: PrinterControlRequest
    public var intakeProvenance: JobIntakeProvenance { .offlineCLI }
    public var transformOwnership: JobTransformOwnership { .workflowProfile }

    public static func accept(acceptanceID: String, cancellationSHA256: String,
        queueReference: FinishingQueueReference, queueStore: FinishingQueueStore,
        workflowStore: WorkflowProfileStore, printerStore: PrinterProfileStore,
        geometry: FinishingDeviceGeometry, originalPDF: Data,
        copyOwnership: JobCopyOwnership, pageRangeOwnership: JobPageRangeOwnership,
        selection: FinishingQueueSelection? = nil, controls request: PrinterControlRequest = .init(),
        workerExecutable: URL, deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Self {
        do { _ = try ImmutableProfileReference(id: acceptanceID, revision: 1, sha256: cancellationSHA256) }
        catch { throw Error.invalidIdentity }
        guard !originalPDF.isEmpty, originalPDF.count <= ResolvedJobTicket.maximumSourceBytes else { throw Error.invalidSource }
        guard deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds else { throw Error.invalidLimit }
        let start = DispatchTime.now().uptimeNanoseconds
        func remaining() throws -> Double {
            guard !cancellation.isCancelled else { throw Error.cancelled }
            let value = deadlineSeconds - Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            guard value > 0 else { throw Error.timedOut }; return value
        }
        _ = try remaining()
        let copyPolicy: LabelOrderPlan.CopyPolicy
        switch copyOwnership {
        case let .engine(copies, collated):
            guard (1...ResolvedJobTicket.maximumOutputLabels).contains(copies) else { throw Error.invalidOwnership }
            copyPolicy = .engine(copies: copies, collated: collated)
        case .upstreamAlreadyExpanded: copyPolicy = .alreadyExpanded
        }
        let selectedPages: Set<Int>?
        switch pageRangeOwnership {
        case let .engine(pages):
            guard !pages.isEmpty, pages == Array(Set(pages)).sorted(),
                  pages.allSatisfy({ (1...ResolvedJobTicket.maximumSourcePages).contains($0) }) else { throw Error.invalidOwnership }
            selectedPages = Set(pages)
        case .upstreamAlreadyApplied: selectedPages = nil
        }
        let queue = try queueStore.load(reference: queueReference, workflowStore: workflowStore, printerStore: printerStore)
        let workflow = try workflowStore.load(profileID: queue.workflowProfile.id, revision: queue.workflowProfile.revision)
        let canvas = try geometry.canvas(for: queue, workflow: workflow)
        let selected = selection ?? queue.defaultSelection
        // Reject invalid controls/selection before invoking the PDF worker.
        _ = try queue.resolve(outputLabelCount: 1, workflow: workflow, printer: geometry.printer.profile,
                              selection: selected, job: request)
        let structuralPages = workflow.pageRules.filter { !$0.structuralAnchors.isEmpty }.map(\.sourcePage)
        let barcodePages = workflow.pageRules.filter { $0.structuralAnchors.contains { $0.kind == .barcodeLike } }.map(\.sourcePage)
        let pages = try OfflineLayoutWorker.analyze(originalPDF: originalPDF, structuralPages: structuralPages,
            workerExecutable: workerExecutable, barcodePages: barcodePages,
            deadlineSeconds: remaining(), cancellation: cancellation)
        if let selectedPages, !selectedPages.isSubset(of: Set(1...pages.count)) { throw Error.invalidOwnership }
        let extraction = try ExtractionPlanner.plan(analyzedPages: pages, profile: workflow,
            selectedSourcePages: selectedPages, copyPolicy: copyPolicy)
        let resolved = try queue.resolve(outputLabelCount: extraction.outputLabels.count, workflow: workflow,
            printer: geometry.printer.profile, selection: selected, job: request)
        let job = try printerStore.finishingPlan(reference: queue.printerProfile, mode: selected.mode,
            outputLabelCount: extraction.outputLabels.count, schedule: selected.schedule)
        guard job.plan == resolved.plan, job.printer == geometry.printer else { throw Error.bindingMismatch }
        var effectiveRequest = request; effectiveRequest.finishing = selected.mode
        let sourceHash = SHA256.hash(data: originalPDF).map { String(format: "%02x", $0) }.joined()
        _ = try remaining()
        return Self(acceptanceID: acceptanceID, cancellationSHA256: cancellationSHA256,
            queueReference: queueReference, queueDefinition: queue, workflow: workflow, geometry: geometry,
            originalPDF: originalPDF, sourceSHA256: sourceHash,
            extraction: extraction, copyOwnership: copyOwnership, pageRangeOwnership: pageRangeOwnership,
            canvas: canvas, job: job, controls: resolved.controls, controlRequest: effectiveRequest)
    }

    public func prepare(workerExecutable: URL,
        deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()) throws -> FinishingRasterPreparation {
        let result = try FinishingRasterPreparation.prepare(job: job, controlRequest: controlRequest,
            workflowDefaults: queueDefinition.workflowDefaults, originalPDF: originalPDF, extraction: extraction,
            canvas: canvas, conversion: workflow.monochromeConversion, workerExecutable: workerExecutable,
            deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        guard result.sourceSHA256 == sourceSHA256, result.sourceByteCount == originalPDF.count,
              result.extraction == extraction, result.canvas == canvas,
              result.controls == controls else { throw Error.bindingMismatch }
        return result
    }
}
