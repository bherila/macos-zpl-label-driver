import CoreFoundation
import Foundation

public enum VirtualQueueError: Error, Equatable, Sendable {
    case invalidSelector(String)
    case invalidDisplayName
    case invalidDigest
    case invalidRevision
    case invalidDefaults
    case printerProfileMismatch
    case tooManyQueues
    case duplicateQueueID(String)
}

public struct ImmutableProfileReference: Equatable, Sendable {
    public let id: String
    public let schemaVersion: Int
    public let revision: Int
    public let sha256: String

    public init(id: String, schemaVersion: Int = 1, revision: Int, sha256: String) throws {
        guard VirtualQueueDefinition.isSelector(id) else {
            throw VirtualQueueError.invalidSelector(id)
        }
        guard schemaVersion == 1, revision > 0 else { throw VirtualQueueError.invalidRevision }
        guard VirtualQueueDefinition.isSHA256(sha256) else { throw VirtualQueueError.invalidDigest }
        self.id = id
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.sha256 = sha256
    }
}

public struct PhysicalDeviceCoordinationID: Equatable, Hashable, Sendable {
    public let sha256: String

    public init(sha256: String) throws {
        guard VirtualQueueDefinition.isSHA256(sha256) else { throw VirtualQueueError.invalidDigest }
        self.sha256 = sha256
    }
}

