/// Delivery states are deliberately stronger than a transport exit code.
/// `transmitted` means the local transport accepted all bytes, not that a
/// physical label printed; only a supported receipt may produce confirmation.
public enum DeliveryState: Equatable, Sendable {
    case accepted
    case prepared
    case waiting
    case transmitting(bytesAccepted: Int)
    case transmitted(bytesAccepted: Int)
    case deviceConfirmed
    case uncertain(bytesAccepted: Int)
    case failedBeforeTransmission
    case cancelledBeforeTransmission
}

public enum DeliveryStateError: Error, Equatable, Sendable {
    case invalidTransition
    case invalidByteCount
    case retryRequiresExplicitReview
}

public struct DeliveryReceipt: Equatable, Sendable {
    public let state: DeliveryState
    public let expectedBytes: Int
    public let profileRevision: Int

    public var mayRetryAutomatically: Bool {
        if case .failedBeforeTransmission = state { return true }
        return false
    }
}

public struct DeliveryTracker: Sendable {
    private(set) public var receipt: DeliveryReceipt

    public init(expectedBytes: Int, profileRevision: Int) throws {
        guard expectedBytes > 0, profileRevision > 0 else { throw DeliveryStateError.invalidByteCount }
        receipt = DeliveryReceipt(state: .accepted, expectedBytes: expectedBytes, profileRevision: profileRevision)
    }

    public mutating func prepared() throws { try transition(from: .accepted, to: .prepared) }
    public mutating func waiting() throws { try transition(from: .prepared, to: .waiting) }

    public mutating func acceptedByTransport(byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= receipt.expectedBytes else { throw DeliveryStateError.invalidByteCount }
        switch receipt.state {
        case .waiting, .transmitting:
            receipt = DeliveryReceipt(state: .transmitting(bytesAccepted: byteCount), expectedBytes: receipt.expectedBytes, profileRevision: receipt.profileRevision)
        default: throw DeliveryStateError.invalidTransition
        }
    }

    public mutating func transportFinished() throws {
        guard case let .transmitting(bytes) = receipt.state, bytes == receipt.expectedBytes else {
            throw DeliveryStateError.invalidTransition
        }
        receipt = DeliveryReceipt(state: .transmitted(bytesAccepted: bytes), expectedBytes: receipt.expectedBytes, profileRevision: receipt.profileRevision)
    }

    public mutating func deviceConfirmed() throws {
        guard case .transmitted = receipt.state else { throw DeliveryStateError.invalidTransition }
        receipt = DeliveryReceipt(state: .deviceConfirmed, expectedBytes: receipt.expectedBytes, profileRevision: receipt.profileRevision)
    }

    /// A disconnect, crash, or cancellation after any accepted byte is not
    /// automatically replayable; the device may still print it.
    public mutating func transportBecameAmbiguous() throws {
        let bytes: Int
        switch receipt.state {
        case let .transmitting(count), let .transmitted(count): bytes = count
        default: throw DeliveryStateError.invalidTransition
        }
        receipt = DeliveryReceipt(state: .uncertain(bytesAccepted: bytes), expectedBytes: receipt.expectedBytes, profileRevision: receipt.profileRevision)
    }

    public mutating func failedOrCancelledBeforeTransmission(cancelled: Bool) throws {
        guard case .waiting = receipt.state else { throw DeliveryStateError.invalidTransition }
        receipt = DeliveryReceipt(state: cancelled ? .cancelledBeforeTransmission : .failedBeforeTransmission,
                                  expectedBytes: receipt.expectedBytes, profileRevision: receipt.profileRevision)
    }

    public func requireExplicitRetryReview() throws {
        guard receipt.mayRetryAutomatically else { throw DeliveryStateError.retryRequiresExplicitReview }
    }

    private mutating func transition(from: DeliveryState, to: DeliveryState) throws {
        guard receipt.state == from else { throw DeliveryStateError.invalidTransition }
        receipt = DeliveryReceipt(state: to, expectedBytes: receipt.expectedBytes, profileRevision: receipt.profileRevision)
    }
}
