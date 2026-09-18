import CoreFoundation
import Foundation

public enum ActiveVirtualQueueError: Error, Equatable, Sendable {
    case invalidGeneration
    case invalidHistory
}

/// Mutable selection intent whose target remains an immutable queue revision.
/// Generation and the previous digest support compare-and-swap publication;
/// they are not scheduler state and do not mutate held-job bindings.
public struct ActiveVirtualQueueSelection: Equatable, Sendable {
    public let schemaVersion: Int
    public let generation: Int
    public let queue: ImmutableProfileReference
    public let previousQueueSHA256: String?

    public init(
        schemaVersion: Int = 1,
        generation: Int,
        queue: ImmutableProfileReference,
        previousQueueSHA256: String?
    ) throws {
        guard schemaVersion == 1, generation > 0 else {
            throw ActiveVirtualQueueError.invalidGeneration
        }
        if generation == 1 {
            guard previousQueueSHA256 == nil else { throw ActiveVirtualQueueError.invalidHistory }
        } else {
            guard let previousQueueSHA256,
                  VirtualQueueDefinition.isSHA256(previousQueueSHA256),
                  previousQueueSHA256 != queue.sha256 else {
                throw ActiveVirtualQueueError.invalidHistory
            }
        }
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.queue = queue
        self.previousQueueSHA256 = previousQueueSHA256
    }
}

public enum ActiveVirtualQueueJSONError: Error, Equatable, Sendable {
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

public enum ActiveVirtualQueueJSON {
    public static let maximumBytes = 4 * 1024

    public static func encode(
        _ selection: ActiveVirtualQueueSelection,
        maximumBytes: Int = maximumBytes
    ) throws -> Data {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw ActiveVirtualQueueJSONError.invalidLimit
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": selection.schemaVersion,
            "generation": selection.generation,
            "queue": [
                "id": selection.queue.id,
                "schemaVersion": selection.queue.schemaVersion,
                "revision": selection.queue.revision,
                "sha256": selection.queue.sha256,
            ],
            "previousQueueSHA256": selection.previousQueueSHA256.map { $0 as Any } ?? NSNull(),
        ], options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw ActiveVirtualQueueJSONError.outputTooLarge }
        return data
    }

    public static func decode(
        _ data: Data,
        maximumBytes: Int = maximumBytes
    ) throws -> ActiveVirtualQueueSelection {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw ActiveVirtualQueueJSONError.invalidLimit
        }
        guard data.count <= maximumBytes else { throw ActiveVirtualQueueJSONError.inputTooLarge }
        let raw: Any
        do { raw = try TokenPreservingJSON.decode(data) }
        catch { throw ActiveVirtualQueueJSONError.malformedJSON }
        do {
            let root = try object(raw, allowed: [
                "schemaVersion", "generation", "queue", "previousQueueSHA256",
            ])
            guard try integer(root, "schemaVersion") == 1 else {
                throw ActiveVirtualQueueJSONError.unsupportedSchema
            }
            let queue = try object(try required(root, "queue"), allowed: [
                "id", "schemaVersion", "revision", "sha256",
            ])
            let previousRaw = try required(root, "previousQueueSHA256")
            let previous: String?
            if previousRaw is NSNull { previous = nil }
            else if let value = previousRaw as? String { previous = value }
            else { throw ActiveVirtualQueueJSONError.invalidType("previousQueueSHA256") }
            return try ActiveVirtualQueueSelection(
                schemaVersion: 1,
                generation: integer(root, "generation"),
                queue: ImmutableProfileReference(
                    id: string(queue, "id"),
                    schemaVersion: integer(queue, "schemaVersion"),
                    revision: integer(queue, "revision"),
                    sha256: string(queue, "sha256")
                ),
                previousQueueSHA256: previous
            )
        } catch let error as ActiveVirtualQueueJSONError { throw error }
        catch { throw ActiveVirtualQueueJSONError.invalidValue }
    }

    private static func object(_ raw: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw ActiveVirtualQueueJSONError.invalidType("object")
        }
        guard Set(value.keys) == allowed else {
            if let missing = allowed.subtracting(value.keys).sorted().first {
                throw ActiveVirtualQueueJSONError.missingField(missing)
            }
            throw ActiveVirtualQueueJSONError.unknownField
        }
        return value
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw ActiveVirtualQueueJSONError.missingField(key) }
        return value
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try required(object, key) as? String else {
            throw ActiveVirtualQueueJSONError.invalidType(key)
        }
        return value
    }

    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        guard let value = try required(object, key) as? TokenPreservingJSON.Number,
              let exact = value.integerValue else { throw ActiveVirtualQueueJSONError.invalidType(key) }
        return exact
    }
}