/// Immutable product-owned queue intent. It is not proof that a CUPS queue
/// exists. Selectors are never interpreted as paths or command fragments.
public struct VirtualQueueDefinition: Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let revision: Int
    public let displayName: String
    public let physicalDevice: PhysicalDeviceCoordinationID
    public let workflowProfile: ImmutableProfileReference
    public let printerProfile: ImmutableProfileReference
    public let workflowDefaults: PrinterControlRequest

    public init(
        schemaVersion: Int = 1,
        id: String,
        revision: Int,
        displayName: String,
        physicalDevice: PhysicalDeviceCoordinationID,
        workflowProfile: ImmutableProfileReference,
        printerProfile: ImmutableProfileReference,
        workflowDefaults: PrinterControlRequest,
        validatingAgainst profile: PrinterProfile
    ) throws {
        guard schemaVersion == 1, revision > 0 else { throw VirtualQueueError.invalidRevision }
        guard Self.isSelector(id) else { throw VirtualQueueError.invalidSelector(id) }
        guard !displayName.isEmpty, displayName.utf8.count <= 128,
              displayName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw VirtualQueueError.invalidDisplayName
        }
        guard printerProfile.schemaVersion == profile.schemaVersion,
              printerProfile.revision == profile.revision else {
            throw VirtualQueueError.printerProfileMismatch
        }
        try profile.validate(workflowDefaults)
        guard workflowDefaults.thermalMethod == .directThermal,
              workflowDefaults.finishing == .tearOff,
              workflowDefaults.darkness == nil,
              workflowDefaults.tracking == nil,
              workflowDefaults.mediaGeometry == nil else {
            throw VirtualQueueError.invalidDefaults
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.displayName = displayName
        self.physicalDevice = physicalDevice
        self.workflowProfile = workflowProfile
        self.printerProfile = printerProfile
        self.workflowDefaults = workflowDefaults
    }

    public var schedulerQueueName: String { "label-driver-\(id)" }

    static func isSelector(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...48).contains(bytes.count), let first = bytes.first,
              (0x61...0x7a).contains(first) || (0x30...0x39).contains(first) else { return false }
        return bytes.allSatisfy {
            (0x61...0x7a).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2d
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 64 && bytes.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

public struct VirtualQueueCatalog: Equatable, Sendable {
    public let queues: [VirtualQueueDefinition]

    public init(_ queues: [VirtualQueueDefinition]) throws {
        guard queues.count <= 64 else { throw VirtualQueueError.tooManyQueues }
        var seen = Set<String>()
        for queue in queues where !seen.insert(queue.id).inserted {
            throw VirtualQueueError.duplicateQueueID(queue.id)
        }
        self.queues = queues
    }

    public func targeting(_ device: PhysicalDeviceCoordinationID) -> [VirtualQueueDefinition] {
        queues.filter { $0.physicalDevice == device }
    }
}

public enum VirtualQueueJSONError: Error, Equatable, Sendable {
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

/// Exact bounded version-1 publication contract for the unprivileged setup app
/// and a later installed consumer. Raw paths, commands, documents, and device
/// identities have no fields in this schema.
public enum VirtualQueueJSON {
    public static let maximumBytes = 16 * 1024

    public static func encode(
        _ queue: VirtualQueueDefinition,
        maximumBytes: Int = maximumBytes
    ) throws -> Data {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw VirtualQueueJSONError.invalidLimit
        }
        let speed: Any = queue.workflowDefaults.printSpeedIps.map { $0 as Any } ?? NSNull()
        let root: [String: Any] = [
            "schemaVersion": queue.schemaVersion,
            "id": queue.id,
            "revision": queue.revision,
            "displayName": queue.displayName,
            "physicalDeviceSHA256": queue.physicalDevice.sha256,
            "workflowProfile": encodeReference(queue.workflowProfile),
            "printerProfile": encodeReference(queue.printerProfile),
            "defaults": [
                "thermalMethod": "directThermal",
                "finishing": "tearOff",
                "printSpeedIps": speed,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw VirtualQueueJSONError.outputTooLarge }
        return data
    }

    public static func decode(
        _ data: Data,
        validatingAgainst profile: PrinterProfile,
        maximumBytes: Int = maximumBytes
    ) throws -> VirtualQueueDefinition {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw VirtualQueueJSONError.invalidLimit
        }
        guard data.count <= maximumBytes else { throw VirtualQueueJSONError.inputTooLarge }
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) }
        catch { throw VirtualQueueJSONError.malformedJSON }
        do {
            let root = try object(raw, allowed: [
                "schemaVersion", "id", "revision", "displayName", "physicalDeviceSHA256",
                "workflowProfile", "printerProfile", "defaults",
            ])
            guard try integer(root, "schemaVersion") == 1 else {
                throw VirtualQueueJSONError.unsupportedSchema
            }
            let defaults = try object(try required(root, "defaults"), allowed: [
                "thermalMethod", "finishing", "printSpeedIps",
            ])
            guard try string(defaults, "thermalMethod") == "directThermal",
                  try string(defaults, "finishing") == "tearOff" else {
                throw VirtualQueueJSONError.invalidValue("defaults")
            }
            let speed: Int?
            if try required(defaults, "printSpeedIps") is NSNull { speed = nil }
            else { speed = try integer(defaults, "printSpeedIps") }
            return try VirtualQueueDefinition(
                schemaVersion: 1,
                id: string(root, "id"),
                revision: integer(root, "revision"),
                displayName: string(root, "displayName"),
                physicalDevice: PhysicalDeviceCoordinationID(
                    sha256: string(root, "physicalDeviceSHA256")
                ),
                workflowProfile: decodeReference(try required(root, "workflowProfile")),
                printerProfile: decodeReference(try required(root, "printerProfile")),
                workflowDefaults: PrinterControlRequest(
                    thermalMethod: .directThermal, finishing: .tearOff, printSpeedIps: speed
                ),
                validatingAgainst: profile
            )
        } catch let error as VirtualQueueJSONError { throw error }
        catch { throw VirtualQueueJSONError.invalidValue("queue") }
    }

    /// Reads only the immutable printer reference needed to resolve the exact
    /// profile before a full validation pass. The root key set and size are
    /// still exact; callers must subsequently call `decode` on the same bytes.
    public static func printerProfileReference(
        in data: Data,
        maximumBytes: Int = maximumBytes
    ) throws -> ImmutableProfileReference {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw VirtualQueueJSONError.invalidLimit
        }
        guard data.count <= maximumBytes else { throw VirtualQueueJSONError.inputTooLarge }
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) }
        catch { throw VirtualQueueJSONError.malformedJSON }
        let root = try object(raw, allowed: [
            "schemaVersion", "id", "revision", "displayName", "physicalDeviceSHA256",
            "workflowProfile", "printerProfile", "defaults",
        ])
        guard try integer(root, "schemaVersion") == 1 else {
            throw VirtualQueueJSONError.unsupportedSchema
        }
        do { return try decodeReference(required(root, "printerProfile")) }
        catch let error as VirtualQueueJSONError { throw error }
        catch { throw VirtualQueueJSONError.invalidValue("printerProfile") }
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
            throw VirtualQueueJSONError.invalidType("object")
        }
        guard Set(value.keys) == allowed else {
            if let missing = allowed.subtracting(value.keys).sorted().first {
                throw VirtualQueueJSONError.missingField(missing)
            }
            throw VirtualQueueJSONError.unknownField
        }
        return value
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw VirtualQueueJSONError.missingField(key) }
        return value
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try required(object, key) as? String else {
            throw VirtualQueueJSONError.invalidType(key)
        }
        return value
    }

    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        guard let value = try required(object, key) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite,
              value.doubleValue.rounded(.towardZero) == value.doubleValue,
              value.doubleValue >= Double(Int.min), value.doubleValue < Double(Int.max) else {
            throw VirtualQueueJSONError.invalidType(key)
        }
        return Int(value.doubleValue)
    }
}
