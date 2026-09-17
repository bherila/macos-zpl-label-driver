import CoreFoundation
import Foundation

public enum ResolvedJobTicketError: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidReference
    case invalidSource
    case invalidPlan
    case invalidCopyOwnership
    case invalidControls
    case invalidImaging
    case invalidLimit
    case inputTooLarge
    case outputTooLarge
    case malformedJSON
    case unknownField
    case missingField(String)
    case invalidType(String)
    case unsupportedSchema
}

/// Records which layer already expanded copies. `outputLabels` is always the
/// final ordered sequence; no downstream layer may multiply it again.
public enum JobCopyOwnership: Equatable, Sendable {
    case engine(copies: Int, collated: Bool)
    case upstreamAlreadyExpanded
}

public enum JobPageRangeOwnership: Equatable, Sendable {
    case engine(selectedSourcePages: [Int])
    case upstreamAlreadyApplied
}

public enum JobTransformOwnership: String, Equatable, Sendable {
    case workflowProfile
}

public enum JobIntakeProvenance: String, Equatable, Sendable {
    case cupsScheduler
    case offlineCLI
}

public struct ResolvedOutputLabel: Equatable, Sendable {
    public let sourcePage: Int
    public let regionID: String
}

public struct ResolvedSkippedPage: Equatable, Sendable {
    public let sourcePage: Int
    public let reason: NonLabelPageReason
}

/// Submission-time configuration snapshot. It contains no document title,
/// payload, path, endpoint, serial number, or raw printer command.
public struct ResolvedJobTicket: Equatable, Sendable {
    public static let maximumSourceBytes = 100 * 1024 * 1024
    public static let maximumSourcePages = 1_000
    public static let maximumOutputLabels = 10_000

    public let schemaVersion: Int
    public let acceptanceID: String
    public let cancellationSHA256: String
    public let activeSelectionGeneration: Int
    public let queue: ImmutableProfileReference
    public let workflowProfile: ImmutableProfileReference
    public let printerProfile: ImmutableProfileReference
    public let physicalDevice: PhysicalDeviceCoordinationID
    public let sourceDocumentSHA256: String
    public let sourceByteCount: Int
    public let sourcePageCount: Int
    public let intakeProvenance: JobIntakeProvenance
    public let copyOwnership: JobCopyOwnership
    public let pageRangeOwnership: JobPageRangeOwnership
    public let transformOwnership: JobTransformOwnership
    public let monochromeConversion: MonochromeConversion
    public let controls: ResolvedPrinterControls
    public let outputLabels: [ResolvedOutputLabel]
    public let skippedPages: [ResolvedSkippedPage]

    /// Accepts an already validated extraction plan and snapshots every
    /// configuration reference needed to reproduce its semantics later.
    public static func accept(
        acceptanceID: String,
        cancellationSHA256: String,
        activeSelection: ActiveVirtualQueueSelection,
        queueReference: ImmutableProfileReference,
        queueDefinition: VirtualQueueDefinition,
        workflowProfile: WorkflowProfile,
        printerProfile: PrinterProfile,
        sourceDocumentSHA256: String,
        sourceByteCount: Int,
        intakeProvenance: JobIntakeProvenance,
        plan: ExtractionPlan,
        copyOwnership: JobCopyOwnership,
        pageRangeOwnership: JobPageRangeOwnership,
        explicitControls: PrinterControlRequest = .init()
    ) throws -> ResolvedJobTicket {
        guard activeSelection.queue == queueReference,
              queueReference.id == queueDefinition.id,
              queueReference.schemaVersion == queueDefinition.schemaVersion,
              queueReference.revision == queueDefinition.revision,
              queueDefinition.workflowProfile.schemaVersion == workflowProfile.schemaVersion,
              queueDefinition.workflowProfile.id == workflowProfile.id,
              queueDefinition.workflowProfile.revision == workflowProfile.revision,
              queueDefinition.printerProfile.schemaVersion == printerProfile.schemaVersion,
              queueDefinition.printerProfile.revision == printerProfile.revision else {
            throw ResolvedJobTicketError.invalidReference
        }
        try validatePlan(
            plan, workflowProfile: workflowProfile, copyOwnership: copyOwnership,
            pageRangeOwnership: pageRangeOwnership
        )
        let defaults = PrinterControlDefaults(
            thermalMethod: queueDefinition.workflowDefaults.thermalMethod,
            finishing: queueDefinition.workflowDefaults.finishing,
            printSpeedIps: queueDefinition.workflowDefaults.printSpeedIps,
            feedSpeedIps: queueDefinition.workflowDefaults.feedSpeedIps,
            backfeedSpeedIps: queueDefinition.workflowDefaults.backfeedSpeedIps,
            darkness: queueDefinition.workflowDefaults.darkness,
            tracking: queueDefinition.workflowDefaults.tracking,
            mediaGeometry: queueDefinition.workflowDefaults.mediaGeometry
        )
        let controls: ResolvedPrinterControls
        do { controls = try printerProfile.resolveControls(job: explicitControls, workflowDefaults: defaults) }
        catch { throw ResolvedJobTicketError.invalidControls }
        return try ResolvedJobTicket(
            schemaVersion: queueDefinition.schemaVersion == 4 || printerProfile.schemaVersion == 5 ? 5 :
                (queueDefinition.schemaVersion == 3 || printerProfile.schemaVersion == 4 ? 4 :
                (queueDefinition.schemaVersion == 2 || printerProfile.schemaVersion == 3 ? 3 : 2)),
            acceptanceID: acceptanceID,
            cancellationSHA256: cancellationSHA256,
            activeSelectionGeneration: activeSelection.generation,
            queue: queueReference,
            workflowProfile: queueDefinition.workflowProfile,
            printerProfile: queueDefinition.printerProfile,
            physicalDevice: queueDefinition.physicalDevice,
            sourceDocumentSHA256: sourceDocumentSHA256,
            sourceByteCount: sourceByteCount,
            sourcePageCount: plan.sourcePageCount,
            intakeProvenance: intakeProvenance,
            copyOwnership: copyOwnership,
            pageRangeOwnership: pageRangeOwnership,
            transformOwnership: .workflowProfile,
            monochromeConversion: workflowProfile.monochromeConversion,
            controls: controls,
            outputLabels: plan.outputLabels.map {
                ResolvedOutputLabel(sourcePage: $0.sourcePage, regionID: $0.regionID)
            },
            skippedPages: plan.skippedPages.map {
                ResolvedSkippedPage(sourcePage: $0.sourcePage, reason: $0.reason)
            }
        )
    }

