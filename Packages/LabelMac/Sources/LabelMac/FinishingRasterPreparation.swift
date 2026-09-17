import CryptoKit
import Foundation
import LabelCore

/// Original-document rendering for an offline finishing intention. Construction
/// owns the worker inputs and retains their complete extraction order. This is
/// not an accepted scheduler ticket or authority for mechanical transmission.
public struct FinishingRasterPreparation: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimit, sourceLimit, planMismatch, canvasMismatch, rasterLimit
        case byteLimit, timedOut, cancelled, bindingMismatch
    }
    public let sourceSHA256: String
    public let sourceByteCount: Int
    public let extraction: ExtractionPlan
    public let canvas: DotCanvas
    public let conversion: MonochromeConversion
    public let rasters: [MonochromeBitmap]
    public let binding: FinishingRasterBinding
    public let normalization: FinishingControlNormalization
    public var controls: ResolvedPrinterControls { normalization.controls }

    public static func prepare(
        job: ProfileBoundFinishingJobPlan, controlRequest: PrinterControlRequest = .init(),
        workflowDefaults: PrinterControlDefaults = .init(), originalPDF: Data, extraction: ExtractionPlan,
        canvas: DotCanvas, conversion: MonochromeConversion, workerExecutable: URL,
        maximumPackedBytes: Int = FinishingRasterBinding.maximumTotalBytes,
        deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> Self {
        guard deadlineSeconds.isFinite, deadlineSeconds > 0,
              deadlineSeconds <= OfflineRenderWorkerProcess.defaultDeadlineSeconds,
              (1...FinishingRasterBinding.maximumTotalBytes).contains(maximumPackedBytes) else {
            throw Error.invalidLimit
        }
        guard !originalPDF.isEmpty, originalPDF.count <= OfflineConversion.maximumInputBytes else {
            throw Error.sourceLimit
        }
        guard extraction.outputLabels.count == job.plan.outputLabelCount else { throw Error.planMismatch }
        guard extraction.outputLabels.allSatisfy({ $0.outputStock == canvas.physicalSize }) else {
            throw Error.canvasMismatch
        }
        let (pixels, pixelOverflow) = canvas.width.multipliedReportingOverflow(by: canvas.height)
        guard !pixelOverflow, pixels <= 32 * 1024 * 1024,
              canvas.width <= 8192, canvas.height <= 65535 else { throw Error.rasterLimit }
        let (bytes, byteOverflow) = canvas.bitmapLayout.byteCount.multipliedReportingOverflow(
            by: extraction.outputLabels.count)
        guard !byteOverflow, bytes <= maximumPackedBytes else { throw Error.byteLimit }
        let normalization = try ZPLControlEncoder().prepareFinishingNormalization(profile: job.printer.profile,
            plan: job.plan, job: controlRequest, workflowDefaults: workflowDefaults)
        let controls = normalization.controls
        let start = DispatchTime.now().uptimeNanoseconds
        func remaining() throws -> Double {
            guard !cancellation.isCancelled else { throw Error.cancelled }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            let value = deadlineSeconds - elapsed
            guard value > 0 else { throw Error.timedOut }
            return value
        }
        // Observe every source page in the isolated worker, including accounted
        // non-label pages. A different page count cannot silently discard input.
        let pages = try OfflineLayoutWorker.analyze(originalPDF: originalPDF, structuralPages: [],
            workerExecutable: workerExecutable, deadlineSeconds: remaining(), cancellation: cancellation)
        guard pages.count == extraction.sourcePageCount else { throw Error.planMismatch }
        var rasters: [MonochromeBitmap] = []
        rasters.reserveCapacity(extraction.outputLabels.count)
        for label in extraction.outputLabels {
            let bitmap = try OfflineExtractionWorker.render(originalPDF: originalPDF,
                label: label, canvas: canvas, conversion: conversion, workerExecutable: workerExecutable,
                deadlineSeconds: remaining(), cancellation: cancellation)
            if case let .value(geometry) = controls.mediaGeometry {
                let offsets: OffsetControlRequest?
                if case let .value(value) = controls.offsets { offsets = value } else { offsets = nil }
                let tracking: MediaTracking?
                if case let .value(value) = controls.tracking { tracking = value } else { tracking = nil }
                try job.printer.profile.capabilities.physicalGeometry.validateRaster(bitmap, request: geometry,
                    tracking: tracking, trackingFact: job.printer.profile.capabilities.tracking[.continuous]
                        ?? .init(state: .unknown, evidence: .unobserved), offsets: offsets)
            }
            rasters.append(bitmap)
        }
        let binding = try FinishingRasterBinding(job: job, orderedRasters: rasters,
            maximumTotalBytes: maximumPackedBytes, cancellation: cancellation)
        let sourceHash = hash(originalPDF)
        _ = try remaining()
        return Self(sourceSHA256: sourceHash, sourceByteCount: originalPDF.count,
            extraction: extraction, canvas: canvas, conversion: conversion, rasters: rasters, binding: binding, normalization: normalization)
    }

    public func validateSource(originalPDF: Data, extraction: ExtractionPlan,
                               canvas: DotCanvas, conversion: MonochromeConversion) throws {
        guard originalPDF.count == sourceByteCount, Self.hash(originalPDF) == sourceSHA256,
              self.extraction == extraction, self.canvas == canvas, self.conversion == conversion else {
            throw Error.bindingMismatch
        }
    }

    /// Re-resolves only against the retained immutable profile and policy. A
    /// later draft or new revision cannot replace this preparation's controls.
    public func validateControls(job: PrinterControlRequest,
                                 workflowDefaults: PrinterControlDefaults = .init()) throws {
        let expected = try binding.job.printer.profile.resolveFinishingControls(
            plan: binding.job.plan, job: job, workflowDefaults: workflowDefaults)
        guard expected == controls else { throw Error.bindingMismatch }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
