import Foundation

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
    case payloadBindingMismatch
    case retryRequiresExplicitReview
}

/// The immutable profile facts bound at job acceptance. This value is copied
/// into a receipt; later profile/default edits therefore cannot rewrite a
/// queued job's declared media or revision.
public struct JobProfileSnapshot: Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public let media: MediaConfiguration
    public let thermalMedia: ThermalMediaConfiguration

    public init(profile: PrinterProfile) {
        schemaVersion = profile.schemaVersion
        revision = profile.revision
        media = profile.media
        thermalMedia = profile.thermalMedia
    }
}

public struct DeliveryReceipt: Equatable, Sendable {
    public let state: DeliveryState
    public let expectedBytes: Int
    public let profileRevision: Int
    /// Present only when the caller supplied the complete typed profile rather
    /// than a legacy revision token. A transport receipt cannot manufacture it.
    public let profileSnapshot: JobProfileSnapshot?

    public var mayRetryAutomatically: Bool {
        if case .failedBeforeTransmission = state { return true }
        return false
    }
}

public struct DeliveryTracker: Sendable {
    private(set) public var receipt: DeliveryReceipt
    private let boundPayload: Data?

    public init(expectedBytes: Int, profileRevision: Int) throws {
        guard expectedBytes > 0, profileRevision > 0 else { throw DeliveryStateError.invalidByteCount }
        receipt = DeliveryReceipt(
            state: .accepted,
            expectedBytes: expectedBytes,
            profileRevision: profileRevision,
            profileSnapshot: nil
        )
        boundPayload = nil
    }

    public init(expectedBytes: Int, profile: PrinterProfile) throws {
        try self.init(expectedBytes: expectedBytes, profileSnapshot: JobProfileSnapshot(profile: profile))
    }

    public init(expectedBytes: Int, profileSnapshot: JobProfileSnapshot) throws {
        guard expectedBytes > 0 else { throw DeliveryStateError.invalidByteCount }
        receipt = DeliveryReceipt(
            state: .accepted,
            expectedBytes: expectedBytes,
            profileRevision: profileSnapshot.revision,
            profileSnapshot: profileSnapshot
        )
        boundPayload = nil
    }

    public init(preparedLabel: PreparedLabel) throws {
        try self.init(boundPayload: preparedLabel.bytes, profileSnapshot: preparedLabel.profileSnapshot)
    }

    /// Bind the complete ordered job rather than pairing concatenated bytes
    /// with a revision token or the snapshot of an arbitrary individual label.
    public init(preparedJob: PreparedJobPayload) throws {
        try self.init(boundPayload: preparedJob.bytes, profileSnapshot: preparedJob.profileSnapshot)
    }

    private init(boundPayload: Data, profileSnapshot: JobProfileSnapshot) throws {
        guard !boundPayload.isEmpty else { throw DeliveryStateError.invalidByteCount }
        receipt = DeliveryReceipt(
            state: .accepted,
            expectedBytes: boundPayload.count,
            profileRevision: profileSnapshot.revision,
            profileSnapshot: profileSnapshot
        )
        self.boundPayload = boundPayload
    }

    public mutating func prepared() throws { try transition(from: .accepted, to: .prepared) }
    public mutating func waiting() throws { try transition(from: .prepared, to: .waiting) }

    /// Authorizes a new full-payload delivery before any external write. This
    /// tracker does not support implicit restart or resume from a later state.
    public func validateTransportStart(payload: Data) throws {
        guard payload.count == receipt.expectedBytes else { throw DeliveryStateError.invalidByteCount }
        guard case .waiting = receipt.state else { throw DeliveryStateError.invalidTransition }
        if let boundPayload, boundPayload != payload { throw DeliveryStateError.payloadBindingMismatch }
    }

    public mutating func acceptedByTransport(byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= receipt.expectedBytes else { throw DeliveryStateError.invalidByteCount }
        switch receipt.state {
        case .waiting:
            receipt = receipt.replacingState(.transmitting(bytesAccepted: byteCount))
        case let .transmitting(previous) where byteCount >= previous:
            receipt = receipt.replacingState(.transmitting(bytesAccepted: byteCount))
        default: throw DeliveryStateError.invalidTransition
        }
    }

    public mutating func transportFinished() throws {
        guard case let .transmitting(bytes) = receipt.state, bytes == receipt.expectedBytes else {
            throw DeliveryStateError.invalidTransition
        }
        receipt = receipt.replacingState(.transmitted(bytesAccepted: bytes))
    }

    public mutating func deviceConfirmed() throws {
        guard case .transmitted = receipt.state else { throw DeliveryStateError.invalidTransition }
        receipt = receipt.replacingState(.deviceConfirmed)
    }

    /// A disconnect, crash, or cancellation after any accepted byte is not
    /// automatically replayable; the device may still print it.
    public mutating func transportBecameAmbiguous() throws {
        let bytes: Int
        switch receipt.state {
        case let .transmitting(count), let .transmitted(count): bytes = count
        default: throw DeliveryStateError.invalidTransition
        }
        receipt = receipt.replacingState(.uncertain(bytesAccepted: bytes))
    }

    /// Use this when a transport API accepted a send attempt but cannot say
    /// whether any bytes reached its peer. Zero is unknown here, not proof
    /// that no bytes were accepted, so automatic retry remains forbidden.
    public mutating func transportAttemptBecameAmbiguous() throws {
        guard case .waiting = receipt.state else { throw DeliveryStateError.invalidTransition }
        receipt = receipt.replacingState(.uncertain(bytesAccepted: 0))
    }

    public mutating func failedOrCancelledBeforeTransmission(cancelled: Bool) throws {
        guard case .waiting = receipt.state else { throw DeliveryStateError.invalidTransition }
        receipt = receipt.replacingState(cancelled ? .cancelledBeforeTransmission : .failedBeforeTransmission)
    }

    public func requireExplicitRetryReview() throws {
        guard receipt.mayRetryAutomatically else { throw DeliveryStateError.retryRequiresExplicitReview }
    }

    private mutating func transition(from: DeliveryState, to: DeliveryState) throws {
        guard receipt.state == from else { throw DeliveryStateError.invalidTransition }
        receipt = receipt.replacingState(to)
    }
}

private extension DeliveryReceipt {
    func replacingState(_ state: DeliveryState) -> DeliveryReceipt {
        DeliveryReceipt(
            state: state,
            expectedBytes: expectedBytes,
            profileRevision: profileRevision,
            profileSnapshot: profileSnapshot
        )
    }
}
