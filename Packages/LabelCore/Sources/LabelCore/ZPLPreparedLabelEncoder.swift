import Foundation

/// A complete, bounded label format assembled from typed controls and the
/// canonical graphic writer. It is prepared output, not transport delivery.
public struct ZPLPreparedLabelEncoder: Sendable {
    public enum EncodingError: Error, Equatable, Sendable { case outputLimit }
    public let maxOutputBytes: Int
    public let controls: ZPLControlEncoder
    public let graphics: ZPLGraphicEncoder

    public init(maxOutputBytes: Int = 64 * 1024 * 1024,
                controls: ZPLControlEncoder = try! ZPLControlEncoder(),
                graphics: ZPLGraphicEncoder = try! ZPLGraphicEncoder()) throws {
        guard maxOutputBytes >= 8 else { throw EncodingError.outputLimit }
        self.maxOutputBytes = maxOutputBytes
        self.controls = controls
        self.graphics = graphics
    }

    public func encode(bitmap: MonochromeBitmap, controls resolved: ResolvedPrinterControls) throws -> Data {
        let controlBytes = try controls.encode(resolved)
        let wrapperBytes = 8
        guard controlBytes.count <= maxOutputBytes - wrapperBytes else { throw EncodingError.outputLimit }
        let graphics = try ZPLGraphicEncoder(maxDecodedBandBytes: graphics.maxDecodedBandBytes,
                                             maxOutputBytes: maxOutputBytes - wrapperBytes - controlBytes.count,
                                             maxDimensionDots: graphics.maxDimensionDots)
        var result = Data("^XA\n".utf8)
        result.append(controlBytes)
        try graphics.writeGraphicFields(bitmap) { result.append($0) }
        result.append(Data("^XZ\n".utf8))
        return result
    }
}
