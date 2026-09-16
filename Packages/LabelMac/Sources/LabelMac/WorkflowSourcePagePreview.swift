import Foundation
import LabelCore

/// Display-only source reference. Final extraction always uses original PDF
/// bytes, never this lower-resolution monochrome representation.
public struct WorkflowSourcePagePreview: Equatable, Sendable {
    public let sourcePage: Int
    public let canvas: DotCanvas
    public let bitmap: MonochromeBitmap

    public enum Error: Swift.Error, Equatable, Sendable { case invalidLimit }

    public static func render(originalPDF: Data, sourcePage: Int, pageBox: PDFPageBox,
        workerExecutable: URL, maximumDimension: Int = 1_200,
        deadlineSeconds: Double = 60,
        cancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> Self {
        guard sourcePage > 0, (64...1_200).contains(maximumDimension) else { throw Error.invalidLimit }
        let size = try pageBox.effectivePhysicalSize()
        let pitch = Double(maximumDimension) / max(size.width.value, size.height.value)
        let canvas = try DotCanvas(physicalSize: size,
            resolution: DotResolution(xDotsPerMillimeter: pitch, yDotsPerMillimeter: pitch),
            maximumWidth: 1_200, maximumHeight: 1_200, maximumByteCount: 180_000)
        let ticket = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "pageNumber": sourcePage,
            "physicalSize": ["widthMillimeters": size.width.value, "heightMillimeters": size.height.value],
            "resolution": ["xDotsPerMillimeter": pitch, "yDotsPerMillimeter": pitch],
            "conversion": ["mode": "photographicOrderedDither4x4"], "placementPolicy": "fit",
        ], options: [.sortedKeys])
        let output = try OfflineRenderWorkerProcess.run(originalPDF: originalPDF, ticketJSON: ticket,
            workerExecutable: workerExecutable, deadlineSeconds: deadlineSeconds, cancellation: cancellation)
        let bitmap = try OfflineExtractionWorker.validate(output: output, canvas: canvas)
        return Self(sourcePage: sourcePage, canvas: canvas, bitmap: bitmap)
    }
}
