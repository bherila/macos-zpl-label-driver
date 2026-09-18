import CoreGraphics
import Foundation
import LabelCore
import Vision

/// Local barcode-location candidates, not decoded values or shipping-label bounds.
/// Production callers run this inside the deadline-supervised analysis child:
/// the synchronous Vision framework call itself has no claimed wall-clock bound.
enum QuartzBarcodeAnalyzer {
    enum Error: Swift.Error, Equatable, Sendable {
        case detectorUnavailable
        case invalidObservation
        case observationLimitExceeded
    }

    static let maximumObservations = 64

    static func analyze(originalPDF: Data, pageNumber: Int,
        maximumInputBytes: Int, maximumSourcePages: Int
    ) throws -> AnalyzedSourcePage {
        let (box, raster) = try QuartzStructuralAnalyzer.analysisRaster(
            originalPDF: originalPDF, pageNumber: pageNumber, maximumDimension: 1_024,
            maximumInputBytes: maximumInputBytes, maximumSourcePages: maximumSourcePages)
        guard let provider = CGDataProvider(data: raster.pixels as CFData),
              let image = CGImage(width: raster.width, height: raster.height,
                bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: raster.bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: .init(rawValue: 0),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent) else { throw Error.detectorUnavailable }
        let request = VNDetectBarcodesRequest()
        // Revision is pinned before selecting the intentionally narrow symbology set.
        request.revision = VNDetectBarcodesRequestRevision3
        let symbologies: [VNBarcodeSymbology] = [.code128, .qr]
        do {
            let supported = try request.supportedSymbologies()
            guard symbologies.allSatisfy({ supported.contains($0) }) else {
                throw Error.detectorUnavailable
            }
            request.symbologies = symbologies
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch { throw Error.detectorUnavailable }
        guard let observations = request.results else { throw Error.detectorUnavailable }
        guard observations.count <= maximumObservations else { throw Error.observationLimitExceeded }
        // Never read payloadStringValue, payloadData, descriptors, or framework diagnostics.
        let anchors = try observations.map { observation in
            guard symbologies.contains(observation.symbology) else { throw Error.invalidObservation }
            return ObservedPageAnchor(kind: .barcodeLike,
                normalizedRect: try canonicalRectangle(visionLowerLeft: observation.boundingBox))
        }.sorted { lhs, rhs in
            let a = lhs.normalizedRect, b = rhs.normalizedRect
            if a.y != b.y { return a.y < b.y }
            if a.x != b.x { return a.x < b.x }
            if a.width != b.width { return a.width < b.width }
            return a.height < b.height
        }
        return try AnalyzedSourcePage(pageBox: box, anchors: anchors)
    }

    static func canonicalRectangle(visionLowerLeft rect: CGRect) throws -> LabelCore.NormalizedRect {
        let x = Double(rect.origin.x), y = Double(rect.origin.y)
        let width = Double(rect.size.width), height = Double(rect.size.height)
        guard [x, y, width, height].allSatisfy(\.isFinite),
              x >= 0, y >= 0, width > 0, height > 0,
              x + width <= 1, y + height <= 1 else { throw Error.invalidObservation }
        // Quartz's supplied raster is top-to-bottom; Vision boxes use lower-left origin.
        do { return try LabelCore.NormalizedRect(x: x, y: 1 - (y + height), width: width, height: height) }
        catch { throw Error.invalidObservation }
    }
}
