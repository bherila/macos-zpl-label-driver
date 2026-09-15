/// Checked packed-bitmap dimensions. This is not a printer capability validator
/// and does not allocate image memory or encode printer commands.
public struct BitmapLayout: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidDimensions
        case invalidLimit
        case sizeOverflow
        case exceedsLimit(actual: Int, limit: Int)
    }

    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let byteCount: Int

    /// Computes a tightly packed one-bit row layout without overflowing width + 7.
    public init(width: Int, height: Int, maxByteCount: Int = 512 * 1024 * 1024) throws {
        guard width > 0, height > 0 else {
            throw ValidationError.invalidDimensions
        }
        guard maxByteCount > 0 else {
            throw ValidationError.invalidLimit
        }
        let stride = width / 8 + (width % 8 == 0 ? 0 : 1)
        let (count, overflow) = stride.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw ValidationError.sizeOverflow
        }
        guard count <= maxByteCount else {
            throw ValidationError.exceedsLimit(actual: count, limit: maxByteCount)
        }
        self.width = width
        self.height = height
        self.bytesPerRow = stride
        self.byteCount = count
    }
}