    init(
        schemaVersion: Int,
        acceptanceID: String,
        cancellationSHA256: String,
        activeSelectionGeneration: Int,
        queue: ImmutableProfileReference,
        workflowProfile: ImmutableProfileReference,
        printerProfile: ImmutableProfileReference,
        physicalDevice: PhysicalDeviceCoordinationID,
        sourceDocumentSHA256: String,
        sourceByteCount: Int,
        sourcePageCount: Int,
        intakeProvenance: JobIntakeProvenance,
        copyOwnership: JobCopyOwnership,
        pageRangeOwnership: JobPageRangeOwnership,
        transformOwnership: JobTransformOwnership,
        monochromeConversion: MonochromeConversion,
        controls: ResolvedPrinterControls,
        outputLabels: [ResolvedOutputLabel],
        skippedPages: [ResolvedSkippedPage]
    ) throws {
        guard (2...5).contains(schemaVersion) else { throw ResolvedJobTicketError.unsupportedSchema }
        guard schemaVersion >= 3 || (printerProfile.schemaVersion <= 2 && queue.schemaVersion == 1 &&
              controls.feedSpeedIps == .notExplicitlyControlled && controls.backfeedSpeedIps == .notExplicitlyControlled) else {
            throw ResolvedJobTicketError.invalidControls
        }
        guard schemaVersion >= 4 || (printerProfile.schemaVersion <= 3 && queue.schemaVersion <= 2 &&
              controls.darkness == .leaveUnchanged) else {
            throw ResolvedJobTicketError.invalidControls
        }
        guard schemaVersion == 5 || (printerProfile.schemaVersion <= 4 && queue.schemaVersion <= 3 &&
              controls.tracking == .leaveUnchanged && controls.mediaGeometry == .leaveUnchanged) else {
            throw ResolvedJobTicketError.invalidControls
        }
        guard VirtualQueueDefinition.isSelector(acceptanceID),
              VirtualQueueDefinition.isSHA256(cancellationSHA256)
        else { throw ResolvedJobTicketError.invalidIdentity }
        guard activeSelectionGeneration > 0,
              workflowProfile.schemaVersion == 2, (1...4).contains(queue.schemaVersion),
              (1...5).contains(printerProfile.schemaVersion),
              controls.profileSchemaVersion == printerProfile.schemaVersion,
              controls.profileRevision == printerProfile.revision else {
            throw ResolvedJobTicketError.invalidReference
        }
        guard VirtualQueueDefinition.isSHA256(sourceDocumentSHA256),
              (1...Self.maximumSourceBytes).contains(sourceByteCount),
              (1...Self.maximumSourcePages).contains(sourcePageCount) else {
            throw ResolvedJobTicketError.invalidSource
        }
        guard !outputLabels.isEmpty, outputLabels.count <= Self.maximumOutputLabels,
              outputLabels.allSatisfy({
                  (1...sourcePageCount).contains($0.sourcePage) && Self.isIdentity($0.regionID)
              }),
              skippedPages.allSatisfy({ (1...sourcePageCount).contains($0.sourcePage) }),
              Set(skippedPages.map(\.sourcePage)).count == skippedPages.count else {
            throw ResolvedJobTicketError.invalidPlan
        }
        let outputPages = Set(outputLabels.map(\.sourcePage))
        let skipped = Set(skippedPages.map(\.sourcePage))
        guard outputPages.isDisjoint(with: skipped) else { throw ResolvedJobTicketError.invalidPlan }
        switch copyOwnership {
        case let .engine(copies, _):
            guard copies > 0, copies <= Self.maximumOutputLabels else {
                throw ResolvedJobTicketError.invalidCopyOwnership
            }
        case .upstreamAlreadyExpanded:
            break
        }
        let selectedPages: Set<Int>
        switch pageRangeOwnership {
        case let .engine(selectedSourcePages):
            guard !selectedSourcePages.isEmpty,
                  selectedSourcePages == selectedSourcePages.sorted(),
                  Set(selectedSourcePages).count == selectedSourcePages.count,
                  selectedSourcePages.allSatisfy({ (1...sourcePageCount).contains($0) }) else {
                throw ResolvedJobTicketError.invalidPlan
            }
            selectedPages = Set(selectedSourcePages)
        case .upstreamAlreadyApplied:
            selectedPages = Set(1...sourcePageCount)
        }
        guard outputPages.union(skipped) == selectedPages else {
            throw ResolvedJobTicketError.invalidPlan
        }
        self.schemaVersion = schemaVersion
        self.acceptanceID = acceptanceID
        self.cancellationSHA256 = cancellationSHA256
        self.activeSelectionGeneration = activeSelectionGeneration
        self.queue = queue
        self.workflowProfile = workflowProfile
        self.printerProfile = printerProfile
        self.physicalDevice = physicalDevice
        self.sourceDocumentSHA256 = sourceDocumentSHA256
        self.sourceByteCount = sourceByteCount
        self.sourcePageCount = sourcePageCount
        self.intakeProvenance = intakeProvenance
        self.copyOwnership = copyOwnership
        self.pageRangeOwnership = pageRangeOwnership
        self.transformOwnership = transformOwnership
        self.monochromeConversion = monochromeConversion
        self.controls = controls
        self.outputLabels = outputLabels
        self.skippedPages = skippedPages
    }

