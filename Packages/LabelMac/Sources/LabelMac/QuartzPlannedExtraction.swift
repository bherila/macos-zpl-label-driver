import Foundation
import LabelCore

public struct PreparedExtractionLabel: Equatable, Sendable {
    public let bitmap: MonochromeBitmap
    public let zpl: Data
    public let sourcePage: Int
    public let regionID: String
    public let profileID: String
    public let profileRevision: Int

    /// This is a serialization of the same packed bitmap passed to the
    /// encoder, not a separately rendered preview.
    public var previewPBM: Data { bitmap.pbmData() }
}

/// Renders one immutable extraction-plan item from the original PDF directly
/// into the final dot canvas. Analysis thumbnails are not an input type here.
public enum QuartzPlannedExtraction {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedOutputMargins
        case outputStockMismatch
    }

    public static func prepare(
        originalPDF: Data,
        label: PlannedExtractionLabel,
        canvas: DotCanvas,
        conversion: MonochromeConversion,
        maximumInputBytes: Int = 100 * 1024 * 1024,
        maximumSourcePages: Int = 1_000,
        maximumPixels: Int = 32 * 1024 * 1024
    ) throws -> PreparedExtractionLabel {
        guard label.outputMargins == .zero else { throw Error.unsupportedOutputMargins }
        guard canvas.physicalSize == label.outputStock else { throw Error.outputStockMismatch }
        let grayscale = try QuartzPDFRenderer.render(.init(
            originalPDF: originalPDF,
            pageNumber: label.sourcePage,
            canvas: canvas,
            placementPolicy: .fit,
            sourceRegion: label.normalizedRect,
            regionRotation: label.rotation,
            expectedSourceRect: label.sourceRect,
            maximumInputBytes: maximumInputBytes,
            maximumSourcePages: maximumSourcePages,
            maximumPixels: maximumPixels
        ))
        let bitmap = try conversion.convert(
            width: grayscale.width,
            height: grayscale.height,
            grayscale: grayscale.pixels,
            stride: grayscale.bytesPerRow,
            maxByteCount: canvas.bitmapLayout.byteCount
        )
        return PreparedExtractionLabel(
            bitmap: bitmap,
            zpl: try ZPLGraphicEncoder().diagnosticFormat(bitmap),
            sourcePage: label.sourcePage,
            regionID: label.regionID,
            profileID: label.profileID,
            profileRevision: label.profileRevision
        )
    }
}
