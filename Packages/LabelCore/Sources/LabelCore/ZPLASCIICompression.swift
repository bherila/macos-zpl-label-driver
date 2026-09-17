import Foundation

/// Lossless ASCII hexadecimal repeat counts (R43), not ^GFC binary compression.
/// Firmware support is not inferred from model name or successful offline tests.
public enum ZPLASCIICompression {
    public enum Error: Swift.Error, Equatable { case supportNotEstablished }

    /// Encodes one complete row. Counts never cross a row or graphic-field boundary.
    /// Literal fallback ensures the result never exceeds the plain hex row size.
    public static func row(_ bytes: ArraySlice<UInt8>) -> Data {
        let hex = Array("0123456789ABCDEF".utf8)
        var result = Data()
        var current: UInt8?
        var count = 0
        func flush() {
            guard let value = current else { return }
            var tokens = Data()
            var remaining = count
            while remaining >= 400 { tokens.append(122); remaining -= 400 }
            if remaining >= 20 { tokens.append(UInt8(103 + remaining / 20 - 1)); remaining %= 20 }
            if remaining > 0 { tokens.append(UInt8(71 + remaining - 1)) }
            tokens.append(value)
            if tokens.count < count { result.append(tokens) }
            else { result.append(contentsOf: repeatElement(value, count: count)) }
        }
        for byte in bytes {
            for value in [hex[Int(byte >> 4)], hex[Int(byte & 15)]] {
                if value == current { count += 1 }
                else { flush(); current = value; count = 1 }
            }
        }
        flush()
        return result
    }
}

extension ZPLGraphicEncoder {
    /// Explicit experimental path. Ordinary prepared jobs continue to use plain hex.
    /// Offline callers may assert supported for testing; production must first bind
    /// actual firmware qualification to an immutable profile.
    public func writeCompressedGraphicFields(
        _ bitmap: MonochromeBitmap, support: CapabilityState,
        sink: (Data) throws -> Void
    ) throws {
        guard support == .supported else { throw ZPLASCIICompression.Error.supportNotEstablished }
        let plan = try bands(for: bitmap.layout)
        let stride = bitmap.layout.bytesPerRow
        func header(_ band: GraphicBand) -> Data {
            Data("^FO0,\(band.y)^GFA,\(band.byteCount),\(band.byteCount),\(stride),".utf8)
        }
        func payload(_ band: GraphicBand, emit: (Data) throws -> Void) rethrows {
            var previous: ArraySlice<UInt8>?
            for y in band.y..<(band.y + band.rowCount) {
                let row = bitmap.bytes[(y * stride)..<((y + 1) * stride)]
                if let previous, row.elementsEqual(previous) { try emit(Data([58])) }
                else { try emit(ZPLASCIICompression.row(row)) }
                previous = row
            }
        }
        // Count exact encoded output before any callback, using one row of scratch.
        var total = 0
        func reserve(_ count: Int) throws {
            let (next, overflow) = total.addingReportingOverflow(count)
            guard !overflow, next <= maxOutputBytes else { throw EncodingError.outputLimit }
            total = next
        }
        for band in plan {
            try reserve(header(band).count + 4)
            try payload(band) { try reserve($0.count) }
        }
        for band in plan {
            try sink(header(band))
            try payload(band, emit: sink)
            try sink(Data("^FS\n".utf8))
        }
    }

    public func compressedDiagnosticFormat(_ bitmap: MonochromeBitmap) throws -> Data {
        guard maxOutputBytes > 8 else { throw EncodingError.outputLimit }
        let fields = try Self(maxDecodedBandBytes: maxDecodedBandBytes,
                              maxOutputBytes: maxOutputBytes - 8,
                              maxDimensionDots: maxDimensionDots)
        var output = Data("^XA\n".utf8)
        try fields.writeCompressedGraphicFields(bitmap, support: .supported) { output.append($0) }
        output.append(Data("^XZ\n".utf8))
        return output
    }
}
