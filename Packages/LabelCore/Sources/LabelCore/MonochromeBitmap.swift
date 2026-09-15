import Foundation

/// Canonical packed bitmap: top-to-bottom rows, MSB first, 1 = black.
/// This value contains no printer configuration and performs no I/O.
public struct MonochromeBitmap: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case wrongByteCount(expected: Int, actual: Int)
        case nonzeroPadding(row: Int)
        case invalidGrayscaleStride
        case invalidGrayscaleLength
    }
    public let layout: BitmapLayout
    public let bytes: [UInt8]

    /// An exact display-oriented expansion of the packed bitmap. This is not a
    /// rendering result: each source bit maps directly to one grayscale pixel.
    public struct GrayscalePreview: Equatable, Sendable {
        public let width: Int
        public let height: Int
        public let bytesPerRow: Int
        /// Top-to-bottom rows; 0 is black and 255 is white.
        public let pixels: [UInt8]
    }

    public init(width: Int, height: Int, bytes: [UInt8], maxByteCount: Int = 16 * 1024 * 1024) throws {
        let layout = try BitmapLayout(width: width, height: height, maxByteCount: maxByteCount)
        guard bytes.count == layout.byteCount else {
            throw ValidationError.wrongByteCount(expected: layout.byteCount, actual: bytes.count)
        }
        let used = width % 8
        if used != 0 {
            let mask = UInt8((1 << (8 - used)) - 1)
            for row in 0..<height where bytes[(row + 1) * layout.bytesPerRow - 1] & mask != 0 {
                throw ValidationError.nonzeroPadding(row: row)
            }
        }
        self.layout = layout
        self.bytes = bytes
    }

    /// Input is already flattened opaque grayscale, with 0 = black, 255 = white.
    /// A sample strictly BELOW threshold is black; equality is white.
    /// The caller owns color conversion/alpha flattening. No sharpening or dithering.
    public static func threshold(
        width: Int, height: Int, grayscale: [UInt8], stride: Int,
        threshold: UInt8 = 128, maxByteCount: Int = 16 * 1024 * 1024
    ) throws -> Self {
        try thresholdBytes(
            width: width,
            height: height,
            grayscale: grayscale,
            stride: stride,
            threshold: threshold,
            maxByteCount: maxByteCount
        )
    }

    /// Data-backed form for native image buffers. The bytes are read directly;
    /// callers do not need to materialize an array only to pack it again.
    public static func threshold(
        width: Int, height: Int, grayscale: Data, stride: Int,
        threshold: UInt8 = 128, maxByteCount: Int = 16 * 1024 * 1024
    ) throws -> Self {
        try thresholdBytes(
            width: width,
            height: height,
            grayscale: grayscale,
            stride: stride,
            threshold: threshold,
            maxByteCount: maxByteCount
        )
    }

    private static func thresholdBytes<Bytes: RandomAccessCollection>(
        width: Int, height: Int, grayscale: Bytes, stride: Int,
        threshold: UInt8, maxByteCount: Int
    ) throws -> Self where Bytes.Element == UInt8, Bytes.Index == Int {
        let layout = try BitmapLayout(width: width, height: height, maxByteCount: maxByteCount)
        guard stride >= width else { throw ValidationError.invalidGrayscaleStride }
        let (required, overflow) = stride.multipliedReportingOverflow(by: height)
        guard !overflow, required == grayscale.count else { throw ValidationError.invalidGrayscaleLength }
        var packed = [UInt8](repeating: 0, count: layout.byteCount)
        for y in 0..<height {
            for x in 0..<width where grayscale[grayscale.index(grayscale.startIndex, offsetBy: y * stride + x)] < threshold {
                packed[y * layout.bytesPerRow + x / 8] |= UInt8(0x80 >> (x % 8))
            }
        }
        return try Self(width: width, height: height, bytes: packed, maxByteCount: maxByteCount)
    }

    /// Exact packed-data preview. No rerendering or resampling is performed.
    public func pbmData() -> Data {
        var data = Data("P4\n\(layout.width) \(layout.height)\n".utf8)
        data.append(contentsOf: bytes)
        return data
    }

    /// Expands only meaningful bitmap bits. Tail padding is never displayed.
    public func grayscalePreview() -> GrayscalePreview {
        var pixels = [UInt8](repeating: 255, count: layout.width * layout.height)
        for y in 0..<layout.height {
            for x in 0..<layout.width {
                let source = bytes[y * layout.bytesPerRow + x / 8]
                pixels[y * layout.width + x] = source & UInt8(0x80 >> (x % 8)) == 0 ? 255 : 0
            }
        }
        return GrayscalePreview(
            width: layout.width,
            height: layout.height,
            bytesPerRow: layout.width,
            pixels: pixels
        )
    }
}
