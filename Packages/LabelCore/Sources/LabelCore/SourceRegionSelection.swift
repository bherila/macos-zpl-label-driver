import Foundation

/// Top-left display coordinates only. PDF origin/rotation mapping remains the
/// existing PDFPageBox contract; reference pixels never become print input.
public enum SourceRegionSelection {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidViewport
        case invalidDrag
        case emptySelection
    }

    /// The drag must start on the page. Its endpoint is visibly constrained to
    /// page edges. Reverse drags produce the same rectangle; zoom is irrelevant.
    public static func rectangle(viewportWidth: Double, viewportHeight: Double,
        startX: Double, startY: Double, endX: Double, endY: Double
    ) throws -> NormalizedRect {
        guard viewportWidth.isFinite, viewportHeight.isFinite,
              viewportWidth > 0, viewportHeight > 0 else { throw Error.invalidViewport }
        guard [startX, startY, endX, endY].allSatisfy(\.isFinite),
              (0...viewportWidth).contains(startX),
              (0...viewportHeight).contains(startY) else { throw Error.invalidDrag }
        let x = min(viewportWidth, max(0, endX))
        let y = min(viewportHeight, max(0, endY))
        let left = min(startX, x) / viewportWidth
        let right = max(startX, x) / viewportWidth
        let top = min(startY, y) / viewportHeight
        let bottom = max(startY, y) / viewportHeight
        guard right > left, bottom > top else { throw Error.emptySelection }
        return try NormalizedRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
