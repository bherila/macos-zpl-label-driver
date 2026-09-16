import Foundation
import LabelCore

/// Produces bounded analysis facts from an original PDF page. The returned
/// anchors can validate a profile, but the analysis bitmap is not exposed as a
/// rendering input.
public enum QuartzStructuralAnalyzer {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimits
    }

    public static func analyzeBorders(
        originalPDF: Data,
        pageNumber: Int,
        maximumDimension: Int = 512,
        maximumInputBytes: Int = 100 * 1024 * 1024,
        maximumSourcePages: Int = 1_000
    ) throws -> AnalyzedSourcePage {
        let (pageBox, grayscale) = try analysisRaster(originalPDF: originalPDF,
            pageNumber: pageNumber, maximumDimension: maximumDimension,
            maximumInputBytes: maximumInputBytes, maximumSourcePages: maximumSourcePages)
        let anchors = try StructuralAnchorAnalyzer.analyzeBorders(.init(
            width: grayscale.width,
            height: grayscale.height,
            bytesPerRow: grayscale.bytesPerRow,
            pixels: grayscale.pixels
        ))
        return try AnalyzedSourcePage(pageBox: pageBox, anchors: anchors)
    }

    /// Shared original-document raster boundary for analysis adapters, never final output.
    static func analysisRaster(originalPDF: Data, pageNumber: Int, maximumDimension: Int,
        maximumInputBytes: Int, maximumSourcePages: Int
    ) throws -> (PDFPageBox, QuartzPDFRenderer.GrayscaleBitmap) {
        // These are hard ceilings, not caller-raisable defaults.
        guard (32...1_024).contains(maximumDimension),
              (1...(100 * 1024 * 1024)).contains(maximumInputBytes),
              (1...1_000).contains(maximumSourcePages) else {
            throw Error.invalidLimits
        }
        let pageBox = try QuartzPDFRenderer.pageBox(
            originalPDF: originalPDF,
            pageNumber: pageNumber,
            maximumInputBytes: maximumInputBytes,
            maximumSourcePages: maximumSourcePages
        )
        let physical = try pageBox.effectivePhysicalSize()
        let dotsPerMillimeter = Double(maximumDimension) /
            max(physical.width.value, physical.height.value)
        let canvas = try DotCanvas(
            physicalSize: physical,
            resolution: DotResolution(
                xDotsPerMillimeter: dotsPerMillimeter,
                yDotsPerMillimeter: dotsPerMillimeter
            ),
            maximumWidth: maximumDimension,
            maximumHeight: maximumDimension,
            maximumByteCount: 128 * 1024
        )
        let grayscale = try QuartzPDFRenderer.render(.init(
            originalPDF: originalPDF,
            pageNumber: pageNumber,
            canvas: canvas,
            maximumInputBytes: maximumInputBytes,
            maximumSourcePages: maximumSourcePages,
            maximumPixels: 1_048_576
        ))
        return (pageBox, grayscale)
    }
}
