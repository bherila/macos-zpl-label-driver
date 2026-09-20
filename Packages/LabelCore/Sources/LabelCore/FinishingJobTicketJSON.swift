import CoreFoundation
import Foundation

public enum FinishingJobTicketJSONError: Error, Equatable, Sendable {
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

/// Canonical private offline finishing ticket record. It uses a distinct kind
/// and schema namespace, so ordinary queue or resolved-ticket bytes can never
/// be reinterpreted as a finishing admission, and the reverse is equally
/// rejected. Storing a record grants no scheduler, device or replay authority.
///
/// The record binds the integer canvas geometry and the native-pitch
/// provenance. The pitch value itself, like the workflow and printer
/// snapshots, is independently supplied immutable context; a store must still
/// verify canonical reference digests before trusting any of them.
public enum FinishingJobTicketJSON {
    public static let maximumBytes = 2 * 1024 * 1024
    /// Full ordinary control field shape, reused so one tested codec encodes
    /// motor speeds, darkness, tracking, geometry and signed offsets.
    private static let controlsShape = 7
    private static let rootKeys: Set<String> = [
        "kind", "schemaVersion", "acceptanceID", "cancellationSHA256", "queue",
        "workflowProfile", "printerProfile", "physicalDeviceSHA256", "nativePitch",
        "canvas", "selection", "cutAfterOutputLabels", "source", "copyOwnership",
        "pageRangeOwnership", "transformOwnership", "monochromeConversion",
        "controls", "outputLabels", "skippedPages",
    ]

    public static func encode(
        _ ticket: ResolvedFinishingJobTicket,
        maximumBytes: Int = maximumBytes
    ) throws -> Data {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw FinishingJobTicketJSONError.invalidLimit
        }
        let root: [String: Any] = [
            "kind": "offlineFinishingJobTicket",
            "schemaVersion": ResolvedFinishingJobTicket.schemaVersion,
            "acceptanceID": ticket.acceptanceID,
            "cancellationSHA256": ticket.cancellationSHA256,
            "queue": [
                "id": ticket.queue.id, "revision": ticket.queue.revision,
                "sha256": ticket.queue.sha256,
            ],
            "workflowProfile": ResolvedJobTicketJSON.reference(ticket.workflowProfile),
            "printerProfile": ResolvedJobTicketJSON.reference(ticket.printerProfile),
            "physicalDeviceSHA256": ticket.physicalDevice.sha256,
            "nativePitch": try encodePitch(ticket.nativePitch),
            "canvas": ["widthDots": ticket.canvas.width, "heightDots": ticket.canvas.height],
            "selection": [
                "mode": ticket.selection.mode.rawValue,
                "schedule": FinishingQueueJSON.encodeSchedule(ticket.selection.schedule),
            ],
            "cutAfterOutputLabels": ticket.cutAfterOutputLabels,
            "source": [
                "format": "application/pdf",
                "sha256": ticket.sourceDocumentSHA256,
                "byteCount": ticket.sourceByteCount,
                "pageCount": ticket.sourcePageCount,
                "intake": ticket.intakeProvenance.rawValue,
            ],
            "copyOwnership": ResolvedJobTicketJSON.encodeCopies(ticket.copyOwnership),
            "pageRangeOwnership": ResolvedJobTicketJSON.encodePageRanges(ticket.pageRangeOwnership),
            "transformOwnership": [
                "extraction": ticket.transformOwnership.rawValue,
                "orientation": ticket.transformOwnership.rawValue,
                "scaling": ticket.transformOwnership.rawValue,
            ],
            "monochromeConversion": ResolvedJobTicketJSON.encodeConversion(ticket.monochromeConversion),
            "controls": ResolvedJobTicketJSON.encodeControls(ticket.controls, version: controlsShape),
            "outputLabels": ticket.outputLabels.map {
                ["sourcePage": $0.sourcePage, "regionID": $0.regionID]
            },
            "skippedPages": ticket.skippedPages.map {
                ["sourcePage": $0.sourcePage, "reason": $0.reason.rawValue]
            },
        ]
        let bytes = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard bytes.count <= maximumBytes else { throw FinishingJobTicketJSONError.outputTooLarge }
        return bytes
    }

    /// Preliminary lookup only. The caller must resolve these references
    /// through its own store and then call `decode` on the same bytes.
    public static func references(
        in bytes: Data, maximumBytes: Int = maximumBytes
    ) throws -> (queue: FinishingQueuePolicyReference,
                 workflow: ImmutableProfileReference,
                 printer: ImmutableProfileReference) {
        let root = try readRoot(bytes, maximumBytes: maximumBytes)
        return try (decodeQueueReference(required(root, "queue")),
                    decodeReference(required(root, "workflowProfile")),
                    decodeReference(required(root, "printerProfile")))
    }

    /// Reads the acceptance identity from a structurally complete record. It
    /// does not accept, admit or authorize the job it names.
    public static func acceptanceID(
        in bytes: Data, maximumBytes: Int = maximumBytes
    ) throws -> String {
        try string(readRoot(bytes, maximumBytes: maximumBytes), "acceptanceID")
    }

