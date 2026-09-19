import CoreFoundation
import Foundation

public enum FinishingQueueJSONError: Error, Equatable, Sendable {
    case invalidLimit
    case inputTooLarge
    case outputTooLarge
    case malformedJSON
    case unknownField
    case missingField(String)
    case invalidType(String)
    case unsupportedSchema
    case invalidValue(String)
}

/// Canonical private offline finishing policy. Ordinary queue schemas are not accepted.
public enum FinishingQueueJSON {
    public static let maximumBytes = 16 * 1024
    private static let keys: Set<String> = ["kind", "schemaVersion", "id", "revision", "displayName",
        "physicalDeviceSHA256", "workflowProfile", "printerProfile", "selection", "defaults"]
    public static func encode(_ queue: FinishingQueueDefinition) throws -> Data {
        let d = queue.workflowDefaults
        let defaults: [String: Any] = [
            "thermalMethod": d.thermalMethod.map { $0.rawValue as Any } ?? NSNull(),
            "finishing": d.finishing.map { $0.rawValue as Any } ?? NSNull(),
            "printSpeedIps": d.printSpeedIps.map { $0 as Any } ?? NSNull(),
            "feedSpeedIps": d.feedSpeedIps.map { $0 as Any } ?? NSNull(),
            "backfeedSpeedIps": d.backfeedSpeedIps.map { $0 as Any } ?? NSNull(),
            "darkness": d.darkness.map { $0 as Any } ?? NSNull(),
            "tracking": d.tracking.map { $0.rawValue as Any } ?? NSNull(),
            "mediaGeometry": PrivatePhysicalGeometryJSON.encode(d.mediaGeometry),
            "offsets": PrivateOffsetJSON.encode(d.offsets)]
        let root: [String: Any] = ["kind": "offlineFinishingQueue", "schemaVersion": 1,
            "id": queue.id, "revision": queue.revision, "displayName": queue.displayName,
            "physicalDeviceSHA256": queue.physicalDevice.sha256,
            "workflowProfile": encodeReference(queue.workflowProfile),
            "printerProfile": encodeReference(queue.printerProfile),
            "selection": ["mode": queue.defaultSelection.mode.rawValue,
                          "schedule": encodeSchedule(queue.defaultSelection.schedule)], "defaults": defaults]
        let bytes = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard bytes.count <= maximumBytes else { throw FinishingQueueJSONError.outputTooLarge }
        return bytes
    }
    public static func references(in bytes: Data) throws -> (workflow: ImmutableProfileReference, printer: ImmutableProfileReference) {
        let root = try readRoot(bytes)
        return try (decodeReference(required(root, "workflowProfile")), decodeReference(required(root, "printerProfile")))
    }
    public static func decode(_ bytes: Data, workflow: WorkflowProfile, printer: PrinterProfile) throws -> FinishingQueueDefinition {
        let root = try readRoot(bytes)
        let selection = try object(required(root, "selection"), allowed: ["mode", "schedule"])
        guard let mode = FinishingMode(rawValue: try string(selection, "mode")) else { throw FinishingQueueJSONError.invalidValue("mode") }
        let d = try object(required(root, "defaults"), allowed: ["thermalMethod", "finishing", "printSpeedIps",
            "feedSpeedIps", "backfeedSpeedIps", "darkness", "tracking", "mediaGeometry", "offsets"])
        let queue = try FinishingQueueDefinition(id: string(root, "id"), revision: integer(root, "revision"),
            displayName: string(root, "displayName"), physicalDevice: .init(sha256: string(root, "physicalDeviceSHA256")),
            workflowProfile: decodeReference(required(root, "workflowProfile")),
            printerProfile: decodeReference(required(root, "printerProfile")),
            defaultSelection: .init(mode: mode, schedule: decodeSchedule(required(selection, "schedule"))),
            workflowDefaults: .init(thermalMethod: optionalEnum(d, "thermalMethod", ThermalMethod.self),
                finishing: optionalEnum(d, "finishing", FinishingMode.self),
                printSpeedIps: optionalInteger(d, "printSpeedIps"), feedSpeedIps: optionalInteger(d, "feedSpeedIps"),
                backfeedSpeedIps: optionalInteger(d, "backfeedSpeedIps"), darkness: optionalInteger(d, "darkness"),
                tracking: optionalEnum(d, "tracking", MediaTracking.self),
                mediaGeometry: PrivatePhysicalGeometryJSON.decode(required(d, "mediaGeometry")),
                offsets: PrivateOffsetJSON.decode(required(d, "offsets"))),
            validatingWorkflow: workflow, validatingPrinter: printer)
        // Exact canonical bytes reject duplicate keys, alternate numeric spellings
        // and noncanonical data before publication or reference hashing.
        guard try encode(queue) == bytes else { throw FinishingQueueJSONError.invalidValue("canonicalBytes") }
        return queue
    }
    private static func readRoot(_ bytes: Data) throws -> [String: Any] {
        guard bytes.count <= maximumBytes else { throw FinishingQueueJSONError.inputTooLarge }
        let raw: Any
        do { raw = try TokenPreservingJSON.decode(bytes) }
        catch { throw FinishingQueueJSONError.malformedJSON }
        let root = try object(raw, allowed: keys)
        guard try string(root, "kind") == "offlineFinishingQueue", try integer(root, "schemaVersion") == 1 else {
            throw FinishingQueueJSONError.unsupportedSchema
        }
        return root
    }
    private static func optionalInteger(_ d: [String: Any], _ key: String) throws -> Int? {
        if try required(d, key) is NSNull { return nil }; return try integer(d, key)
    }
    private static func optionalEnum<T: RawRepresentable>(_ d: [String: Any], _ key: String, _ type: T.Type) throws -> T? where T.RawValue == String {
        if try required(d, key) is NSNull { return nil }
        guard let value = T(rawValue: try string(d, key)) else { throw FinishingQueueJSONError.invalidValue(key) }
        return value
    }
    static func encodeSchedule(_ schedule: CutSchedule?) -> Any {
        guard let schedule else { return NSNull() }
        switch schedule {
        case .everyLabel: return ["kind": "everyLabel"]
        case .endOfJob: return ["kind": "endOfJob"]
        case let .batch(size, remainder): return ["kind": "batch", "size": size, "cutRemainderAtJobEnd": remainder]
        }
    }
    static func decodeSchedule(_ raw: Any) throws -> CutSchedule? {
        if raw is NSNull { return nil }
        guard let d = raw as? [String: Any] else { throw FinishingQueueJSONError.invalidType("schedule") }
        switch try string(d, "kind") {
        case "everyLabel": _ = try object(d, allowed: ["kind"]); return .everyLabel
        case "endOfJob": _ = try object(d, allowed: ["kind"]); return .endOfJob
        case "batch":
            _ = try object(d, allowed: ["kind", "size", "cutRemainderAtJobEnd"])
            guard let n = try required(d, "cutRemainderAtJobEnd") as? NSNumber,
                  CFGetTypeID(n) == CFBooleanGetTypeID() else { throw FinishingQueueJSONError.invalidType("cutRemainderAtJobEnd") }
            return try .batch(size: integer(d, "size"), cutRemainderAtJobEnd: n.boolValue)
        default: throw FinishingQueueJSONError.invalidValue("schedule")
        }
    }
    private static func encodeReference(_ reference: ImmutableProfileReference) -> [String: Any] {
        [
            "id": reference.id, "schemaVersion": reference.schemaVersion,
            "revision": reference.revision, "sha256": reference.sha256,
        ]
    }

    private static func decodeReference(_ raw: Any) throws -> ImmutableProfileReference {
        let value = try object(raw, allowed: ["id", "schemaVersion", "revision", "sha256"])
        return try ImmutableProfileReference(
            id: string(value, "id"), schemaVersion: integer(value, "schemaVersion"),
            revision: integer(value, "revision"), sha256: string(value, "sha256")
        )
    }

    private static func object(_ raw: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw FinishingQueueJSONError.invalidType("object")
        }
        guard Set(value.keys) == allowed else {
            if let missing = allowed.subtracting(value.keys).sorted().first {
                throw FinishingQueueJSONError.missingField(missing)
            }
            throw FinishingQueueJSONError.unknownField
        }
        return value
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw FinishingQueueJSONError.missingField(key) }
        return value
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try required(object, key) as? String else {
            throw FinishingQueueJSONError.invalidType(key)
        }
        return value
    }

    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        guard let value = try required(object, key) as? TokenPreservingJSON.Number,
              let exact = value.integerValue else { throw FinishingQueueJSONError.invalidType(key) }
        return exact
    }
}
