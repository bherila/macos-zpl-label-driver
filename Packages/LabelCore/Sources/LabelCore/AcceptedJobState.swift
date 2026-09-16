import CoreFoundation
import Foundation

public enum AcceptedJobPhase: Equatable, Sendable {
    case accepted
    case prepared(payloadSHA256: String, byteCount: Int)
    case waiting(payloadSHA256: String, byteCount: Int)
    case transmitting(payloadSHA256: String, byteCount: Int, bytesAccepted: Int)
    case transmitted(payloadSHA256: String, byteCount: Int)
    case deviceConfirmed(payloadSHA256: String, byteCount: Int)
    case uncertain(payloadSHA256: String, byteCount: Int, bytesAccepted: Int)
    case failedBeforeTransmission
    case cancelledBeforeTransmission
}

public enum AcceptedJobStateError: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidGeneration
    case invalidHistory
    case invalidPayload
    case invalidTransition
}

/// Canonical, append-only-in-meaning job state. A mutable store may replace its
/// current record, but every replacement names the digest of the exact prior
/// canonical record so stale writers and broken histories fail closed.
public struct AcceptedJobStateRecord: Equatable, Sendable {
    public let schemaVersion: Int
    public let acceptanceID: String
    public let generation: Int
    public let previousStateSHA256: String?
    public let phase: AcceptedJobPhase

    public init(
        schemaVersion: Int = 1,
        acceptanceID: String,
        generation: Int,
        previousStateSHA256: String?,
        phase: AcceptedJobPhase
    ) throws {
        guard schemaVersion == 1,
              (try? ImmutableProfileReference(
                id: acceptanceID, revision: 1,
                sha256: String(repeating: "0", count: 64)
              )) != nil else { throw AcceptedJobStateError.invalidIdentity }
        guard generation > 0 else { throw AcceptedJobStateError.invalidGeneration }
        if generation == 1 {
            guard previousStateSHA256 == nil, phase == .accepted else {
                throw AcceptedJobStateError.invalidHistory
            }
        } else {
            guard let previousStateSHA256,
                  VirtualQueueDefinition.isSHA256(previousStateSHA256),
                  phase != .accepted else {
                throw AcceptedJobStateError.invalidHistory
            }
        }
        try Self.validatePayload(phase)
        self.schemaVersion = schemaVersion
        self.acceptanceID = acceptanceID
        self.generation = generation
        self.previousStateSHA256 = previousStateSHA256
        self.phase = phase
    }

    public static func accepted(acceptanceID: String) throws -> Self {
        try Self(
            acceptanceID: acceptanceID, generation: 1,
            previousStateSHA256: nil, phase: .accepted
        )
    }

    public func advanced(
        to next: AcceptedJobPhase,
        previousStateSHA256: String
    ) throws -> Self {
        guard generation < Int.max,
              VirtualQueueDefinition.isSHA256(previousStateSHA256),
              Self.allows(from: phase, to: next) else {
            throw AcceptedJobStateError.invalidTransition
        }
        return try Self(
            acceptanceID: acceptanceID, generation: generation + 1,
            previousStateSHA256: previousStateSHA256, phase: next
        )
    }

    private static func payload(_ phase: AcceptedJobPhase) -> (String, Int, Int?)? {
        switch phase {
        case let .prepared(hash, count), let .waiting(hash, count),
             let .transmitted(hash, count), let .deviceConfirmed(hash, count):
            (hash, count, nil)
        case let .transmitting(hash, count, accepted),
             let .uncertain(hash, count, accepted):
            (hash, count, accepted)
        default: nil
        }
    }

    private static func validatePayload(_ phase: AcceptedJobPhase) throws {
        guard let (hash, count, accepted) = payload(phase) else { return }
        guard VirtualQueueDefinition.isSHA256(hash), count > 0,
              accepted.map({ (0...count).contains($0) }) ?? true else {
            throw AcceptedJobStateError.invalidPayload
        }
    }

