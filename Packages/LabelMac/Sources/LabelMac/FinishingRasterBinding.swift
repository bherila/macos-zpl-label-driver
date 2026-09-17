import CryptoKit
import Foundation
import LabelCore

public struct FinishingRasterIdentity: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let byteCount: Int
    public let sha256: String
}

/// Digests the actual packed encoder inputs without rerendering or retaining
/// another payload copy. A later sender must capture and validate its own inputs.
/// This is not proof of original-PDF provenance or authority for transmission.
public struct FinishingRasterBinding: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimit
        case countMismatch
        case rasterLimit
        case byteLimit
        case cancelled
        case bindingMismatch
    }
    public static let maximumTotalBytes = 512 * 1024 * 1024
    public let job: ProfileBoundFinishingJobPlan
    public let labels: [FinishingRasterIdentity]
    public let totalPackedBytes: Int
    public let orderedRasterSHA256: String

    public init(job: ProfileBoundFinishingJobPlan, orderedRasters: [MonochromeBitmap],
                maximumTotalBytes: Int = Self.maximumTotalBytes,
                cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        guard (1...Self.maximumTotalBytes).contains(maximumTotalBytes) else { throw Error.invalidLimit }
        guard orderedRasters.count == job.plan.outputLabelCount else { throw Error.countMismatch }
        var identities: [FinishingRasterIdentity] = [], total = 0
        var ordered = SHA256()
        ordered.update(data: Data("label-finishing-raster-order-v1\0".utf8))
        Self.updateScalar(orderedRasters.count, hash: &ordered)
        for (index, bitmap) in orderedRasters.enumerated() {
            guard !cancellation.isCancelled else { throw Error.cancelled }
            let layout = bitmap.layout
            let (pixels, pixelOverflow) = layout.width.multipliedReportingOverflow(by: layout.height)
            guard layout.width <= 8192, layout.height <= 65535, !pixelOverflow,
                  pixels <= 32 * 1024 * 1024 else { throw Error.rasterLimit }
            let (next, byteOverflow) = total.addingReportingOverflow(bitmap.bytes.count)
            guard !byteOverflow, next <= maximumTotalBytes else { throw Error.byteLimit }
            total = next
            var leaf = SHA256()
            leaf.update(data: Data("label-packed-raster-v1\0".utf8))
            for scalar in [layout.width, layout.height, layout.bytesPerRow, bitmap.bytes.count] {
                Self.updateScalar(scalar, hash: &leaf)
            }
            leaf.update(data: Data(bitmap.bytes))
            let digest = leaf.finalize()
            identities.append(.init(width: layout.width, height: layout.height,
                bytesPerRow: layout.bytesPerRow, byteCount: bitmap.bytes.count, sha256: Self.hex(digest)))
            Self.updateScalar(index, hash: &ordered)
            ordered.update(data: Data(digest))
        }
        guard !cancellation.isCancelled else { throw Error.cancelled }
        self.job = job; self.labels = identities; self.totalPackedBytes = total
        self.orderedRasterSHA256 = Self.hex(ordered.finalize())
    }

    public func validate(job: ProfileBoundFinishingJobPlan, orderedRasters: [MonochromeBitmap],
                         cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        guard self.job == job else { throw Error.bindingMismatch }
        let actual = try Self(job: job, orderedRasters: orderedRasters,
            maximumTotalBytes: totalPackedBytes, cancellation: cancellation)
        guard actual.labels == labels, actual.totalPackedBytes == totalPackedBytes,
              actual.orderedRasterSHA256 == orderedRasterSHA256 else { throw Error.bindingMismatch }
    }

    private static func updateScalar(_ scalar: Int, hash: inout SHA256) {
        var value = UInt64(scalar).littleEndian
        withUnsafeBytes(of: &value) { hash.update(data: Data($0)) }
    }
    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
