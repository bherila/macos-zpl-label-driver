import CryptoKit
import Foundation

/// Durable bounded delivery lifecycle for one immutable framed artifact. Records
/// are append-only: there is no clear, reset or overwrite API, absence is only
/// absence, and storage grants no device authority or replay authorization.
/// Both record kinds independently revalidate the archived complete context.
public struct FinishingDeliveryOutcomeStore: @unchecked Sendable {
    public enum Observation: Equatable, Sendable {
        /// Absence is not proof that no external sender ever transmitted, and it
        /// is never a reason to send again.
        case noRecordedDelivery
        /// A durable send-attempt record with no terminal record: this includes a
        /// crash between publication and the first offered file.
        case uncertainAfterRecordedIntent
        case recorded(FinishingDeliveryDisposition)

        public var isUncertain: Bool {
            switch self {
            case .noRecordedDelivery: false
            case .uncertainAfterRecordedIntent: true
            case let .recorded(disposition): disposition.isUncertain
            }
        }
        /// Derived only from a recorded proven pre-attempt refusal. A missing
        /// record authorizes nothing.
        public var authorizesBoundedRetry: Bool {
            switch self {
            case .noRecordedDelivery, .uncertainAfterRecordedIntent: false
            case let .recorded(disposition): disposition.authorizesBoundedRetry
            }
        }
    }
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsafeDirectory, cannotRead, cannotWrite, conflict, invalidRecord
        case capacityReached, publicationBusy, commitUncertain, missingIntent
    }
    public static let maximumRecordBytes = 1024
    public static let maximumRecords = 2 * FinishingArtifactStore.maximumRecords
    private static let directory = "finishing-deliveries"
    private let archives: FinishingArtifactStore
    private let storage: PrivateImmutableDirectory
    public init(root: URL) throws {
        archives = try FinishingArtifactStore(root: root)
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Error.unsafeDirectory }
    }
    init(root: URL, storage: PrivateImmutableDirectory) throws {
        archives = try FinishingArtifactStore(root: root); self.storage = storage
    }

    /// Idempotent durable send-attempt state, published before any provider call
    /// that might be effective. It is never fresh-send authorization.
    public func recordAttemptIntent(reference: FinishingArtifactReference,
                                    against output: FinishingFramedOutput,
                                    cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        _ = try archives.load(reference: reference, against: output, cancellation: cancellation)
        guard !cancellation.isCancelled else { throw FinishingFramedArtifact.Error.cancelled }
        try publish(Self.intentRecord(reference), fileName: Self.fileName(reference, kind: "i"))
        guard !cancellation.isCancelled else { throw Error.commitUncertain }
    }

    /// One immutable terminal record. An uncertain disposition requires the
    /// durable intent to exist already, so uncertainty can never be recorded as
    /// though no attempt had been made.
    public func recordOutcome(reference: FinishingArtifactReference, against output: FinishingFramedOutput,
                              disposition: FinishingDeliveryDisposition,
                              cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        _ = try archives.load(reference: reference, against: output, cancellation: cancellation)
        guard !cancellation.isCancelled else { throw FinishingFramedArtifact.Error.cancelled }
        if disposition.isUncertain, try Self.intent(storage: storage, reference: reference) == nil {
            throw Error.missingIntent
        }
        try publish(Self.outcomeRecord(reference, disposition), fileName: Self.fileName(reference, kind: "o"))
        guard !cancellation.isCancelled else { throw Error.commitUncertain }
    }

    /// Cold read. It performs no provider call, no byte callback and no device
    /// query, and it revalidates the independently supplied complete context.
    public func observation(reference: FinishingArtifactReference, against output: FinishingFramedOutput,
                            cancellation: OfflineRenderWorkerCancellation = .init()) throws -> Observation {
        _ = try archives.load(reference: reference, against: output, cancellation: cancellation)
        let recorded = try Self.outcome(storage: storage, reference: reference)
        let intent = try Self.intent(storage: storage, reference: reference)
        guard !cancellation.isCancelled else { throw FinishingFramedArtifact.Error.cancelled }
        if let recorded { return .recorded(recorded) }
        return intent == nil ? .noRecordedDelivery : .uncertainAfterRecordedIntent
    }

    private func publish(_ bytes: Data, fileName: String) throws {
        do {
            try storage.publish(bytes, directory: Self.directory, fileName: fileName,
                maximumBytes: Self.maximumRecordBytes, maximumRecords: Self.maximumRecords,
                recordFormat: .binary)
        } catch { throw Self.map(error) }
    }
    private static func read(storage: PrivateImmutableDirectory, fileName: String) throws -> Data? {
        do {
            return try storage.read(directory: directory, fileName: fileName,
                maximumBytes: maximumRecordBytes, createDirectoryIfMissing: false)
        } catch PrivateImmutableDirectory.Error.notFound { return nil }
        catch { throw map(error) }
    }
    private static func intent(storage: PrivateImmutableDirectory,
                               reference: FinishingArtifactReference) throws -> Data? {
        guard let bytes = try read(storage: storage, fileName: fileName(reference, kind: "i")) else { return nil }
        guard bytes == intentRecord(reference) else { throw Error.invalidRecord }
        return bytes
    }
    private static func outcome(storage: PrivateImmutableDirectory,
                                reference: FinishingArtifactReference) throws -> FinishingDeliveryDisposition? {
        guard let bytes = try read(storage: storage, fileName: fileName(reference, kind: "o")) else { return nil }
        return try parseOutcome(bytes, reference: reference)
    }

    // Validated identifier alphabet and digests cannot inject a delimiter, and
    // the explicit closed token set is not a synthesized Codable wire layout.
    private static func intentRecord(_ reference: FinishingArtifactReference) -> Data {
        Data("LABEL_FINISHING_DELIVERY_INTENT_V1\n\(reference.id)\n\(reference.revision)\n\(reference.sha256)\n".utf8)
    }
    private static func outcomeRecord(_ reference: FinishingArtifactReference,
                                      _ disposition: FinishingDeliveryDisposition) -> Data {
        Data("LABEL_FINISHING_DELIVERY_OUTCOME_V1\n\(reference.id)\n\(reference.revision)\n\(reference.sha256)\n\(token(disposition))\n".utf8)
    }
    static func token(_ disposition: FinishingDeliveryDisposition) -> String {
        switch disposition {
        case .allStepsSatisfied: "allStepsSatisfied"
        case .failedBeforeAttempt: "failedBeforeAttempt"
        case .cancelledBeforeAttempt: "cancelledBeforeAttempt"
        case .timedOutBeforeAttempt: "timedOutBeforeAttempt"
        case let .cancelledAfterAttempt(step): "cancelledAfterAttempt,\(step)"
        case let .timedOutAfterAttempt(step): "timedOutAfterAttempt,\(step)"
        case let .partialTransmission(step, accepted, expected): "partialTransmission,\(step),\(accepted),\(expected)"
        case let .ambiguousPublication(step): "ambiguousPublication,\(step)"
        case let .statusUnknown(step): "statusUnknown,\(step)"
        case let .statusNotSatisfied(step): "statusNotSatisfied,\(step)"
        case let .ownershipLost(step): "ownershipLost,\(step)"
        case let .providerFailedAfterAttempt(step): "providerFailedAfterAttempt,\(step)"
        }
    }
    private static func parseOutcome(_ bytes: Data,
                                     reference: FinishingArtifactReference) throws -> FinishingDeliveryDisposition {
        guard bytes.count <= maximumRecordBytes, let text = String(data: bytes, encoding: .utf8) else {
            throw Error.invalidRecord
        }
        let lines = text.components(separatedBy: "\n")
        guard lines.count == 6, lines[0] == "LABEL_FINISHING_DELIVERY_OUTCOME_V1", lines[1] == reference.id,
              lines[2] == String(reference.revision), lines[3] == reference.sha256, lines[5].isEmpty else {
            throw Error.invalidRecord
        }
        let disposition = try parseToken(lines[4])
        // Exact canonical re-encoding prevents an alternate spelling of a state.
        guard outcomeRecord(reference, disposition) == bytes else { throw Error.invalidRecord }
        return disposition
    }
    private static func parseToken(_ token: String) throws -> FinishingDeliveryDisposition {
        let parts = token.components(separatedBy: ",")
        func step() throws -> Int {
            guard parts.count == 2, let value = Int(parts[1]), value >= 0 else { throw Error.invalidRecord }
            return value
        }
        func plain() throws {
            guard parts.count == 1 else { throw Error.invalidRecord }
        }
        switch parts[0] {
        case "allStepsSatisfied": try plain(); return .allStepsSatisfied
        case "failedBeforeAttempt": try plain(); return .failedBeforeAttempt
        case "cancelledBeforeAttempt": try plain(); return .cancelledBeforeAttempt
        case "timedOutBeforeAttempt": try plain(); return .timedOutBeforeAttempt
        case "cancelledAfterAttempt": return try .cancelledAfterAttempt(step: step())
        case "timedOutAfterAttempt": return try .timedOutAfterAttempt(step: step())
        case "ambiguousPublication": return try .ambiguousPublication(step: step())
        case "statusUnknown": return try .statusUnknown(step: step())
        case "statusNotSatisfied": return try .statusNotSatisfied(step: step())
        case "ownershipLost": return try .ownershipLost(step: step())
        case "providerFailedAfterAttempt": return try .providerFailedAfterAttempt(step: step())
        case "partialTransmission":
            guard parts.count == 4, let index = Int(parts[1]), let accepted = Int(parts[2]),
                  let expected = Int(parts[3]), index >= 0, accepted >= 0, expected > accepted else {
                throw Error.invalidRecord
            }
            return .partialTransmission(step: index, accepted: accepted, expected: expected)
        default: throw Error.invalidRecord
        }
    }
    private static func fileName(_ reference: FinishingArtifactReference, kind: String) -> String {
        let id = SHA256.hash(data: Data(reference.id.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(id)-r\(reference.revision)-\(kind).bin"
    }
    private static func map(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .cannotCreate, .cannotOpen, .unsafeDirectory: .unsafeDirectory
        case .recordCapacityReached: .capacityReached
        case .publicationBusy: .publicationBusy
        case .conflict: .conflict
        case .commitUncertain: .commitUncertain
        case .cannotWrite: .cannotWrite
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }
}
