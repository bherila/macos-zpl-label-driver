import Foundation

/// Explicit one-bit conversion policies. A job chooses one policy for a
/// content class; callers must not silently dither text or barcode regions.
public enum MonochromeConversion: Equatable, Sendable {
    /// For text and barcode imagery, a sample strictly below `cutoff` is black.
    case textAndBarcodeThreshold(cutoff: UInt8)
    /// For continuous-tone imagery, use the fixed 4×4 Bayer screen below.
    /// Its phase is anchored at the top-left printer dot, so output is stable.
    case photographicOrderedDither4x4

    /// Converts top-to-bottom opaque grayscale data into canonical packed bits.
    /// The source has already been composited onto white by the rendering layer.
    public func convert(
        width: Int,
        height: Int,
        grayscale: Data,
        stride: Int,
        maxByteCount: Int = 16 * 1024 * 1024
    ) throws -> MonochromeBitmap {
        switch self {
        case let .textAndBarcodeThreshold(cutoff):
            return try MonochromeBitmap.threshold(
                width: width,
                height: height,
                grayscale: grayscale,
                stride: stride,
                threshold: cutoff,
                maxByteCount: maxByteCount
            )
        case .photographicOrderedDither4x4:
            let layout = try BitmapLayout(width: width, height: height, maxByteCount: maxByteCount)
            guard stride >= width else { throw MonochromeBitmap.ValidationError.invalidGrayscaleStride }
            let (required, overflow) = stride.multipliedReportingOverflow(by: height)
            guard !overflow, required == grayscale.count else {
                throw MonochromeBitmap.ValidationError.invalidGrayscaleLength
            }
            var packed = [UInt8](repeating: 0, count: layout.byteCount)
            // Values 0...15 specify the standard 4×4 Bayer rank. Adding 8
            // produces thresholds 8,24,...,248, retaining pure white/black.
            let ranks: [UInt8] = [0, 8, 2, 10,
                                  12, 4, 14, 6,
                                  3, 11, 1, 9,
                                  15, 7, 13, 5]
            for y in 0..<height {
                for x in 0..<width {
                    let threshold = ranks[(y & 3) * 4 + (x & 3)] * 16 + 8
                    let sourceIndex = grayscale.index(grayscale.startIndex, offsetBy: y * stride + x)
                    if grayscale[sourceIndex] < threshold {
                        packed[y * layout.bytesPerRow + x / 8] |= UInt8(0x80 >> (x % 8))
                    }
                }
            }
            return try MonochromeBitmap(
                width: width,
                height: height,
                bytes: packed,
                maxByteCount: maxByteCount
            )
        }
    }
}