    private static func isIdentity(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
        }
    }
}

public enum ResolvedJobTicketJSON {
    public static let maximumBytes = 2 * 1024 * 1024

    public static func encode(
        _ ticket: ResolvedJobTicket,
        maximumBytes: Int = maximumBytes
    ) throws -> Data {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw ResolvedJobTicketError.invalidLimit
        }
        let root: [String: Any] = [
            "schemaVersion": ticket.schemaVersion,
            "acceptanceID": ticket.acceptanceID,
            "cancellationSHA256": ticket.cancellationSHA256,
            "activeSelectionGeneration": ticket.activeSelectionGeneration,
            "queue": reference(ticket.queue),
            "workflowProfile": reference(ticket.workflowProfile),
            "printerProfile": reference(ticket.printerProfile),
            "physicalDeviceSHA256": ticket.physicalDevice.sha256,
            "source": [
                "format": "application/pdf",
                "sha256": ticket.sourceDocumentSHA256,
                "byteCount": ticket.sourceByteCount,
                "pageCount": ticket.sourcePageCount,
                "intake": ticket.intakeProvenance.rawValue,
            ],
            "copyOwnership": encodeCopies(ticket.copyOwnership),
            "pageRangeOwnership": encodePageRanges(ticket.pageRangeOwnership),
            "transformOwnership": [
                "extraction": ticket.transformOwnership.rawValue,
                "orientation": ticket.transformOwnership.rawValue,
                "scaling": ticket.transformOwnership.rawValue,
            ],
            "monochromeConversion": encodeConversion(ticket.monochromeConversion),
            "controls": encodeControls(ticket.controls, version: ticket.schemaVersion),
            "outputLabels": ticket.outputLabels.map {
                ["sourcePage": $0.sourcePage, "regionID": $0.regionID]
            },
            "skippedPages": ticket.skippedPages.map {
                ["sourcePage": $0.sourcePage, "reason": $0.reason.rawValue]
            },
        ]
        let bytes = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard bytes.count <= maximumBytes else { throw ResolvedJobTicketError.outputTooLarge }
        return bytes
    }

    /// Reads the queue selector from a structurally complete bounded ticket so
    /// callers can resolve its immutable records before the full validation
    /// pass. It does not itself authorize or accept the job.
    public static func queueReference(
        _ data: Data,
        maximumBytes: Int = maximumBytes
    ) throws -> ImmutableProfileReference {
        try decodeStructure(data, maximumBytes: maximumBytes).queue
    }

    /// Reads the acceptance identity from a structurally complete bounded
    /// ticket. The caller must still resolve and validate every immutable
    /// reference before treating the ticket as an accepted job.
    public static func acceptanceID(
        _ data: Data,
        maximumBytes: Int = maximumBytes
    ) throws -> String {
        try decodeStructure(data, maximumBytes: maximumBytes).acceptanceID
    }

    /// Reads the declared source size from the same complete bounded structure
    /// used by `acceptanceID`. This permits a store to enforce a cumulative
    /// scan budget before opening a potentially large source artifact.
    public static func sourceByteCount(
        _ data: Data,
        maximumBytes: Int = maximumBytes
    ) throws -> Int {
        try decodeStructure(data, maximumBytes: maximumBytes).sourceByteCount
    }

    public static func decode(
        _ data: Data,
        queueReference: ImmutableProfileReference,
        queueDefinition: VirtualQueueDefinition,
        workflowProfile: WorkflowProfile,
        printerProfile: PrinterProfile,
        maximumBytes: Int = maximumBytes
    ) throws -> ResolvedJobTicket {
        let ticket = try decodeStructure(data, maximumBytes: maximumBytes)
        guard ticket.queue == queueReference,
              queueReference.id == queueDefinition.id,
              queueReference.schemaVersion == queueDefinition.schemaVersion,
              queueReference.revision == queueDefinition.revision,
              ticket.workflowProfile == queueDefinition.workflowProfile,
              ticket.printerProfile == queueDefinition.printerProfile,
              ticket.physicalDevice == queueDefinition.physicalDevice,
              workflowProfile.schemaVersion == ticket.workflowProfile.schemaVersion,
              workflowProfile.id == ticket.workflowProfile.id,
              workflowProfile.revision == ticket.workflowProfile.revision,
              printerProfile.schemaVersion == ticket.printerProfile.schemaVersion,
              printerProfile.revision == ticket.printerProfile.revision else {
            throw ResolvedJobTicketError.invalidReference
        }
        guard ticket.monochromeConversion == workflowProfile.monochromeConversion else {
            throw ResolvedJobTicketError.invalidImaging
        }
        try validateTicketPlan(ticket, workflowProfile: workflowProfile)
        do {
            let request = controlRequest(ticket.controls)
            try printerProfile.validate(request)
            let defaults = PrinterControlDefaults(
                thermalMethod: queueDefinition.workflowDefaults.thermalMethod,
                finishing: queueDefinition.workflowDefaults.finishing,
                printSpeedIps: queueDefinition.workflowDefaults.printSpeedIps,
                feedSpeedIps: queueDefinition.workflowDefaults.feedSpeedIps,
                backfeedSpeedIps: queueDefinition.workflowDefaults.backfeedSpeedIps,
                darkness: queueDefinition.workflowDefaults.darkness,
                tracking: queueDefinition.workflowDefaults.tracking,
                mediaGeometry: queueDefinition.workflowDefaults.mediaGeometry)
            guard ticket.controls == (try printerProfile.resolveControls(job: request, workflowDefaults: defaults)) else {
                throw ResolvedJobTicketError.invalidControls
            }
        } catch { throw ResolvedJobTicketError.invalidControls }
        return ticket
    }

    private static func decodeStructure(
        _ data: Data,
        maximumBytes: Int
    ) throws -> ResolvedJobTicket {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw ResolvedJobTicketError.invalidLimit
        }
        guard data.count <= maximumBytes else { throw ResolvedJobTicketError.inputTooLarge }
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) }
        catch { throw ResolvedJobTicketError.malformedJSON }
        do {
            let root = try object(raw, keys: [
                "schemaVersion", "acceptanceID", "cancellationSHA256",
                "activeSelectionGeneration", "queue", "workflowProfile",
                "printerProfile", "physicalDeviceSHA256", "source",
                "copyOwnership", "pageRangeOwnership", "transformOwnership",
                "monochromeConversion", "controls", "outputLabels", "skippedPages",
            ])
            let version = try integer(root, "schemaVersion")
            guard (2...5).contains(version) else {
                throw ResolvedJobTicketError.unsupportedSchema
            }
            let source = try object(try required(root, "source"), keys: [
                "format", "sha256", "byteCount", "pageCount", "intake",
            ])
            guard try string(source, "format") == "application/pdf" else {
                throw ResolvedJobTicketError.invalidSource
            }
            let outputRaw = try array(root, "outputLabels", limit: ResolvedJobTicket.maximumOutputLabels)
            let output = try outputRaw.map { raw -> ResolvedOutputLabel in
                let value = try object(raw, keys: ["sourcePage", "regionID"])
                return ResolvedOutputLabel(
                    sourcePage: try integer(value, "sourcePage"),
                    regionID: try string(value, "regionID")
                )
            }
            let skippedRaw = try array(root, "skippedPages", limit: ResolvedJobTicket.maximumSourcePages)
            let skipped = try skippedRaw.map { raw -> ResolvedSkippedPage in
                let value = try object(raw, keys: ["sourcePage", "reason"])
                guard let reason = NonLabelPageReason(rawValue: try string(value, "reason")) else {
                    throw ResolvedJobTicketError.invalidPlan
                }
                return ResolvedSkippedPage(sourcePage: try integer(value, "sourcePage"), reason: reason)
            }
            return try ResolvedJobTicket(
                schemaVersion: version,
                acceptanceID: string(root, "acceptanceID"),
                cancellationSHA256: string(root, "cancellationSHA256"),
                activeSelectionGeneration: integer(root, "activeSelectionGeneration"),
                queue: decodeReference(try required(root, "queue")),
                workflowProfile: decodeReference(try required(root, "workflowProfile")),
                printerProfile: decodeReference(try required(root, "printerProfile")),
                physicalDevice: PhysicalDeviceCoordinationID(
                    sha256: string(root, "physicalDeviceSHA256")
                ),
                sourceDocumentSHA256: string(source, "sha256"),
                sourceByteCount: integer(source, "byteCount"),
                sourcePageCount: integer(source, "pageCount"),
                intakeProvenance: try decodeIntake(source),
                copyOwnership: decodeCopies(try required(root, "copyOwnership")),
                pageRangeOwnership: decodePageRanges(
                    try required(root, "pageRangeOwnership")
                ),
                transformOwnership: decodeTransformOwnership(
                    try required(root, "transformOwnership")
                ),
                monochromeConversion: decodeConversion(
                    try required(root, "monochromeConversion")
                ),
                controls: decodeControls(try required(root, "controls"), version: version),
                outputLabels: output,
                skippedPages: skipped
            )
        } catch let error as ResolvedJobTicketError { throw error }
        catch { throw ResolvedJobTicketError.malformedJSON }
    }

    private static func reference(_ value: ImmutableProfileReference) -> [String: Any] {
        [
            "id": value.id, "schemaVersion": value.schemaVersion,
            "revision": value.revision, "sha256": value.sha256,
        ]
    }

    private static func decodeReference(_ raw: Any) throws -> ImmutableProfileReference {
        let value = try object(raw, keys: ["id", "schemaVersion", "revision", "sha256"])
        return try ImmutableProfileReference(
            id: string(value, "id"), schemaVersion: integer(value, "schemaVersion"),
            revision: integer(value, "revision"), sha256: string(value, "sha256")
        )
    }

    private static func decodeIntake(_ source: [String: Any]) throws -> JobIntakeProvenance {
        guard let value = JobIntakeProvenance(rawValue: try string(source, "intake")) else {
            throw ResolvedJobTicketError.invalidSource
        }
        return value
    }

    private static func encodeCopies(_ value: JobCopyOwnership) -> [String: Any] {
        switch value {
        case let .engine(copies, collated):
            return ["owner": "engine", "copies": copies, "collated": collated]
        case .upstreamAlreadyExpanded:
            return ["owner": "upstream", "copies": NSNull(), "collated": NSNull()]
        }
    }

    private static func decodeCopies(_ raw: Any) throws -> JobCopyOwnership {
        let value = try object(raw, keys: ["owner", "copies", "collated"])
        switch try string(value, "owner") {
        case "engine":
            return .engine(
                copies: try integer(value, "copies"), collated: try boolean(value, "collated")
            )
        case "upstream":
            guard try required(value, "copies") is NSNull,
                  try required(value, "collated") is NSNull else {
                throw ResolvedJobTicketError.invalidCopyOwnership
            }
            return .upstreamAlreadyExpanded
        default:
            throw ResolvedJobTicketError.invalidCopyOwnership
        }
    }

    private static func encodePageRanges(_ value: JobPageRangeOwnership) -> [String: Any] {
        switch value {
        case let .engine(selectedSourcePages):
            ["owner": "engine", "selectedSourcePages": selectedSourcePages]
        case .upstreamAlreadyApplied:
            ["owner": "upstream", "selectedSourcePages": NSNull()]
        }
    }

    private static func decodePageRanges(_ raw: Any) throws -> JobPageRangeOwnership {
        let value = try object(raw, keys: ["owner", "selectedSourcePages"])
        switch try string(value, "owner") {
        case "engine":
            let pages = try array(
                value, "selectedSourcePages", limit: ResolvedJobTicket.maximumSourcePages
            ).map { try integerValue($0, key: "selectedSourcePages") }
            return .engine(selectedSourcePages: pages)
        case "upstream":
            guard try required(value, "selectedSourcePages") is NSNull else {
                throw ResolvedJobTicketError.invalidPlan
            }
            return .upstreamAlreadyApplied
        default:
            throw ResolvedJobTicketError.invalidPlan
        }
    }

    private static func decodeTransformOwnership(_ raw: Any) throws -> JobTransformOwnership {
        let value = try object(raw, keys: ["extraction", "orientation", "scaling"])
        guard try string(value, "extraction") == JobTransformOwnership.workflowProfile.rawValue,
              try string(value, "orientation") == JobTransformOwnership.workflowProfile.rawValue,
              try string(value, "scaling") == JobTransformOwnership.workflowProfile.rawValue else {
            throw ResolvedJobTicketError.invalidPlan
        }
        return .workflowProfile
    }

    private static func encodeConversion(_ value: MonochromeConversion) -> [String: Any] {
        switch value {
        case let .textAndBarcodeThreshold(cutoff):
            ["mode": "textAndBarcodeThreshold", "cutoff": Int(cutoff)]
        case .photographicOrderedDither4x4:
            ["mode": "photographicOrderedDither4x4", "cutoff": NSNull()]
        }
    }

    private static func decodeConversion(_ raw: Any) throws -> MonochromeConversion {
        let value = try object(raw, keys: ["mode", "cutoff"])
        switch try string(value, "mode") {
        case "textAndBarcodeThreshold":
            let cutoff = try integer(value, "cutoff")
            guard (0...255).contains(cutoff) else {
                throw ResolvedJobTicketError.invalidImaging
            }
            return .textAndBarcodeThreshold(cutoff: UInt8(cutoff))
        case "photographicOrderedDither4x4":
            guard try required(value, "cutoff") is NSNull else {
                throw ResolvedJobTicketError.invalidImaging
            }
            return .photographicOrderedDither4x4
        default:
            throw ResolvedJobTicketError.invalidImaging
        }
    }

    private static func encodeControls(_ value: ResolvedPrinterControls, version: Int) -> [String: Any] {
        var result: [String: Any] = [
            "profileSchemaVersion": value.profileSchemaVersion,
            "profileRevision": value.profileRevision,
            "thermalMethod": encodeRequired(value.thermalMethod),
            "finishing": encodeRequired(value.finishing),
            "printSpeedIps": encodeOptionalInt(value.printSpeedIps),
            "darkness": encodeOptionalInt(value.darkness),
            "tracking": encodeOptionalTracking(value.tracking),
            "mediaGeometry": encodeGeometry(value.mediaGeometry),
        ]
        if version >= 3 {
            result["feedSpeedIps"] = encodeMotorSpeed(value.feedSpeedIps)
            result["backfeedSpeedIps"] = encodeMotorSpeed(value.backfeedSpeedIps)
        }
        return result
    }

    private static func decodeControls(_ raw: Any, version: Int) throws -> ResolvedPrinterControls {
        var keys: Set<String> = ["profileSchemaVersion", "profileRevision", "thermalMethod", "finishing",
                                 "printSpeedIps", "darkness", "tracking", "mediaGeometry"]
        if version >= 3 { keys.formUnion(["feedSpeedIps", "backfeedSpeedIps"]) }
        let value = try object(raw, keys: keys)
        return ResolvedPrinterControls(
            profileSchemaVersion: try integer(value, "profileSchemaVersion"),
            profileRevision: try integer(value, "profileRevision"),
            thermalMethod: try decodeRequired(value, "thermalMethod", ThermalMethod.init(rawValue:)),
            finishing: try decodeRequired(value, "finishing", FinishingMode.init(rawValue:)),
            printSpeedIps: try decodeOptionalInt(value, "printSpeedIps"),
            feedSpeedIps: version >= 3 ? try decodeMotorSpeed(value, "feedSpeedIps") : .notExplicitlyControlled,
            backfeedSpeedIps: version >= 3 ? try decodeMotorSpeed(value, "backfeedSpeedIps") : .notExplicitlyControlled,
            darkness: try decodeOptionalInt(value, "darkness"),
            tracking: try decodeOptional(value, "tracking", MediaTracking.init(rawValue:)),
            mediaGeometry: try decodeGeometry(try required(value, "mediaGeometry"))
        )
    }

    private static func controlRequest(_ controls: ResolvedPrinterControls) -> PrinterControlRequest {
        PrinterControlRequest(
            thermalMethod: value(controls.thermalMethod),
            finishing: value(controls.finishing),
            printSpeedIps: value(controls.printSpeedIps),
            feedSpeedIps: controls.feedSpeedIps.explicitValue,
            backfeedSpeedIps: controls.backfeedSpeedIps.explicitValue,
            darkness: value(controls.darkness),
            tracking: value(controls.tracking),
            mediaGeometry: value(controls.mediaGeometry)
        )
    }

    private static func value<T>(_ setting: ResolvedSetting<T>) -> T? {
        if case let .value(value) = setting { return value }
        return nil
    }

    private static func encodeRequired<T: RawRepresentable>(_ value: ResolvedSetting<T>) -> Any
    where T.RawValue == String, T: Equatable & Sendable {
        switch value {
        case let .value(value): ["mode": "value", "value": value.rawValue]
        case .leaveUnchanged: ["mode": "leaveUnchanged", "value": NSNull()]
        }
    }

    private static func encodeMotorSpeed(_ value: ResolvedMotorSpeed) -> Any {
        switch value {
        case let .value(value): ["mode": "value", "value": value]
        case .notExplicitlyControlled: ["mode": "notExplicitlyControlled", "value": NSNull()]
        }
    }

    private static func decodeMotorSpeed(_ root: [String: Any], _ key: String) throws -> ResolvedMotorSpeed {
        let value = try setting(root, key)
        switch try string(value, "mode") {
        case "notExplicitlyControlled":
            guard try required(value, "value") is NSNull else { throw ResolvedJobTicketError.invalidControls }
            return .notExplicitlyControlled
        case "value": return .value(try integer(value, "value"))
        default: throw ResolvedJobTicketError.invalidControls
        }
    }

    private static func encodeOptionalInt(_ value: ResolvedSetting<Int>) -> Any {
        switch value {
        case let .value(value): ["mode": "value", "value": value]
        case .leaveUnchanged: ["mode": "leaveUnchanged", "value": NSNull()]
        }
    }

    private static func encodeOptionalTracking(
        _ value: ResolvedSetting<MediaTracking>
    ) -> Any {
        switch value {
        case let .value(value): ["mode": "value", "value": value.rawValue]
        case .leaveUnchanged: ["mode": "leaveUnchanged", "value": NSNull()]
        }
    }

    private static func encodeGeometry(_ value: ResolvedSetting<MediaGeometryRequest>) -> Any {
        switch value {
        case .leaveUnchanged:
            ["mode": "leaveUnchanged", "value": NSNull()]
        case let .value(geometry):
            ["mode": "value", "value": [
                "widthDots": geometry.widthDots.map { $0 as Any } ?? NSNull(),
                "lengthDots": geometry.lengthDots.map { $0 as Any } ?? NSNull(),
                "originXDot": geometry.originXDot.map { $0 as Any } ?? NSNull(),
                "originYDot": geometry.originYDot.map { $0 as Any } ?? NSNull(),
            ]]
        }
    }

    private static func decodeRequired<T: Equatable & Sendable>(
        _ root: [String: Any], _ key: String, _ parse: (String) -> T?
    ) throws -> ResolvedSetting<T> {
        let value = try setting(root, key)
        guard try string(value, "mode") == "value",
              let parsed = parse(try string(value, "value")) else {
            throw ResolvedJobTicketError.invalidControls
        }
        return .value(parsed)
    }

    private static func decodeOptional<T: Equatable & Sendable>(
        _ root: [String: Any], _ key: String, _ parse: (String) -> T?
    ) throws -> ResolvedSetting<T> {
        let value = try setting(root, key)
        switch try string(value, "mode") {
        case "leaveUnchanged":
            guard try required(value, "value") is NSNull else {
                throw ResolvedJobTicketError.invalidControls
            }
            return .leaveUnchanged
        case "value":
            guard let parsed = parse(try string(value, "value")) else {
                throw ResolvedJobTicketError.invalidControls
            }
            return .value(parsed)
        default:
            throw ResolvedJobTicketError.invalidControls
        }
    }

    private static func decodeOptionalInt(
        _ root: [String: Any], _ key: String
    ) throws -> ResolvedSetting<Int> {
        let value = try setting(root, key)
        switch try string(value, "mode") {
        case "leaveUnchanged":
            guard try required(value, "value") is NSNull else {
                throw ResolvedJobTicketError.invalidControls
            }
            return .leaveUnchanged
        case "value": return .value(try integer(value, "value"))
        default: throw ResolvedJobTicketError.invalidControls
        }
    }

    private static func decodeGeometry(_ raw: Any) throws -> ResolvedSetting<MediaGeometryRequest> {
        let setting = try object(raw, keys: ["mode", "value"])
        switch try string(setting, "mode") {
        case "leaveUnchanged":
            guard try required(setting, "value") is NSNull else {
                throw ResolvedJobTicketError.invalidControls
            }
            return .leaveUnchanged
        case "value":
            let value = try object(try required(setting, "value"), keys: [
                "widthDots", "lengthDots", "originXDot", "originYDot",
            ])
            return .value(try MediaGeometryRequest(
                widthDots: optionalInteger(value, "widthDots"),
                lengthDots: optionalInteger(value, "lengthDots"),
                originXDot: optionalInteger(value, "originXDot"),
                originYDot: optionalInteger(value, "originYDot")
            ))
        default:
            throw ResolvedJobTicketError.invalidControls
        }
    }

    private static func setting(_ root: [String: Any], _ key: String) throws -> [String: Any] {
        try object(try required(root, key), keys: ["mode", "value"])
    }

    private static func object(_ raw: Any, keys: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw ResolvedJobTicketError.invalidType("object")
        }
        let actual = Set(value.keys)
        guard actual == keys else {
            if let missing = keys.subtracting(actual).sorted().first {
                throw ResolvedJobTicketError.missingField(missing)
            }
            throw ResolvedJobTicketError.unknownField
        }
        return value
    }

    private static func required(_ root: [String: Any], _ key: String) throws -> Any {
        guard let value = root[key] else { throw ResolvedJobTicketError.missingField(key) }
        return value
    }

    private static func string(_ root: [String: Any], _ key: String) throws -> String {
        guard let value = try required(root, key) as? String else {
            throw ResolvedJobTicketError.invalidType(key)
        }
        return value
    }

    private static func integer(_ root: [String: Any], _ key: String) throws -> Int {
        try integerValue(try required(root, key), key: key)
    }

    private static func integerValue(_ raw: Any, key: String) throws -> Int {
        guard let value = raw as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
              value.doubleValue >= Double(Int.min), value.doubleValue < Double(Int.max),
              value.doubleValue == Double(value.intValue) else {
            throw ResolvedJobTicketError.invalidType(key)
        }
        return value.intValue
    }

    private static func optionalInteger(_ root: [String: Any], _ key: String) throws -> Int? {
        if try required(root, key) is NSNull { return nil }
        return try integer(root, key)
    }

    private static func boolean(_ root: [String: Any], _ key: String) throws -> Bool {
        guard let value = try required(root, key) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw ResolvedJobTicketError.invalidType(key)
        }
        return value.boolValue
    }

    private static func array(
        _ root: [String: Any], _ key: String, limit: Int
    ) throws -> [Any] {
        guard let value = try required(root, key) as? [Any], value.count <= limit else {
            throw ResolvedJobTicketError.invalidType(key)
        }
        return value
    }
}

