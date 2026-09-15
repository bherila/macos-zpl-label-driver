import CoreGraphics
import Foundation
import LabelCore

/// Bounded original-PDF renderer. It produces grayscale pixels only; conversion
/// to packed monochrome and any transport are intentionally separate stages.
public enum QuartzPDFRenderer {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimits
        case inputTooLarge(actual: Int, limit: Int)
        case malformedOrUnsupportedPDF
        case encryptedPDF
        case pageOutOfRange(requested: Int, pageCount: Int)
        case annotationsUnsupported
        case pixelLimitExceeded(actual: Int, limit: Int)
        case allocationOverflow
        case contextUnavailable
    }

    public enum AnnotationPolicy: Sendable {
        /// Core Graphics page drawing does not establish annotation appearance
        /// fidelity. Reject an annotated page rather than silently omitting it.
        case reject
    }

    public struct Request: Sendable {
        public let originalPDF: Data
        /// PDF page numbering is one-based, matching Core Graphics and CUPS.
        public let pageNumber: Int
        public let canvas: DotCanvas
        public let annotationPolicy: AnnotationPolicy
        public let maximumInputBytes: Int
        public let maximumPixels: Int

        public init(
            originalPDF: Data,
            pageNumber: Int,
            canvas: DotCanvas,
            annotationPolicy: AnnotationPolicy = .reject,
            maximumInputBytes: Int = 100 * 1024 * 1024,
            maximumPixels: Int = 32 * 1024 * 1024
        ) {
            self.originalPDF = originalPDF
            self.pageNumber = pageNumber
            self.canvas = canvas
            self.annotationPolicy = annotationPolicy
            self.maximumInputBytes = maximumInputBytes
            self.maximumPixels = maximumPixels
        }
    }

    /// Top-to-bottom grayscale pixels: 0 is black and 255 is white.
    public struct GrayscaleBitmap: Equatable, Sendable {
        public let width: Int
        public let height: Int
        public let bytesPerRow: Int
        public let pixels: Data

        public init(width: Int, height: Int, bytesPerRow: Int, pixels: Data) {
            self.width = width
            self.height = height
            self.bytesPerRow = bytesPerRow
            self.pixels = pixels
        }
    }

    public static func render(_ request: Request) throws -> GrayscaleBitmap {
        guard request.maximumInputBytes > 0, request.maximumPixels > 0 else {
            throw Error.invalidLimits
        }
        guard request.originalPDF.count <= request.maximumInputBytes else {
            throw Error.inputTooLarge(actual: request.originalPDF.count, limit: request.maximumInputBytes)
        }
        let (pixels, pixelOverflow) = request.canvas.width.multipliedReportingOverflow(by: request.canvas.height)
        guard !pixelOverflow else { throw Error.allocationOverflow }
        guard pixels <= request.maximumPixels else {
            throw Error.pixelLimitExceeded(actual: pixels, limit: request.maximumPixels)
        }
        guard request.pageNumber > 0,
              let provider = CGDataProvider(data: request.originalPDF as CFData),
              let document = CGPDFDocument(provider) else {
            throw Error.malformedOrUnsupportedPDF
        }
        guard !document.isEncrypted || document.isUnlocked else { throw Error.encryptedPDF }
        guard let page = document.page(at: request.pageNumber) else {
            throw Error.pageOutOfRange(requested: request.pageNumber, pageCount: document.numberOfPages)
        }
        if request.annotationPolicy == .reject, pageContainsAnnotations(page) {
            throw Error.annotationsUnsupported
        }
        let byteCount = pixels
        var storage = Data(repeating: 0, count: byteCount)
        let result: Bool = storage.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: request.canvas.width,
                height: request.canvas.height,
                bitsPerComponent: 8,
                bytesPerRow: request.canvas.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: request.canvas.width, height: request.canvas.height))
            // Quartz bitmap storage is exposed top-to-bottom for this context;
            // keep PDF's drawing transform in its native coordinate space.
            context.interpolationQuality = .high
            context.setShouldAntialias(true)
            let target = CGRect(x: 0, y: 0, width: request.canvas.width, height: request.canvas.height)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            return true
        }
        guard result else { throw Error.contextUnavailable }
        return GrayscaleBitmap(
            width: request.canvas.width,
            height: request.canvas.height,
            bytesPerRow: request.canvas.width,
            pixels: storage
        )
    }

    private static func pageContainsAnnotations(_ page: CGPDFPage) -> Bool {
        guard let dictionary = page.dictionary else { return false }
        var annotations: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(dictionary, "Annots", &annotations)
    }
}
