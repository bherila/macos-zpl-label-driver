import Foundation
import LabelCore

/// Bounded subprocess rendering of one immutable plan item. Printer controls
/// remain in the parent, after validation of the exact returned packed bitmap.
public enum OfflineExtractionWorker {
    public enum Error: Swift.Error, Equatable, Sendable {
        case outputStockMismatch
        case invalidWorkerBitmap
    }

    public static func render(
        originalPDF: Data, label: PlannedExtractionLabel, canvas: DotCanvas,
        conversion: MonochromeConversion, workerExecutable: URL,
        deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> MonochromeBitmap {
        let ticket = try ticketJSON(label: label, canvas: canvas, conversion: conversion)
        let output = try OfflineRenderWorkerProcess.run(originalPDF: originalPDF,
            ticketJSON: ticket, workerExecutable: workerExecutable,
            deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        return try validate(output: output, canvas: canvas)
    }

    /// Builds the immutable wire ticket staged for one child. Separated from
    /// `render` so the schema branch is testable without spawning a worker.
    static func ticketJSON(label: PlannedExtractionLabel, canvas: DotCanvas,
                           conversion: MonochromeConversion) throws -> Data {
        guard canvas.physicalSize == label.outputStock else { throw Error.outputStockMismatch }
        let conversionWire: [String: Any]
        switch conversion {
        case let .textAndBarcodeThreshold(cutoff):
            conversionWire = ["mode": "textAndBarcodeThreshold", "cutoff": Int(cutoff)]
        case .photographicOrderedDither4x4:
            conversionWire = ["mode": "photographicOrderedDither4x4"]
        }
        let region = label.normalizedRect
        let expected = label.sourceRect
        var wire: [String: Any] = [
            "schemaVersion": label.outputMargins == .zero ? 2 : 3, "pageNumber": label.sourcePage,
            "physicalSize": ["widthMillimeters": canvas.physicalSize.width.value,
                             "heightMillimeters": canvas.physicalSize.height.value],
            "resolution": ["xDotsPerMillimeter": canvas.resolution.xDotsPerMillimeter,
                           "yDotsPerMillimeter": canvas.resolution.yDotsPerMillimeter],
            "conversion": conversionWire, "placementPolicy": "fit",
            "extraction": [
                "region": ["x": region.x, "y": region.y, "width": region.width, "height": region.height],
                "expectedSourceRect": ["x": expected.x, "y": expected.y,
                                       "width": expected.width, "height": expected.height],
                "rotation": label.rotation.rawValue,
            ],
        ]
        if label.outputMargins != .zero {
            let margins = label.outputMargins
            wire["outputMargins"] = ["left": margins.left, "top": margins.top,
                "right": margins.right, "bottom": margins.bottom]
        }
        return try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])
    }

    static func validate(output: OfflineRenderWorkerOutput, canvas: DotCanvas) throws -> MonochromeBitmap {
        guard output.result.widthDots == canvas.width, output.result.heightDots == canvas.height else {
            throw Error.invalidWorkerBitmap
        }
        do {
            return try WorkerBitmapBinding.validate(output, maximumPackedBytes: canvas.bitmapLayout.byteCount)
        } catch { throw Error.invalidWorkerBitmap }
    }
}
