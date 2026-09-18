import Foundation

/// Prepared bytes and the immutable profile facts used to create them. This is
/// the handoff boundary between rendering/encoding and delivery; it contains no
/// transport receipt and is not a claim that a printer accepted the bytes.
public struct PreparedLabel: Equatable, Sendable {
    public let bytes: Data
    public let profileSnapshot: JobProfileSnapshot
    public let resolvedControls: ResolvedPrinterControls

    init(
        bytes: Data,
        profileSnapshot: JobProfileSnapshot,
        resolvedControls: ResolvedPrinterControls
    ) {
        self.bytes = bytes
        self.profileSnapshot = profileSnapshot
        self.resolvedControls = resolvedControls
    }
}

/// A typed encoder result paired with the exact resolved output identity that
/// produced it. The job payload constructor checks the complete ordered list,
/// not only its count.
public struct PreparedOutputLabel: Equatable, Sendable {
    public let output: ResolvedOutputLabel
    public let prepared: PreparedLabel

    public init(output: ResolvedOutputLabel, prepared: PreparedLabel) {
        self.output = output
        self.prepared = prepared
    }
}

/// Complete ordered printer-language bytes for one accepted job. Construction
/// requires exactly one typed encoder result per resolved output identity in
/// that exact order, keeps every label on the same immutable profile snapshot
/// and resolved controls, and preflights the total byte budget before
/// concatenation.
public struct PreparedJobPayload: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLabelCount
        case emptyLabel
        case outputOrderMismatch
        case profileMismatch
        case controlsMismatch
        case outputLimit
    }

    public static let maximumLabels = 10_000
    public static let maximumBytes = 64 * 1024 * 1024

    public let bytes: Data
    public let labelCount: Int
    public let outputLabels: [ResolvedOutputLabel]
    public let monochromeConversion: MonochromeConversion
    public let profileSnapshot: JobProfileSnapshot
    public let resolvedControls: ResolvedPrinterControls

    public init(
        labels: [PreparedOutputLabel],
        expectedOutputLabels: [ResolvedOutputLabel],
        monochromeConversion: MonochromeConversion,
        maximumBytes: Int = maximumBytes
    ) throws {
        guard (1...Self.maximumLabels).contains(expectedOutputLabels.count),
              labels.count == expectedOutputLabels.count else {
            throw Error.invalidLabelCount
        }
        guard labels.map(\.output) == expectedOutputLabels else {
            throw Error.outputOrderMismatch
        }
        guard (1...Self.maximumBytes).contains(maximumBytes),
              let first = labels.first?.prepared else {
            throw Error.outputLimit
        }
        var total = 0
        for item in labels {
            let label = item.prepared
            guard !label.bytes.isEmpty else { throw Error.emptyLabel }
            guard label.profileSnapshot == first.profileSnapshot else {
                throw Error.profileMismatch
            }
            guard label.resolvedControls == first.resolvedControls else {
                throw Error.controlsMismatch
            }
            let (next, overflow) = total.addingReportingOverflow(label.bytes.count)
            guard !overflow, next <= maximumBytes else { throw Error.outputLimit }
            total = next
        }
        var bytes = Data()
        bytes.reserveCapacity(total)
        for label in labels { bytes.append(label.prepared.bytes) }
        self.bytes = bytes
        labelCount = labels.count
        outputLabels = expectedOutputLabels
        self.monochromeConversion = monochromeConversion
        profileSnapshot = first.profileSnapshot
        resolvedControls = first.resolvedControls
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
            profileSnapshot: JobProfileSnapshot(profile: profile),
            resolvedControls: resolved
        )
    }
}
