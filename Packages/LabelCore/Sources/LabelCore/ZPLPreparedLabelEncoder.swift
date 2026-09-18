import Foundation

/// Prepared bytes and the immutable profile facts used to create them. This is
/// the handoff boundary between rendering/encoding and delivery; it contains no
/// transport receipt and is not a claim that a printer accepted the bytes.
public struct PreparedLabel: Equatable, Sendable {
    public let bytes: Data
    public let profileSnapshot: JobProfileSnapshot

    public init(bytes: Data, profileSnapshot: JobProfileSnapshot) {
        self.bytes = bytes
        self.profileSnapshot = profileSnapshot
    }
}

/// A complete, bounded label format assembled from typed controls and the
/// canonical graphic writer. It is prepared output, not transport delivery.
public struct ZPLPreparedLabelEncoder: Sendable {
    public enum EncodingError: Error, Equatable, Sendable { case outputLimit }
    public let maxOutputBytes: Int
    public let controls: ZPLControlEncoder
    public let graphics: ZPLGraphicEncoder

    public init(maxOutputBytes: Int = 64 * 1024 * 1024,
                controls: ZPLControlEncoder? = nil,
                graphics: ZPLGraphicEncoder? = nil) throws {
        guard maxOutputBytes >= 8 else { throw EncodingError.outputLimit }
        self.maxOutputBytes = maxOutputBytes
        self.controls = try controls ?? ZPLControlEncoder()
        self.graphics = try graphics ?? ZPLGraphicEncoder()
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

    /// Resolves controls and captures the complete profile before producing
    /// bytes. Consumers that deliver this result can retain the same snapshot
    /// rather than pairing arbitrary bytes with a later profile revision.
    public func prepare(
        bitmap: MonochromeBitmap,
        profile: PrinterProfile,
        job: PrinterControlRequest = .init(),
        workflowDefaults: PrinterControlDefaults = .init()
    ) throws -> PreparedLabel {
        let resolved = try profile.resolveControls(job: job, workflowDefaults: workflowDefaults)
        return try PreparedLabel(
            bytes: encode(bitmap: bitmap, controls: resolved),
            profileSnapshot: JobProfileSnapshot(profile: profile)
        )
    }
}
