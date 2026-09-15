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
        case sourcePageLimitExceeded(actual: Int, limit: Int)
        case pageOutOfRange(requested: Int, pageCount: Int)
        case annotationsUnsupported
        case invalidPageGeometry
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
        public let placementPolicy: PagePlacementPolicy
        public let maximumInputBytes: Int
        /// Bounds document traversal independently from the selected page and
        /// destination-pixel budget.
        public let maximumSourcePages: Int
        public let maximumPixels: Int

        public init(
            originalPDF: Data,
            pageNumber: Int,
            canvas: DotCanvas,
            annotationPolicy: AnnotationPolicy = .reject,
            placementPolicy: PagePlacementPolicy = .fit,
            maximumInputBytes: Int = 100 * 1024 * 1024,
            maximumSourcePages: Int = 1_000,
            maximumPixels: Int = 32 * 1024 * 1024
        ) {
            self.originalPDF = originalPDF
            self.pageNumber = pageNumber
            self.canvas = canvas
            self.annotationPolicy = annotationPolicy
            self.placementPolicy = placementPolicy
            self.maximumInputBytes = maximumInputBytes
            self.maximumSourcePages = maximumSourcePages
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
        guard request.maximumInputBytes > 0, request.maximumSourcePages > 0, request.maximumPixels > 0 else {
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
        guard document.numberOfPages <= request.maximumSourcePages else {
            throw Error.sourcePageLimitExceeded(actual: document.numberOfPages, limit: request.maximumSourcePages)
        }
        guard let page = document.page(at: request.pageNumber) else {
            throw Error.pageOutOfRange(requested: request.pageNumber, pageCount: document.numberOfPages)
        }
        if request.annotationPolicy == .reject, pageContainsAnnotations(page) {
            throw Error.annotationsUnsupported
        }
        let placement: PagePlacement
        do {
            placement = try PagePlacementPlanner.plan(
                source: try physicalSize(of: page),
                canvas: request.canvas,
                policy: request.placementPolicy
            )
        } catch {
            throw Error.invalidPageGeometry
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
            let target = CGRect(
                x: placement.target.x,
                y: placement.target.y,
                width: placement.target.width,
                height: placement.target.height
            )
            context.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: false))
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
        guard CGPDFDictionaryGetArray(dictionary, "Annots", &annotations),
              let annotations else { return false }
        return CGPDFArrayGetCount(annotations) > 0
    }

    private static func physicalSize(of page: CGPDFPage) throws -> PhysicalSize {
        let crop = page.getBoxRect(.cropBox)
        var userUnit: CGPDFReal = 1
        if let dictionary = page.dictionary {
            var declared: CGPDFReal = 0
            if CGPDFDictionaryGetNumber(dictionary, "UserUnit", &declared) {
                userUnit = declared
            }
        }
        let normalizedRotation = ((page.rotationAngle % 360) + 360) % 360
        return try PDFPageBox(
            originX: crop.origin.x,
            originY: crop.origin.y,
            width: crop.width,
            height: crop.height,
            rotationDegreesClockwise: Int(normalizedRotation),
            userUnit: userUnit
        ).effectivePhysicalSize()
    }
}