    private static func samePayload(
        _ left: AcceptedJobPhase, _ right: AcceptedJobPhase
    ) -> Bool {
        guard let lhs = payload(left), let rhs = payload(right) else { return false }
        return lhs.0 == rhs.0 && lhs.1 == rhs.1
    }

    private static func allows(
        from current: AcceptedJobPhase, to next: AcceptedJobPhase
    ) -> Bool {
        switch (current, next) {
        case (.accepted, .prepared),
             (.accepted, .failedBeforeTransmission),
             (.accepted, .cancelledBeforeTransmission): return true
        case (.prepared, .waiting): return samePayload(current, next)
        case (.prepared, .failedBeforeTransmission),
             (.prepared, .cancelledBeforeTransmission),
             (.waiting, .failedBeforeTransmission),
             (.waiting, .cancelledBeforeTransmission): return true
        case let (.waiting, .transmitting(_, _, accepted)):
            return samePayload(current, next) && accepted >= 0
        case let (.waiting, .uncertain(_, _, accepted)):
            return samePayload(current, next) && accepted == 0
        case let (.transmitting(_, _, prior), .transmitting(_, _, accepted)):
            return samePayload(current, next) && accepted >= prior
        case let (.transmitting(_, count, accepted), .transmitted):
            return samePayload(current, next) && accepted == count
        case let (.transmitting(_, _, prior), .uncertain(_, _, accepted)):
            return samePayload(current, next) && accepted >= prior
        case (.transmitted, .deviceConfirmed):
            return samePayload(current, next)
        case let (.transmitted(_, count), .uncertain(_, _, accepted)):
            return samePayload(current, next) && accepted == count
        default: return false
        }
    }
}

public enum AcceptedJobStateJSONError: Error, Equatable, Sendable {
    case invalidLimit
    case inputTooLarge
    case outputTooLarge
    case malformedJSON
    case unknownField
    case missingField(String)
    case invalidType(String)
    case unsupportedSchema
    case invalidValue
}

public enum AcceptedJobStateJSON {
    public static let maximumBytes = 8 * 1024

