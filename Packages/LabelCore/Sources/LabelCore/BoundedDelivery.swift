import Foundation

/// A transport adapter reports only how many bytes it accepted. It never
/// reports printing completion. Implementations must not shell out or interpret
/// document/profile strings. If `write` throws, it guarantees that it accepted
/// zero bytes from that call; adapters with ambiguous send errors must use the
/// separate uncertain-attempt state instead of conforming to this protocol.
public protocol DeliveryByteSink {
    mutating func write(_ bytes: Data) throws -> Int
}

public enum BoundedDeliveryError: Error, Equatable, Sendable {
    case zeroByteWrite
    case invalidWriteCount
    case transportFailureAfterBytesAccepted
    case transportFailureBeforeBytesAccepted
}

public enum BoundedDelivery {
    /// Project copy-buffer budget, not a printer or network packet limit.
    public static let maximumWriteBytes = 64 * 1024

    /// Drives short writes to completion. Any error after at least one accepted
    /// byte transitions the supplied tracker to uncertain before returning.
    public static func write<S: DeliveryByteSink>(
        _ payload: Data, to sink: inout S, tracker: inout DeliveryTracker
    ) throws {
        guard payload.count == tracker.receipt.expectedBytes else { throw BoundedDeliveryError.invalidWriteCount }
        try tracker.validateTransportStart(payload: payload)
        var offset = 0
        var invalidAccounting = false
        do {
            while offset < payload.count {
                let offeredCount = min(maximumWriteBytes, payload.count - offset)
                let count = try sink.write(payload.subdata(in: offset..<(offset + offeredCount)))
                guard count >= 0, count <= offeredCount else {
                    invalidAccounting = true
                    throw BoundedDeliveryError.invalidWriteCount
                }
                guard count > 0 else { throw BoundedDeliveryError.zeroByteWrite }
                offset += count
                try tracker.acceptedByTransport(byteCount: offset)
            }
            try tracker.transportFinished()
        } catch {
            if invalidAccounting {
                // A broken byte-count contract gives no evidence of what was
                // actually delivered, even when no prior bytes were reported.
                if offset > 0 { try? tracker.transportBecameAmbiguous() }
                else { try? tracker.transportAttemptBecameAmbiguous() }
                throw BoundedDeliveryError.invalidWriteCount
            }
            if offset > 0 {
                try? tracker.transportBecameAmbiguous()
                throw BoundedDeliveryError.transportFailureAfterBytesAccepted
            }
            try? tracker.failedOrCancelledBeforeTransmission(cancelled: false)
            throw BoundedDeliveryError.transportFailureBeforeBytesAccepted
        }
    }
}
