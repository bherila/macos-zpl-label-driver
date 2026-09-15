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
        let layout = try BitmapLayout(width: width, height: height, maxByteCount: maxByteCount)
        guard stride >= width else { throw ValidationError.invalidGrayscaleStride }
        let (required, overflow) = stride.multipliedReportingOverflow(by: height)
        guard !overflow, required == grayscale.count else { throw ValidationError.invalidGrayscaleLength }
        var packed = [UInt8](repeating: 0, count: layout.byteCount)
        for y in 0..<height {
            for x in 0..<width where grayscale[y * stride + x] < threshold {
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
}