private func validatePlan(
    _ plan: ExtractionPlan,
    workflowProfile: WorkflowProfile,
    copyOwnership: JobCopyOwnership,
    pageRangeOwnership: JobPageRangeOwnership
) throws {
    guard plan.profileID == workflowProfile.id,
          plan.profileRevision == workflowProfile.revision else {
        throw ResolvedJobTicketError.invalidPlan
    }
    let actual = plan.outputLabels.map {
        ResolvedOutputLabel(sourcePage: $0.sourcePage, regionID: $0.regionID)
    }
    let skipped = plan.skippedPages.map {
        ResolvedSkippedPage(sourcePage: $0.sourcePage, reason: $0.reason)
    }
    try validatePlanMapping(
        sourcePageCount: plan.sourcePageCount,
        outputLabels: actual,
        skippedPages: skipped,
        workflowProfile: workflowProfile,
        copyOwnership: copyOwnership,
        pageRangeOwnership: pageRangeOwnership
    )
}

private func validateTicketPlan(
    _ ticket: ResolvedJobTicket,
    workflowProfile: WorkflowProfile
) throws {
    try validatePlanMapping(
        sourcePageCount: ticket.sourcePageCount,
        outputLabels: ticket.outputLabels,
        skippedPages: ticket.skippedPages,
        workflowProfile: workflowProfile,
        copyOwnership: ticket.copyOwnership,
        pageRangeOwnership: ticket.pageRangeOwnership
    )
}

