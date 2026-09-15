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
    /// Drives short writes to completion. Any error after at least one accepted
    /// byte transitions the supplied tracker to uncertain before returning.
    public static func write<S: DeliveryByteSink>(
        _ payload: Data, to sink: inout S, tracker: inout DeliveryTracker
    ) throws {
        guard payload.count == tracker.receipt.expectedBytes else { throw BoundedDeliveryError.invalidWriteCount }
        try tracker.validateTransportStart(payload: payload)
        var offset = 0
        do {
            while offset < payload.count {
                let count = try sink.write(payload.subdata(in: offset..<payload.count))
                guard count > 0 else { throw BoundedDeliveryError.zeroByteWrite }
                guard count <= payload.count - offset else { throw BoundedDeliveryError.invalidWriteCount }
                offset += count
                try tracker.acceptedByTransport(byteCount: offset)
            }
            try tracker.transportFinished()
        } catch {
            if offset > 0 {
                try? tracker.transportBecameAmbiguous()
                throw BoundedDeliveryError.transportFailureAfterBytesAccepted
            }
            try? tracker.failedOrCancelledBeforeTransmission(cancelled: false)
            throw BoundedDeliveryError.transportFailureBeforeBytesAccepted
        }
    }
}