    public static func decode(
        _ bytes: Data,
        queueReference: FinishingQueuePolicyReference,
        queue: FinishingQueueDefinition,
        device: FinishingDeviceBinding,
        workflow: WorkflowProfile,
        printer: PrinterProfile,
        maximumBytes: Int = maximumBytes
    ) throws -> ResolvedFinishingJobTicket {
        let root = try readRoot(bytes, maximumBytes: maximumBytes)
        guard try decodeQueueReference(required(root, "queue")) == queueReference else {
            throw FinishingJobTicketJSONError.invalidValue("queue")
        }
        let selection = try object(required(root, "selection"), allowed: ["mode", "schedule"])
        guard let mode = FinishingMode(rawValue: try string(selection, "mode")) else {
            throw FinishingJobTicketJSONError.invalidValue("mode")
        }
        let schedule: CutSchedule?
        do { schedule = try FinishingQueueJSON.decodeSchedule(required(selection, "schedule")) }
        catch { throw FinishingJobTicketJSONError.invalidValue("schedule") }
        let source = try object(required(root, "source"), allowed: [
            "format", "sha256", "byteCount", "pageCount", "intake",
        ])
        guard try string(source, "format") == "application/pdf" else {
            throw FinishingJobTicketJSONError.invalidValue("format")
        }
        guard let intake = JobIntakeProvenance(rawValue: try string(source, "intake")) else {
            throw FinishingJobTicketJSONError.invalidValue("intake")
        }
        let canvas = try object(required(root, "canvas"), allowed: ["widthDots", "heightDots"])
        let pitch = try decodePitch(required(root, "nativePitch"), device: device)
        let outputs = try array(root, "outputLabels", limit: ResolvedJobTicket.maximumOutputLabels)
            .map { raw -> ResolvedOutputLabel in
                let value = try object(raw, allowed: ["sourcePage", "regionID"])
                return ResolvedOutputLabel(sourcePage: try integer(value, "sourcePage"),
                                           regionID: try string(value, "regionID"))
            }
        let skipped = try array(root, "skippedPages", limit: ResolvedJobTicket.maximumSourcePages)
            .map { raw -> ResolvedSkippedPage in
                let value = try object(raw, allowed: ["sourcePage", "reason"])
                guard let reason = NonLabelPageReason(rawValue: try string(value, "reason")) else {
                    throw FinishingJobTicketJSONError.invalidValue("reason")
                }
                return ResolvedSkippedPage(sourcePage: try integer(value, "sourcePage"), reason: reason)
            }
        let boundaries = try array(root, "cutAfterOutputLabels", limit: CutSchedulePlanner.maximumLabels)
            .map { try integerValue($0, key: "cutAfterOutputLabels") }
        let ticket: ResolvedFinishingJobTicket
        do {
            ticket = try ResolvedFinishingJobTicket(
                acceptanceID: string(root, "acceptanceID"),
                cancellationSHA256: string(root, "cancellationSHA256"),
                queue: queueReference,
                workflowProfile: decodeReference(required(root, "workflowProfile")),
                printerProfile: decodeReference(required(root, "printerProfile")),
                physicalDevice: PhysicalDeviceCoordinationID(sha256: string(root, "physicalDeviceSHA256")),
                nativePitch: pitch,
                canvas: device.canvas(for: queue, workflow: workflow, printer: printer),
                selection: FinishingQueueSelection(mode: mode, schedule: schedule),
                cutAfterOutputLabels: boundaries,
                sourceDocumentSHA256: string(source, "sha256"),
                sourceByteCount: integer(source, "byteCount"),
                sourcePageCount: integer(source, "pageCount"),
                intakeProvenance: intake,
                copyOwnership: ResolvedJobTicketJSON.decodeCopies(required(root, "copyOwnership")),
                pageRangeOwnership: ResolvedJobTicketJSON.decodePageRanges(required(root, "pageRangeOwnership")),
                transformOwnership: ResolvedJobTicketJSON.decodeTransformOwnership(
                    required(root, "transformOwnership")),
                monochromeConversion: ResolvedJobTicketJSON.decodeConversion(
                    required(root, "monochromeConversion")),
                controls: ResolvedJobTicketJSON.decodeControls(required(root, "controls"),
                                                               version: controlsShape),
                outputLabels: outputs,
                skippedPages: skipped,
                queueDefinition: queue,
                device: device,
                workflow: workflow,
                printer: printer
            )
        } catch let error as FinishingJobTicketJSONError { throw error }
        catch let error as FinishingJobTicketError { throw error }
        catch { throw FinishingJobTicketJSONError.invalidValue("ticket") }
        // The declared canvas geometry must equal the geometry rebuilt from the
        // independently supplied pitch; stored dots never authorize allocation.
        guard try integer(canvas, "widthDots") == ticket.canvas.width,
              try integer(canvas, "heightDots") == ticket.canvas.height else {
            throw FinishingJobTicketJSONError.invalidValue("canvas")
        }
        // Exact canonical bytes reject duplicate keys, alternate numeric
        // spellings and any other noncanonical identity normalization.
        guard try encode(ticket, maximumBytes: maximumBytes) == bytes else {
            throw FinishingJobTicketJSONError.invalidValue("canonicalBytes")
        }
        return ticket
    }

