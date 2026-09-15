import Foundation
import LabelCore

/// The final document-imaging boundary: original PDF bytes become the one-bit
/// buffer used by the encoder. This performs no scaling beyond Quartz's draw
/// into the requested physical dot canvas, no I/O, and no preview rendering.
public enum QuartzPDFToMonochrome {
    /// Applies the documented deterministic threshold after native rendering.
    /// The source bitmap's width, height, and stride are preserved exactly.
    public static func render(
        _ request: QuartzPDFRenderer.Request,
        threshold: UInt8 = 128,
        maxByteCount: Int = 16 * 1024 * 1024
    ) throws -> MonochromeBitmap {
        let grayscale = try QuartzPDFRenderer.render(request)
        return try MonochromeBitmap.threshold(
            width: grayscale.width,
            height: grayscale.height,
            grayscale: grayscale.pixels,
            stride: grayscale.bytesPerRow,
            threshold: threshold,
            maxByteCount: maxByteCount
        )
    }
}
