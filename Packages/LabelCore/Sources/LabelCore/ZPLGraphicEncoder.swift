import Foundation

public struct GraphicBand: Equatable, Sendable {
    public let y: Int
    public let rowCount: Int
    public let byteOffset: Int
    public let byteCount: Int
}

/// Uncompressed ASCII-hex ^GF writer. Does not own media, copies, darkness,
/// orientation, state normalization, device delivery or physical completion.
public struct ZPLGraphicEncoder: Sendable {
    public enum EncodingError: Error, Equatable, Sendable {
        case invalidLimits
        case rowExceedsBandLimit
        case coordinateLimit
        case outputLimit
    }
    public let maxDecodedBandBytes: Int
    public let maxOutputBytes: Int
    public let maxDimensionDots: Int

    /// 32 KiB is a project default, NOT a certified GC420d memory budget.
    public init(maxDecodedBandBytes: Int = 32_768, maxOutputBytes: Int = 64 * 1024 * 1024,
                maxDimensionDots: Int = 32_000) throws {
        guard (1...99_999).contains(maxDecodedBandBytes), maxOutputBytes > 0,
              (1...32_000).contains(maxDimensionDots) else { throw EncodingError.invalidLimits }
        self.maxDecodedBandBytes = maxDecodedBandBytes
        self.maxOutputBytes = maxOutputBytes
        self.maxDimensionDots = maxDimensionDots
    }

    public func bands(for layout: BitmapLayout) throws -> [GraphicBand] {
        guard layout.width <= maxDimensionDots, layout.height <= maxDimensionDots else {
            throw EncodingError.coordinateLimit
        }
        guard layout.bytesPerRow <= maxDecodedBandBytes else { throw EncodingError.rowExceedsBandLimit }
        let rowsPerBand = maxDecodedBandBytes / layout.bytesPerRow
        var bands: [GraphicBand] = []
        var y = 0
        while y < layout.height {
            let rows = min(rowsPerBand, layout.height - y)
            bands.append(GraphicBand(y: y, rowCount: rows, byteOffset: y * layout.bytesPerRow,
                                     byteCount: rows * layout.bytesPerRow))
            y += rows
        }
        return bands
    }

    private func header(_ band: GraphicBand, stride: Int) -> Data {
        Data("^FO0,\(band.y)^GFA,\(band.byteCount),\(band.byteCount),\(stride),".utf8)
    }

    /// Preflights the complete budget before the FIRST sink callback.
    /// Sink failure is propagated immediately. Callers must stage/discard partial
    /// output; this method does not provide exactly-once device delivery.
    /// Cancellation can be expressed by throwing from the sink between chunks.
    public func writeGraphicFields(_ bitmap: MonochromeBitmap,
                                   sink: (Data) throws -> Void) throws {
        let plan = try bands(for: bitmap.layout)
        var total = 0
        for band in plan {
            let (twice, mulOverflow) = band.byteCount.multipliedReportingOverflow(by: 2)
            let extra = header(band, stride: bitmap.layout.bytesPerRow).count + 4 // ^FS\n
            let (size, addOverflow) = twice.addingReportingOverflow(extra)
            let (next, totalOverflow) = total.addingReportingOverflow(size)
            guard !mulOverflow, !addOverflow, !totalOverflow, next <= maxOutputBytes else {
                throw EncodingError.outputLimit
            }
            total = next
        }
        let hex = Array("0123456789ABCDEF".utf8)
        for band in plan {
            try sink(header(band, stride: bitmap.layout.bytesPerRow))
            var start = band.byteOffset
            let end = start + band.byteCount
            while start < end {
                let stop = min(start + 4096, end)
                var chunk = Data(capacity: (stop - start) * 2)
                for value in bitmap.bytes[start..<stop] {
                    chunk.append(hex[Int(value >> 4)])
                    chunk.append(hex[Int(value & 15)])
                }
                try sink(chunk)
                start = stop
            }
            try sink(Data("^FS\n".utf8))
        }
    }

    /// Offline test envelope only: one ^XA/^XZ, no ^PQ or device settings.
    /// It intentionally does not normalize inherited printer state. Production
    /// code must combine fields with the M3 validated state/job-ticket layer.
    public func diagnosticFormat(_ bitmap: MonochromeBitmap) throws -> Data {
        guard maxOutputBytes > 8 else { throw EncodingError.outputLimit }
        let fields = try Self(maxDecodedBandBytes: maxDecodedBandBytes,
                              maxOutputBytes: maxOutputBytes - 8,
                              maxDimensionDots: maxDimensionDots)
        var output = Data("^XA\n".utf8)
        try fields.writeGraphicFields(bitmap) { output.append($0) }
        output.append(Data("^XZ\n".utf8))
        return output
    }
}