    public static func encode(
        _ record: AcceptedJobStateRecord,
        maximumBytes: Int = maximumBytes
    ) throws -> Data {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw AcceptedJobStateJSONError.invalidLimit
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": record.schemaVersion,
            "acceptanceID": record.acceptanceID,
            "generation": record.generation,
            "previousStateSHA256": record.previousStateSHA256.map { $0 as Any } ?? NSNull(),
            "phase": phaseObject(record.phase),
        ], options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw AcceptedJobStateJSONError.outputTooLarge }
        return data
    }

    public static func decode(
        _ data: Data,
        maximumBytes: Int = maximumBytes
    ) throws -> AcceptedJobStateRecord {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw AcceptedJobStateJSONError.invalidLimit
        }
        guard data.count <= maximumBytes else { throw AcceptedJobStateJSONError.inputTooLarge }
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) }
        catch { throw AcceptedJobStateJSONError.malformedJSON }
        do {
            let root = try object(raw, allowed: [
                "schemaVersion", "acceptanceID", "generation",
                "previousStateSHA256", "phase",
            ])
            guard try integer(root, "schemaVersion") == 1 else {
                throw AcceptedJobStateJSONError.unsupportedSchema
            }
            let previousRaw = try required(root, "previousStateSHA256")
            let previous: String?
            if previousRaw is NSNull { previous = nil }
            else if let value = previousRaw as? String { previous = value }
            else { throw AcceptedJobStateJSONError.invalidType("previousStateSHA256") }
            return try AcceptedJobStateRecord(
                acceptanceID: string(root, "acceptanceID"),
                generation: integer(root, "generation"),
                previousStateSHA256: previous,
                phase: phase(try required(root, "phase"))
            )
        } catch let error as AcceptedJobStateJSONError { throw error }
        catch { throw AcceptedJobStateJSONError.invalidValue }
    }

    private static func phaseObject(_ phase: AcceptedJobPhase) -> [String: Any] {
        var result: [String: Any] = ["kind": kind(phase)]
        switch phase {
        case let .prepared(hash, count), let .waiting(hash, count),
             let .transmitted(hash, count), let .deviceConfirmed(hash, count):
            result["payloadSHA256"] = hash; result["byteCount"] = count
        case let .transmitting(hash, count, accepted),
             let .uncertain(hash, count, accepted):
            result["payloadSHA256"] = hash; result["byteCount"] = count
            result["bytesAccepted"] = accepted
        default: break
        }
        return result
    }

    private static func kind(_ phase: AcceptedJobPhase) -> String {
        switch phase {
        case .accepted: "accepted"
        case .prepared: "prepared"
        case .waiting: "waiting"
        case .transmitting: "transmitting"
        case .transmitted: "transmitted"
        case .deviceConfirmed: "deviceConfirmed"
        case .uncertain: "uncertain"
        case .failedBeforeTransmission: "failedBeforeTransmission"
        case .cancelledBeforeTransmission: "cancelledBeforeTransmission"
        }
    }

    private static func phase(_ raw: Any) throws -> AcceptedJobPhase {
        guard let value = raw as? [String: Any], let kind = value["kind"] as? String else {
            throw AcceptedJobStateJSONError.invalidType("phase")
        }
        let payloadKeys: Set<String> = ["kind", "payloadSHA256", "byteCount"]
        let progressKeys = payloadKeys.union(["bytesAccepted"])
        switch kind {
        case "accepted": try exact(value, ["kind"]); return .accepted
        case "prepared": try exact(value, payloadKeys); return .prepared(payloadSHA256: try string(value, "payloadSHA256"), byteCount: try integer(value, "byteCount"))
        case "waiting": try exact(value, payloadKeys); return .waiting(payloadSHA256: try string(value, "payloadSHA256"), byteCount: try integer(value, "byteCount"))
        case "transmitting": try exact(value, progressKeys); return .transmitting(payloadSHA256: try string(value, "payloadSHA256"), byteCount: try integer(value, "byteCount"), bytesAccepted: try integer(value, "bytesAccepted"))
        case "transmitted": try exact(value, payloadKeys); return .transmitted(payloadSHA256: try string(value, "payloadSHA256"), byteCount: try integer(value, "byteCount"))
        case "deviceConfirmed": try exact(value, payloadKeys); return .deviceConfirmed(payloadSHA256: try string(value, "payloadSHA256"), byteCount: try integer(value, "byteCount"))
        case "uncertain": try exact(value, progressKeys); return .uncertain(payloadSHA256: try string(value, "payloadSHA256"), byteCount: try integer(value, "byteCount"), bytesAccepted: try integer(value, "bytesAccepted"))
        case "failedBeforeTransmission": try exact(value, ["kind"]); return .failedBeforeTransmission
        case "cancelledBeforeTransmission": try exact(value, ["kind"]); return .cancelledBeforeTransmission
        default: throw AcceptedJobStateJSONError.invalidValue
        }
    }

    private static func exact(_ object: [String: Any], _ keys: Set<String>) throws {
        guard Set(object.keys) == keys else { throw AcceptedJobStateJSONError.unknownField }
    }
    private static func object(_ raw: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else { throw AcceptedJobStateJSONError.invalidType("object") }
        guard Set(value.keys) == allowed else {
            if let missing = allowed.subtracting(value.keys).sorted().first { throw AcceptedJobStateJSONError.missingField(missing) }
            throw AcceptedJobStateJSONError.unknownField
        }
        return value
    }
    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw AcceptedJobStateJSONError.missingField(key) }
        return value
    }
    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try required(object, key) as? String else { throw AcceptedJobStateJSONError.invalidType(key) }
        return value
    }
    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        guard let number = try required(object, key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue >= Double(Int.min), number.doubleValue < Double(Int.max),
              number.doubleValue == Double(number.intValue) else {
            throw AcceptedJobStateJSONError.invalidType(key)
        }
        return number.intValue
    }
}