    private static func encodePitch(_ pitch: Observation<DotResolution>) throws -> [String: Any] {
        guard case let .observed(_, evidence) = pitch else {
            throw FinishingJobTicketJSONError.invalidValue("nativePitch")
        }
        switch evidence {
        case let .documentedModel(sourceID):
            return ["evidence": "documentedModel", "sourceID": sourceID]
        case .reportedInstallation:
            return ["evidence": "reportedInstallation", "sourceID": NSNull()]
        case .observedByHost:
            // No host observation establishes a native dot pitch. The registry
            // says what the device is, never how finely it prints, so this is
            // refused exactly as an unobserved pitch is refused: fail closed
            // rather than store a provenance nothing can have produced.
            throw FinishingJobTicketJSONError.invalidValue("nativePitch")
        case .unobserved:
            throw FinishingJobTicketJSONError.invalidValue("nativePitch")
        }
    }

    /// The stored provenance must equal the independently supplied binding's.
    /// An unobserved pitch is never accepted as a default or as zero.
    private static func decodePitch(
        _ raw: Any, device: FinishingDeviceBinding
    ) throws -> Observation<DotResolution> {
        let value = try object(raw, allowed: ["evidence", "sourceID"])
        let stored: CapabilityEvidence
        switch try string(value, "evidence") {
        case "documentedModel":
            stored = .documentedModel(sourceID: try string(value, "sourceID"))
        case "reportedInstallation":
            guard try required(value, "sourceID") is NSNull else {
                throw FinishingJobTicketJSONError.invalidValue("sourceID")
            }
            stored = .reportedInstallation
        default:
            throw FinishingJobTicketJSONError.invalidValue("evidence")
        }
        guard stored == device.pitchEvidence else {
            throw FinishingJobTicketJSONError.invalidValue("nativePitch")
        }
        return device.nativePitch
    }

    private static func readRoot(_ bytes: Data, maximumBytes: Int) throws -> [String: Any] {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw FinishingJobTicketJSONError.invalidLimit
        }
        guard bytes.count <= maximumBytes else { throw FinishingJobTicketJSONError.inputTooLarge }
        let raw: Any
        do { raw = try TokenPreservingJSON.decode(bytes) }
        catch { throw FinishingJobTicketJSONError.malformedJSON }
        let root = try object(raw, allowed: rootKeys)
        guard try string(root, "kind") == "offlineFinishingJobTicket",
              try integer(root, "schemaVersion") == ResolvedFinishingJobTicket.schemaVersion else {
            throw FinishingJobTicketJSONError.unsupportedSchema
        }
        return root
    }

    private static func decodeQueueReference(_ raw: Any) throws -> FinishingQueuePolicyReference {
        let value = try object(raw, allowed: ["id", "revision", "sha256"])
        do {
            return try FinishingQueuePolicyReference(
                id: string(value, "id"), revision: integer(value, "revision"),
                sha256: string(value, "sha256"))
        } catch let error as FinishingJobTicketJSONError { throw error }
        catch { throw FinishingJobTicketJSONError.invalidValue("queue") }
    }

    private static func decodeReference(_ raw: Any) throws -> ImmutableProfileReference {
        let value = try object(raw, allowed: ["id", "schemaVersion", "revision", "sha256"])
        do {
            return try ImmutableProfileReference(
                id: string(value, "id"), schemaVersion: integer(value, "schemaVersion"),
                revision: integer(value, "revision"), sha256: string(value, "sha256"))
        } catch let error as FinishingJobTicketJSONError { throw error }
        catch { throw FinishingJobTicketJSONError.invalidValue("reference") }
    }

    private static func object(_ raw: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw FinishingJobTicketJSONError.invalidType("object")
        }
        guard Set(value.keys) == allowed else {
            if let missing = allowed.subtracting(value.keys).sorted().first {
                throw FinishingJobTicketJSONError.missingField(missing)
            }
            throw FinishingJobTicketJSONError.unknownField
        }
        return value
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw FinishingJobTicketJSONError.missingField(key) }
        return value
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try required(object, key) as? String else {
            throw FinishingJobTicketJSONError.invalidType(key)
        }
        return value
    }

    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        try integerValue(try required(object, key), key: key)
    }

    private static func integerValue(_ raw: Any, key: String) throws -> Int {
        guard let value = raw as? TokenPreservingJSON.Number, let exact = value.integerValue else {
            throw FinishingJobTicketJSONError.invalidType(key)
        }
        return exact
    }

    private static func array(_ root: [String: Any], _ key: String, limit: Int) throws -> [Any] {
        guard let value = try required(root, key) as? [Any], value.count <= limit else {
            throw FinishingJobTicketJSONError.invalidType(key)
        }
        return value
    }
}