private func validatePlanMapping(
    sourcePageCount: Int,
    outputLabels: [ResolvedOutputLabel],
    skippedPages: [ResolvedSkippedPage],
    workflowProfile: WorkflowProfile,
    copyOwnership: JobCopyOwnership,
    pageRangeOwnership: JobPageRangeOwnership
) throws {
    guard workflowProfile.pageRules.count == sourcePageCount else {
        throw ResolvedJobTicketError.invalidPlan
    }
    var base: [(order: Int, label: ResolvedOutputLabel)] = []
    var expectedSkipped: [ResolvedSkippedPage] = []
    let selectedPages: Set<Int>
    switch pageRangeOwnership {
    case let .engine(selectedSourcePages): selectedPages = Set(selectedSourcePages)
    case .upstreamAlreadyApplied: selectedPages = Set(1...sourcePageCount)
    }
    for rule in workflowProfile.pageRules where selectedPages.contains(rule.sourcePage) {
        switch rule.disposition {
        case let .extract(regions):
            for region in regions {
                base.append((
                    region.outputOrder,
                    ResolvedOutputLabel(sourcePage: rule.sourcePage, regionID: region.id)
                ))
            }
        case let .skip(reason):
            expectedSkipped.append(ResolvedSkippedPage(sourcePage: rule.sourcePage, reason: reason))
        }
    }
    let ordered = base.sorted { $0.order < $1.order }.map(\.label)
    let expectedOutput: [ResolvedOutputLabel]
    switch copyOwnership {
    case let .engine(copies, collated):
        let (expectedCount, overflow) = ordered.count.multipliedReportingOverflow(by: copies)
        guard copies > 0, copies <= ResolvedJobTicket.maximumOutputLabels,
              !overflow, expectedCount <= ResolvedJobTicket.maximumOutputLabels else {
            throw ResolvedJobTicketError.invalidCopyOwnership
        }
        if collated {
            expectedOutput = (0..<copies).flatMap { _ in ordered }
        } else {
            expectedOutput = ordered.flatMap { label in (0..<copies).map { _ in label } }
        }
    case .upstreamAlreadyExpanded:
        guard ordered.count <= ResolvedJobTicket.maximumOutputLabels else {
            throw ResolvedJobTicketError.invalidPlan
        }
        expectedOutput = ordered
    }
    guard outputLabels == expectedOutput,
          skippedPages == expectedSkipped.sorted(by: { $0.sourcePage < $1.sourcePage }) else {
        throw ResolvedJobTicketError.invalidPlan
    }
}
