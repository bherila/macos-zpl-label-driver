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
        /// Optional extraction region in the visually upright crop box. The
        /// page remains the original PDF; this never accepts analysis pixels.
        public let sourceRegion: NormalizedRect?
        public let regionRotation: ExtractionRotation
        /// When supplied by an immutable plan, the renderer re-derives and
        /// checks the source rectangle against the actual PDF page geometry.
        public let expectedSourceRect: PDFSourceRect?
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
            sourceRegion: NormalizedRect? = nil,
            regionRotation: ExtractionRotation = .degrees0,
            expectedSourceRect: PDFSourceRect? = nil,
            maximumInputBytes: Int = 100 * 1024 * 1024,
            maximumSourcePages: Int = 1_000,
            maximumPixels: Int = 32 * 1024 * 1024
        ) {
            self.originalPDF = originalPDF
            self.pageNumber = pageNumber
            self.canvas = canvas
            self.annotationPolicy = annotationPolicy
            self.placementPolicy = placementPolicy
            self.sourceRegion = sourceRegion
            self.regionRotation = regionRotation
            self.expectedSourceRect = expectedSourceRect
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

    /// Reads the canonical crop-box geometry without rasterizing. The same
    /// bounded document-opening path is shared with `render`.
    public static func pageBox(
        originalPDF: Data,
        pageNumber: Int,
        maximumInputBytes: Int = 100 * 1024 * 1024,
        maximumSourcePages: Int = 1_000
    ) throws -> PDFPageBox {
        guard maximumInputBytes > 0, maximumSourcePages > 0 else { throw Error.invalidLimits }
        let (_, page) = try openPage(
            originalPDF: originalPDF,
            pageNumber: pageNumber,
            maximumInputBytes: maximumInputBytes,
            maximumSourcePages: maximumSourcePages
        )
        do {
            return try geometry(of: page)
        } catch {
            throw Error.invalidPageGeometry
        }
    }

    public static func documentPageBoxes(
        originalPDF: Data,
        maximumInputBytes: Int = 100 * 1024 * 1024,
        maximumSourcePages: Int = 1_000
    ) throws -> [PDFPageBox] {
        guard maximumInputBytes > 0, maximumSourcePages > 0 else { throw Error.invalidLimits }
        guard originalPDF.count <= maximumInputBytes else {
            throw Error.inputTooLarge(actual: originalPDF.count, limit: maximumInputBytes)
        }
        guard let provider = CGDataProvider(data: originalPDF as CFData),
              let document = CGPDFDocument(provider) else {
            throw Error.malformedOrUnsupportedPDF
        }
        guard !document.isEncrypted || document.isUnlocked else { throw Error.encryptedPDF }
        guard document.numberOfPages > 0, document.numberOfPages <= maximumSourcePages else {
            throw Error.sourcePageLimitExceeded(actual: document.numberOfPages, limit: maximumSourcePages)
        }
        return try (1...document.numberOfPages).map { pageNumber in
            guard let page = document.page(at: pageNumber) else {
                throw Error.pageOutOfRange(requested: pageNumber, pageCount: document.numberOfPages)
            }
            do { return try geometry(of: page) }
            catch { throw Error.invalidPageGeometry }
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
        let (_, page) = try openPage(
            originalPDF: request.originalPDF,
            pageNumber: request.pageNumber,
            maximumInputBytes: request.maximumInputBytes,
            maximumSourcePages: request.maximumSourcePages
        )
        if request.annotationPolicy == .reject, pageContainsAnnotations(page) {
            throw Error.annotationsUnsupported
        }
        let pageBox: PDFPageBox
        let placement: PagePlacement
        do {
            pageBox = try geometry(of: page)
            if let expected = request.expectedSourceRect {
                guard let region = request.sourceRegion,
                      rectanglesEqual(pageBox.sourceRect(for: region), expected) else {
                    throw Error.invalidPageGeometry
                }
            }
            var sourceSize = try pageBox.effectivePhysicalSize()
            if let region = request.sourceRegion {
                sourceSize = PhysicalSize(
                    width: try Millimeters(sourceSize.width.value * region.width),
                    height: try Millimeters(sourceSize.height.value * region.height)
                )
            }
            if request.regionRotation == .degrees90 || request.regionRotation == .degrees270 {
                sourceSize = PhysicalSize(width: sourceSize.height, height: sourceSize.width)
            }
            placement = try PagePlacementPlanner.plan(
                source: sourceSize,
                canvas: request.canvas,
                policy: request.placementPolicy
            )
        } catch {
            throw Error.invalidPageGeometry
        }
        let target = CGRect(
            x: placement.target.x,
            // The planner owns top-down dot coordinates; Quartz draws bottom-up.
            y: request.canvas.height - placement.target.y - placement.target.height,
            width: placement.target.width,
            height: placement.target.height
        )
        let unrotatedTarget = unrotatedTarget(for: target, rotation: request.regionRotation)
        let fullTarget: CGRect
        do {
            fullTarget = try fullPageTarget(for: request.sourceRegion, selectedTarget: unrotatedTarget)
        } catch {
            throw Error.invalidPageGeometry
        }
        let drawingTransform: CGAffineTransform
        if let region = request.sourceRegion {
            let selected = pageBox.sourceRect(for: region)
            drawingTransform = try plannedDrawingTransform(page: page, target: unrotatedTarget,
                selectedSource: CGRect(x: selected.x, y: selected.y,
                    width: selected.width, height: selected.height))
        } else {
            drawingTransform = try plannedDrawingTransform(page: page, target: fullTarget)
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
            context.clip(to: target)
            rotateContext(context, around: CGPoint(x: target.midX, y: target.midY), rotation: request.regionRotation)
            context.concatenate(drawingTransform)
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

    private static func openPage(
        originalPDF: Data,
        pageNumber: Int,
        maximumInputBytes: Int,
        maximumSourcePages: Int
    ) throws -> (CGPDFDocument, CGPDFPage) {
        guard originalPDF.count <= maximumInputBytes else {
            throw Error.inputTooLarge(actual: originalPDF.count, limit: maximumInputBytes)
        }
        guard pageNumber > 0,
              let provider = CGDataProvider(data: originalPDF as CFData),
              let document = CGPDFDocument(provider) else {
            throw Error.malformedOrUnsupportedPDF
        }
        guard !document.isEncrypted || document.isUnlocked else { throw Error.encryptedPDF }
        guard document.numberOfPages <= maximumSourcePages else {
            throw Error.sourcePageLimitExceeded(actual: document.numberOfPages, limit: maximumSourcePages)
        }
        guard let page = document.page(at: pageNumber) else {
            throw Error.pageOutOfRange(requested: pageNumber, pageCount: document.numberOfPages)
        }
        return (document, page)
    }

    private static func geometry(of page: CGPDFPage) throws -> PDFPageBox {
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
        )
    }

    private static func fullPageTarget(
        for region: NormalizedRect?,
        selectedTarget: CGRect
    ) throws -> CGRect {
        guard let region else { return selectedTarget }
        let width = selectedTarget.width / region.width
        let height = selectedTarget.height / region.height
        let result = CGRect(
            x: selectedTarget.minX - region.x * width,
            y: selectedTarget.minY - (1 - region.y - region.height) * height,
            width: width,
            height: height
        )
        let values = [result.minX, result.minY, result.width, result.height]
        guard values.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000_000 }) else {
            throw Error.invalidPageGeometry
        }
        return result
    }

    /// Keep Quartz's crop/media intersection and page rotation, but explicitly
    /// map its resulting rectangle to the planner's independently rounded X/Y
    /// dot extent. The observed native drawing transform is not relied on to
    /// enlarge a page. These affine operations compose before one rasterization.
    private static func plannedDrawingTransform(
        page: CGPDFPage, target: CGRect, selectedSource: CGRect? = nil
    ) throws -> CGAffineTransform {
        let effective = page.getBoxRect(.cropBox).intersection(page.getBoxRect(.mediaBox))
        guard !effective.isNull, !effective.isEmpty else { throw Error.invalidPageGeometry }
        let quarterTurn = page.rotationAngle % 180 != 0
        let upright = CGRect(x: 0, y: 0,
            width: quarterTurn ? effective.height : effective.width,
            height: quarterTurn ? effective.width : effective.height)
        let base = page.getDrawingTransform(.cropBox, rect: upright, rotate: 0, preserveAspectRatio: true)
        // Map the selected original-space rectangle directly. Expanding a
        // normalized crop into a synthetic full-sheet target and then dividing
        // it by the full page introduces avoidable rounding in the final scale.
        // The preceding fullPageTarget check still bounds near-zero regions.
        let mapped = (selectedSource ?? effective).applying(base)
        guard [mapped.minX, mapped.minY, mapped.width, mapped.height].allSatisfy(\.isFinite),
              mapped.width > 0, mapped.height > 0 else { throw Error.invalidPageGeometry }
        let sx = target.width / mapped.width, sy = target.height / mapped.height
        let correction = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
            tx: target.minX - mapped.minX * sx, ty: target.minY - mapped.minY * sy)
        let result = base.concatenating(correction)
        guard [result.a, result.b, result.c, result.d, result.tx, result.ty].allSatisfy(\.isFinite),
              (result.a * result.d - result.b * result.c).isFinite,
              result.a * result.d - result.b * result.c != 0 else { throw Error.invalidPageGeometry }
        return result
    }

    private static func unrotatedTarget(for target: CGRect, rotation: ExtractionRotation) -> CGRect {
        switch rotation {
        case .degrees0, .degrees180:
            return target
        case .degrees90, .degrees270:
            return CGRect(
                x: target.midX - target.height / 2,
                y: target.midY - target.width / 2,
                width: target.height,
                height: target.width
            )
        }
    }

    private static func rotateContext(
        _ context: CGContext,
        around center: CGPoint,
        rotation: ExtractionRotation
    ) {
        guard rotation != .degrees0 else { return }
        context.translateBy(x: center.x, y: center.y)
        // Quartz coordinates are bottom-up; negative is visually clockwise.
        context.rotate(by: -CGFloat(rotation.rawValue) * .pi / 180)
        context.translateBy(x: -center.x, y: -center.y)
    }

    private static func rectanglesEqual(_ lhs: PDFSourceRect, _ rhs: PDFSourceRect) -> Bool {
        let tolerance = 1e-7
        return abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
