import CoreFoundation
import Foundation

public enum PrinterProfileJSONError: Error, Equatable, Sendable {
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

/// Exact bounded private persistence contract for immutable printer profiles.
/// This format is not an application-facing capability advertisement.
public enum PrinterProfileJSON {
    public static let maximumBytes = 32 * 1024

    public static func encode(
        _ profile: PrinterProfile,
        maximumBytes: Int = maximumBytes
    ) throws -> Data {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw PrinterProfileJSONError.invalidLimit
        }
        try validateForEncoding(profile)
        var root: [String: Any] = [
            "schemaVersion": profile.schemaVersion,
            "revision": profile.revision,
            "capabilities": encodeCapabilities(profile.capabilities, version: profile.schemaVersion),
            "installedHardware": encodeInstalled(profile.installedHardware),
            "media": encodeMedia(profile.media),
            "connection": encodeConnection(profile.connection),
        ]
        if profile.schemaVersion >= 7 {
            root["thermalMedia"] = [
                "method": encodeObservation(profile.thermalMedia.method) { $0.rawValue },
                "ribbonPresent": encodeObservation(profile.thermalMedia.ribbonPresent) { $0 },
            ]
        }
        if profile.schemaVersion == 8 {
            root["finishingConfiguration"] = profile.finishingConfiguration.map(encodeFinishingConfiguration) ?? NSNull()
        }
        if profile.schemaVersion >= 2 {
            root["configuredDefaults"] = [
                "thermalMethod": profile.configuredDefaults.thermalMethod.map { $0.rawValue as Any } ?? NSNull(),
                "finishing": profile.configuredDefaults.finishing.map { $0.rawValue as Any } ?? NSNull(),
                "printSpeedIps": profile.configuredDefaults.printSpeedIps.map { $0 as Any } ?? NSNull(),
            ]
        }
        if profile.schemaVersion >= 3 {
            guard var defaults = root["configuredDefaults"] as? [String: Any] else {
                throw PrinterProfileJSONError.invalidValue("configuredDefaults")
            }
            defaults["feedSpeedIps"] = profile.configuredDefaults.feedSpeedIps.map { $0 as Any } ?? NSNull()
            defaults["backfeedSpeedIps"] = profile.configuredDefaults.backfeedSpeedIps.map { $0 as Any } ?? NSNull()
            if profile.schemaVersion >= 4 { defaults["darkness"] = profile.configuredDefaults.darkness.map { $0 as Any } ?? NSNull() }
            if profile.schemaVersion >= 5 {
                defaults["tracking"] = profile.configuredDefaults.tracking.map { $0.rawValue as Any } ?? NSNull()
                defaults["mediaGeometry"] = PrivatePhysicalGeometryJSON.encode(profile.configuredDefaults.mediaGeometry)
            }
            if profile.schemaVersion >= 6 { defaults["offsets"] = PrivateOffsetJSON.encode(profile.configuredDefaults.offsets) }
            root["configuredDefaults"] = defaults
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw PrinterProfileJSONError.outputTooLarge }
        return data
    }

    public static func decode(
        _ data: Data,
        maximumBytes: Int = maximumBytes
    ) throws -> PrinterProfile {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw PrinterProfileJSONError.invalidLimit
        }
        guard data.count <= maximumBytes else { throw PrinterProfileJSONError.inputTooLarge }
        let raw: Any
        do { raw = try TokenPreservingJSON.decode(data) }
        catch { throw PrinterProfileJSONError.malformedJSON }
        do {
            guard let dictionary = raw as? [String: Any] else {
                throw PrinterProfileJSONError.invalidType("object")
            }
            let version = try integer(dictionary, "schemaVersion")
            guard (1...8).contains(version) else { throw PrinterProfileJSONError.unsupportedSchema }
            var keys: Set<String> = [
                "schemaVersion", "revision", "capabilities", "installedHardware",
                "media", "connection",
            ]
            if version >= 2 { keys.insert("configuredDefaults") }
            if version >= 7 { keys.insert("thermalMedia") }
            if version == 8 { keys.insert("finishingConfiguration") }
            let root = try object(raw, allowed: keys)
            var defaults = PrinterControlDefaults()
            if version >= 2 {
                var defaultKeys: Set<String> = ["thermalMethod", "finishing", "printSpeedIps"]
                if version >= 3 { defaultKeys.formUnion(["feedSpeedIps", "backfeedSpeedIps"]) }
                if version >= 4 { defaultKeys.insert("darkness") }
                if version >= 5 { defaultKeys.formUnion(["tracking", "mediaGeometry"]) }
                if version >= 6 { defaultKeys.insert("offsets") }
                let value = try object(required(root, "configuredDefaults"), allowed: defaultKeys)
                if !(try required(value, "thermalMethod") is NSNull) {
                    defaults.thermalMethod = try enumeration(value, "thermalMethod", ThermalMethod.self)
                }
                if !(try required(value, "finishing") is NSNull) {
                    defaults.finishing = try enumeration(value, "finishing", FinishingMode.self)
                }
                if version >= 6 { defaults.offsets = try PrivateOffsetJSON.decode(required(value, "offsets")) }
                defaults.printSpeedIps = try optionalInteger(value, "printSpeedIps")
                if version >= 4 { defaults.darkness = try optionalInteger(value, "darkness") }
                if version >= 5 {
                    if !(try required(value, "tracking") is NSNull) { defaults.tracking = try enumeration(value, "tracking", MediaTracking.self) }
                    defaults.mediaGeometry = try PrivatePhysicalGeometryJSON.decode(required(value, "mediaGeometry"))
                }
                if version >= 3 {
                    defaults.feedSpeedIps = try optionalInteger(value, "feedSpeedIps")
                    defaults.backfeedSpeedIps = try optionalInteger(value, "backfeedSpeedIps")
                }
            }
            return try PrinterProfile(
                schemaVersion: version,
                revision: integer(root, "revision"),
                capabilities: decodeCapabilities(try required(root, "capabilities"), version: version),
                installedHardware: decodeInstalled(try required(root, "installedHardware")),
                media: decodeMedia(try required(root, "media")),
                connection: decodeConnection(try required(root, "connection")),
                configuredDefaults: defaults,
                thermalMedia: version >= 7 ? try decodeThermalMedia(required(root, "thermalMedia")) : .unobserved,
                finishingConfiguration: version == 8 ? try decodeFinishingConfiguration(required(root, "finishingConfiguration")) : nil
            )
        } catch let error as PrinterProfileJSONError { throw error }
        catch { throw PrinterProfileJSONError.invalidValue("profile") }
    }

    private static func encodeCapabilities(_ value: PrinterCapabilities, version: Int) -> [String: Any] {
        var tracking: [String: Any] = [:]
        for choice in [MediaTracking.gap, .blackMark, .continuous] {
            tracking[choice.rawValue] = value.tracking[choice].map(encodeFact) ?? NSNull()
        }
        var result: [String: Any] = [
            "model": value.model,
            "thermalTransfer": encodeFact(value.thermalTransfer),
            "cutter": encodeFact(value.cutter),
            "peeler": encodeFact(value.peeler),
            "rewind": encodeFact(value.rewind),
            "tracking": tracking,
            "printSpeedChoicesIps": value.printSpeedChoicesIps.sorted(),
            "darkness": encodeFact(value.darkness),
        ]
        if version >= 7 { result["directThermal"] = encodeFact(value.directThermal) }
        if version >= 3 {
            result["feedSpeeds"] = encodeSpeedChoices(value.feedSpeeds)
            result["backfeedSpeeds"] = encodeSpeedChoices(value.backfeedSpeeds)
        }
        if version >= 5 {
            let p = value.physicalGeometry
            func limit(_ value: QualifiedDotLimit) -> Any {
                ["fact": encodeFact(value.fact), "maximumDots": value.maximumDots.map { $0 as Any } ?? NSNull()]
            }
            result["physicalGeometry"] = ["width": limit(p.width), "continuousLength": limit(p.continuousLength),
                                          "homeX": limit(p.homeX), "homeY": limit(p.homeY)]
        }
        if version >= 6 {
            func limit(_ value: QualifiedDotRange) -> Any {
                ["fact": encodeFact(value.fact), "minimumDots": value.range.map { $0.lowerBound as Any } ?? NSNull(),
                 "maximumDots": value.range.map { $0.upperBound as Any } ?? NSNull()]
            }
            result["offsets"] = ["blackMark": limit(value.offsets.blackMark), "shiftLeft": limit(value.offsets.shiftLeft),
                                 "labelTop": limit(value.offsets.labelTop)]
        }
        return result
    }

    private static func decodeOffsets(_ raw: Any) throws -> OffsetControlQualification {
        let value = try object(raw, allowed: ["blackMark", "shiftLeft", "labelTop"])
        func limit(_ key: String) throws -> QualifiedDotRange {
            let item = try object(required(value, key), allowed: ["fact", "minimumDots", "maximumDots"])
            let low = try optionalInteger(item, "minimumDots"), high = try optionalInteger(item, "maximumDots")
            guard (low == nil) == (high == nil) else { throw PrinterProfileJSONError.invalidType("offset range") }
            let range: ClosedRange<Int>?
            if let low, let high {
                guard low >= -9_999, high <= 9_999, low <= high else { throw PrinterProfileJSONError.invalidType("offset range") }
                range = low...high
            } else { range = nil }
            return .init(fact: try decodeFact(required(item, "fact")), range: range)
        }
        return try .init(blackMark: limit("blackMark"), shiftLeft: limit("shiftLeft"), labelTop: limit("labelTop"))
    }

    private static func decodePhysicalGeometry(_ raw: Any) throws -> PhysicalGeometryQualification {
        let object = try object(raw, allowed: ["width", "continuousLength", "homeX", "homeY"])
        func limit(_ key: String) throws -> QualifiedDotLimit {
            let value = try self.object(required(object, key), allowed: ["fact", "maximumDots"])
            return try .init(fact: decodeFact(required(value, "fact")), maximumDots: optionalInteger(value, "maximumDots"))
        }
        return try .init(width: limit("width"), continuousLength: limit("continuousLength"), homeX: limit("homeX"), homeY: limit("homeY"))
    }

    private static func encodeSpeedChoices(_ value: QualifiedSpeedChoices) -> [String: Any] {
        ["fact": encodeFact(value.fact), "choicesIps": value.choicesIps.sorted()]
    }

    private static func decodeSpeedChoices(_ raw: Any) throws -> QualifiedSpeedChoices {
        let value = try object(raw, allowed: ["fact", "choicesIps"])
        guard let array = try required(value, "choicesIps") as? [Any], array.count <= 11 else {
            throw PrinterProfileJSONError.invalidValue("choicesIps")
        }
        let choices = try array.map { try integerValue($0, "choicesIps") }
        guard Set(choices).count == choices.count else {
            throw PrinterProfileJSONError.invalidValue("choicesIps")
        }
        return QualifiedSpeedChoices(fact: try decodeFact(required(value, "fact")), choicesIps: Set(choices))
    }


    private static let finishingModes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]

    private static func encodeFinishingConfiguration(_ value: FinishingProfileConfiguration) -> [String: Any] {
        var modes: [String: Any] = [:], stock: [String: Any] = [:]
        for mode in finishingModes {
            modes[mode.rawValue] = value.finishing.modes[mode].map(encodeFact) ?? NSNull()
            stock[mode.rawValue] = value.stock.compatibleModes[mode].map { encodeObservation($0) { $0 } } ?? NSNull()
        }
        return ["modes": modes, "enabledModes": value.finishing.enabledModes.map(\.rawValue).sorted(),
            "installed": ["cutter": encodeObservation(value.finishing.installed.cutter) { $0 },
                "peeler": encodeObservation(value.finishing.installed.peeler) { $0 },
                "rewinder": encodeObservation(value.finishing.installed.rewinder) { $0 }],
            "stock": ["media": encodeMedia(value.stock.media), "compatibleModes": stock],
            "schedules": ["everyLabel": encodeFact(value.schedules.everyLabel),
                "batch": encodeFact(value.schedules.batch), "endOfJob": encodeFact(value.schedules.endOfJob),
                "maximumBatchSize": value.schedules.maximumBatchSize.map { $0 as Any } ?? NSNull()]]
    }

    private static func decodeFinishingBoolean(_ raw: Any) throws -> Observation<Bool> {
        try decodeObservation(raw) {
            guard let number = $0 as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw PrinterProfileJSONError.invalidType("finishingBoolean")
            }
            return number.boolValue
        }
    }

    private static func decodeFinishingConfiguration(_ raw: Any) throws -> FinishingProfileConfiguration? {
        if raw is NSNull { return nil }
        let value = try object(raw, allowed: ["modes", "enabledModes", "installed", "stock", "schedules"])
        let keys = Set(finishingModes.map(\.rawValue))
        let modes = try object(required(value, "modes"), allowed: keys)
        let stock = try object(required(value, "stock"), allowed: ["media", "compatibleModes"])
        let compatible = try object(required(stock, "compatibleModes"), allowed: keys)
        var facts: [FinishingMode: CapabilityFact] = [:], observations: [FinishingMode: Observation<Bool>] = [:]
        for mode in finishingModes {
            let fact = try required(modes, mode.rawValue)
            if !(fact is NSNull) { facts[mode] = try decodeFact(fact) }
            let observation = try required(compatible, mode.rawValue)
            if !(observation is NSNull) { observations[mode] = try decodeFinishingBoolean(observation) }
        }
        guard let enabled = try required(value, "enabledModes") as? [String], enabled.count <= 4,
              enabled == enabled.sorted(), Set(enabled).count == enabled.count,
              enabled.allSatisfy({ FinishingMode(rawValue: $0) != nil }) else {
            throw PrinterProfileJSONError.invalidValue("enabledModes")
        }
        let installed = try object(required(value, "installed"), allowed: ["cutter", "peeler", "rewinder"])
        let schedules = try object(required(value, "schedules"), allowed: ["everyLabel", "batch", "endOfJob", "maximumBatchSize"])
        return .init(finishing: .init(modes: facts, enabledModes: Set(enabled.compactMap(FinishingMode.init(rawValue:))),
            installed: .init(cutter: try decodeFinishingBoolean(required(installed, "cutter")),
                peeler: try decodeFinishingBoolean(required(installed, "peeler")),
                rewinder: try decodeFinishingBoolean(required(installed, "rewinder")))),
            stock: .init(media: try decodeMedia(required(stock, "media")), compatibleModes: observations),
            schedules: .init(everyLabel: try decodeFact(required(schedules, "everyLabel")),
                batch: try decodeFact(required(schedules, "batch")), endOfJob: try decodeFact(required(schedules, "endOfJob")),
                maximumBatchSize: try optionalInteger(schedules, "maximumBatchSize")))
    }

    private static func validateForEncoding(_ profile: PrinterProfile) throws {
        if let configuration = profile.finishingConfiguration {
            for fact in Array(configuration.finishing.modes.values) + [configuration.schedules.everyLabel,
                configuration.schedules.batch, configuration.schedules.endOfJob] { try validateEvidence(fact.evidence) }
            for observation in Array(configuration.stock.compatibleModes.values) + [configuration.finishing.installed.cutter,
                configuration.finishing.installed.peeler, configuration.finishing.installed.rewinder] {
                try validateObservationEvidence(observation)
            }
        }
        let capabilities = profile.capabilities
        for fact in [
            capabilities.directThermal, capabilities.thermalTransfer, capabilities.cutter, capabilities.peeler,
            capabilities.rewind, capabilities.darkness, capabilities.feedSpeeds.fact,
            capabilities.backfeedSpeeds.fact, capabilities.physicalGeometry.width.fact,
            capabilities.physicalGeometry.continuousLength.fact, capabilities.physicalGeometry.homeX.fact,
            capabilities.physicalGeometry.homeY.fact, capabilities.offsets.blackMark.fact,
            capabilities.offsets.shiftLeft.fact, capabilities.offsets.labelTop.fact,
        ] + Array(capabilities.tracking.values) {
            try validateEvidence(fact.evidence)
        }
        try validateEvidence(profile.installedHardware.cutter.evidence)
        try validateEvidence(profile.installedHardware.peeler.evidence)
        try validateObservationEvidence(profile.thermalMedia.method)
        try validateObservationEvidence(profile.thermalMedia.ribbonPresent)
        try validateObservationEvidence(profile.media.form)
        try validateObservationEvidence(profile.media.nominalLabelFace)
        try validateObservationEvidence(profile.media.configuredTracking)
        try validateObservationEvidence(profile.media.calibration)
        try validateObservationEvidence(profile.connection.stableIdentity)
    }

    private static func validateObservationEvidence<T>(_ value: Observation<T>) throws {
        if case .observed(_, let evidence) = value {
            guard evidence != .unobserved else {
                throw PrinterProfileJSONError.invalidValue("observationEvidence")
            }
            try validateEvidence(evidence)
        }
    }

    private static func validateEvidence(_ value: CapabilityEvidence) throws {
        guard case .documentedModel(let sourceID) = value else { return }
        guard !sourceID.isEmpty, sourceID.utf8.count <= 128,
              sourceID.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw PrinterProfileJSONError.invalidValue("sourceID")
        }
    }

    private static func decodeCapabilities(_ raw: Any, version: Int) throws -> PrinterCapabilities {
        var keys: Set<String> = ["model", "thermalTransfer", "cutter", "peeler", "rewind", "tracking",
                                 "printSpeedChoicesIps", "darkness"]
        if version >= 7 { keys.insert("directThermal") }
        if version >= 3 { keys.formUnion(["feedSpeeds", "backfeedSpeeds"]) }
        if version >= 5 { keys.insert("physicalGeometry") }
        if version >= 6 { keys.insert("offsets") }
        let value = try object(raw, allowed: keys)
        let trackingObject = try object(try required(value, "tracking"), allowed: [
            MediaTracking.gap.rawValue, MediaTracking.blackMark.rawValue,
            MediaTracking.continuous.rawValue,
        ])
        var tracking: [MediaTracking: CapabilityFact] = [:]
        for choice in [MediaTracking.gap, .blackMark, .continuous] {
            let rawFact = try required(trackingObject, choice.rawValue)
            if !(rawFact is NSNull) { tracking[choice] = try decodeFact(rawFact) }
        }
        let speedRaw = try required(value, "printSpeedChoicesIps")
        guard let speedValues = speedRaw as? [Any], speedValues.count <= 32 else {
            throw PrinterProfileJSONError.invalidType("printSpeedChoicesIps")
        }
        let speeds = try speedValues.map { try integerValue($0, "printSpeedChoicesIps") }
        guard Set(speeds).count == speeds.count else {
            throw PrinterProfileJSONError.invalidValue("printSpeedChoicesIps")
        }
        return PrinterCapabilities(
            model: try safeString(value, "model", maximumBytes: 128),
            thermalTransfer: try decodeFact(required(value, "thermalTransfer")),
            cutter: try decodeFact(required(value, "cutter")),
            peeler: try decodeFact(required(value, "peeler")),
            rewind: try decodeFact(required(value, "rewind")),
            tracking: tracking,
            printSpeedChoicesIps: Set(speeds),
            darkness: try decodeFact(required(value, "darkness")),
            feedSpeeds: version >= 3 ? try decodeSpeedChoices(required(value, "feedSpeeds")) : .unverified,
            backfeedSpeeds: version >= 3 ? try decodeSpeedChoices(required(value, "backfeedSpeeds")) : .unverified,
            physicalGeometry: version >= 5 ? try decodePhysicalGeometry(required(value, "physicalGeometry")) : .unverified,
            offsets: version >= 6 ? try decodeOffsets(required(value, "offsets")) : .unverified,
            directThermal: version >= 7 ? try decodeFact(required(value, "directThermal")) : .init(state: .unknown, evidence: .unobserved)
        )
    }

    private static func encodeInstalled(_ value: InstalledHardware) -> [String: Any] {
        [
            "transport": value.transport.rawValue,
            "selectedFinishing": value.selectedFinishing.rawValue,
            "cutter": encodeFact(value.cutter),
            "peeler": encodeFact(value.peeler),
            "observedSpeedIps": value.observedSpeedIps.map { $0 as Any } ?? NSNull(),
            "observedDarkness": value.observedDarkness.map { $0 as Any } ?? NSNull(),
            "observedTracking": value.observedTracking.map { $0.rawValue as Any } ?? NSNull(),
        ]
    }

    private static func decodeInstalled(_ raw: Any) throws -> InstalledHardware {
        let value = try object(raw, allowed: [
            "transport", "selectedFinishing", "cutter", "peeler", "observedSpeedIps",
            "observedDarkness", "observedTracking",
        ])
        return InstalledHardware(
            transport: try enumeration(value, "transport", PrinterTransport.self),
            selectedFinishing: try enumeration(value, "selectedFinishing", FinishingMode.self),
            cutter: try decodeFact(required(value, "cutter")),
            peeler: try decodeFact(required(value, "peeler")),
            observedSpeedIps: try optionalInteger(value, "observedSpeedIps"),
            observedDarkness: try optionalInteger(value, "observedDarkness"),
            observedTracking: try optionalEnumeration(value, "observedTracking", MediaTracking.self)
        )
    }

    private static func encodeMedia(_ value: MediaConfiguration) -> [String: Any] {
        [
            "form": encodeObservation(value.form) { $0.rawValue },
            "nominalLabelFace": encodeObservation(value.nominalLabelFace) {
                ["widthMM": $0.width.value, "heightMM": $0.height.value]
            },
            "configuredTracking": encodeObservation(value.configuredTracking) { $0.rawValue },
            "calibration": encodeObservation(value.calibration) {
                [
                    "widthDots": $0.widthDots, "lengthDots": $0.lengthDots,
                    "originXDot": $0.originXDot, "originYDot": $0.originYDot,
                ]
            },
        ]
    }

    private static func decodeMedia(_ raw: Any) throws -> MediaConfiguration {
        let value = try object(raw, allowed: [
            "form", "nominalLabelFace", "configuredTracking", "calibration",
        ])
        let form: Observation<MediaForm> = try decodeObservation(required(value, "form")) {
            try rawEnumeration($0, "form", MediaForm.self)
        }
        let face: Observation<PhysicalSize> = try decodeObservation(
            required(value, "nominalLabelFace")
        ) { raw in
            let size = try object(raw, allowed: ["widthMM", "heightMM"])
            return PhysicalSize(
                width: try Millimeters(number(size, "widthMM")),
                height: try Millimeters(number(size, "heightMM"))
            )
        }
        let tracking: Observation<MediaTracking> = try decodeObservation(
            required(value, "configuredTracking")
        ) { try rawEnumeration($0, "configuredTracking", MediaTracking.self) }
        let calibration: Observation<MediaCalibration> = try decodeObservation(
            required(value, "calibration")
        ) { raw in
            let item = try object(raw, allowed: [
                "widthDots", "lengthDots", "originXDot", "originYDot",
            ])
            return try MediaCalibration(
                widthDots: integer(item, "widthDots"),
                lengthDots: integer(item, "lengthDots"),
                originXDot: integer(item, "originXDot"),
                originYDot: integer(item, "originYDot")
            )
        }
        return MediaConfiguration(
            form: form, nominalLabelFace: face,
            configuredTracking: tracking, calibration: calibration
        )
    }

    private static func encodeConnection(_ value: ConnectionConfiguration) -> [String: Any] {
        [
            "transport": value.transport.rawValue,
            "stableIdentity": encodeObservation(value.stableIdentity) {
                $0.privateProfileValue
            },
        ]
    }

    private static func decodeConnection(_ raw: Any) throws -> ConnectionConfiguration {
        let value = try object(raw, allowed: ["transport", "stableIdentity"])
        let identity: Observation<StableConnectionIdentity> = try decodeObservation(
            required(value, "stableIdentity")
        ) { raw in
            guard let text = raw as? String else {
                throw PrinterProfileJSONError.invalidType("stableIdentity")
            }
            return try StableConnectionIdentity(opaqueValue: text)
        }
        return ConnectionConfiguration(
            transport: try enumeration(value, "transport", PrinterTransport.self),
            stableIdentity: identity
        )
    }

    private static func encodeFact(_ value: CapabilityFact) -> [String: Any] {
        ["state": value.state.rawValue, "evidence": encodeEvidence(value.evidence)]
    }

    private static func decodeFact(_ raw: Any) throws -> CapabilityFact {
        let value = try object(raw, allowed: ["state", "evidence"])
        return CapabilityFact(
            state: try enumeration(value, "state", CapabilityState.self),
            evidence: try decodeEvidence(required(value, "evidence"))
        )
    }

    private static func encodeEvidence(_ value: CapabilityEvidence) -> [String: Any] {
        switch value {
        case .documentedModel(let sourceID):
            return ["kind": "documentedModel", "sourceID": sourceID]
        case .reportedInstallation:
            return ["kind": "reportedInstallation", "sourceID": NSNull()]
        case let .observedByHost(method):
            return ["kind": "observedByHost", "method": method.rawValue]
        case .unobserved:
            return ["kind": "unobserved", "sourceID": NSNull()]
        }
    }

    private static func decodeEvidence(_ raw: Any) throws -> CapabilityEvidence {
        // The key set is checked per kind rather than once for all kinds.
        // `object(_:allowed:)` demands an exact match, so a single shared set
        // containing "method" would force every evidence object -- including
        // every profile already written to disk -- to grow a null "method"
        // field. A host observation has no source document, so it carries
        // "method" and no "sourceID"; the other three keep their exact
        // existing shape, byte for byte.
        //
        // "method" is also not smuggled through "sourceID". A source
        // identifier names a document, a method names how this host looked,
        // and one field meaning both is the conflation this case exists to end.
        guard let fields = raw as? [String: Any] else {
            throw PrinterProfileJSONError.invalidType("object")
        }
        let kind = try string(fields, "kind")
        if kind == "observedByHost" {
            let value = try object(raw, allowed: ["kind", "method"])
            guard let method = HostObservationMethod(rawValue: try string(value, "method")) else {
                throw PrinterProfileJSONError.invalidValue("method")
            }
            return .observedByHost(method: method)
        }
        let value = try object(raw, allowed: ["kind", "sourceID"])
        switch kind {
        case "documentedModel":
            return .documentedModel(
                sourceID: try safeString(value, "sourceID", maximumBytes: 128)
            )
        case "reportedInstallation":
            guard try required(value, "sourceID") is NSNull else {
                throw PrinterProfileJSONError.invalidValue("sourceID")
            }
            return .reportedInstallation
        case "unobserved":
            guard try required(value, "sourceID") is NSNull else {
                throw PrinterProfileJSONError.invalidValue("sourceID")
            }
            return .unobserved
        default:
            throw PrinterProfileJSONError.invalidValue("evidence")
        }
    }

    private static func decodeThermalMedia(_ raw: Any) throws -> ThermalMediaConfiguration {
        let value = try object(raw, allowed: ["method", "ribbonPresent"])
        let method: Observation<ThermalMethod> = try decodeObservation(required(value, "method")) {
            guard let name = $0 as? String, let method = ThermalMethod(rawValue: name) else {
                throw PrinterProfileJSONError.invalidType("thermalMethod")
            }
            return method
        }
        let ribbon: Observation<Bool> = try decodeObservation(required(value, "ribbonPresent")) {
            guard let number = $0 as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw PrinterProfileJSONError.invalidType("ribbonPresent")
            }
            return number.boolValue
        }
        return .init(method: method, ribbonPresent: ribbon)
    }

    private static func encodeObservation<T>(
        _ value: Observation<T>, transform: (T) -> Any
    ) -> [String: Any] {
        switch value {
        case .unobserved:
            return ["state": "unobserved", "value": NSNull(), "evidence": NSNull()]
        case .observed(let observed, let evidence):
            return [
                "state": "observed", "value": transform(observed),
                "evidence": encodeEvidence(evidence),
            ]
        }
    }

    private static func decodeObservation<T: Equatable & Sendable>(
        _ raw: Any, transform: (Any) throws -> T
    ) throws -> Observation<T> {
        let value = try object(raw, allowed: ["state", "value", "evidence"])
        switch try string(value, "state") {
        case "unobserved":
            guard try required(value, "value") is NSNull,
                  try required(value, "evidence") is NSNull else {
                throw PrinterProfileJSONError.invalidValue("observation")
            }
            return .unobserved
        case "observed":
            let observed = try transform(required(value, "value"))
            let evidence = try decodeEvidence(required(value, "evidence"))
            guard evidence != .unobserved else {
                throw PrinterProfileJSONError.invalidValue("observationEvidence")
            }
            return .observed(observed, evidence: evidence)
        default:
            throw PrinterProfileJSONError.invalidValue("observation")
        }
    }

    private static func object(_ raw: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw PrinterProfileJSONError.invalidType("object")
        }
        guard Set(value.keys) == allowed else {
            if let missing = allowed.subtracting(value.keys).sorted().first {
                throw PrinterProfileJSONError.missingField(missing)
            }
            throw PrinterProfileJSONError.unknownField
        }
        return value
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw PrinterProfileJSONError.missingField(key) }
        return value
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try required(object, key) as? String else {
            throw PrinterProfileJSONError.invalidType(key)
        }
        return value
    }

    private static func safeString(
        _ object: [String: Any], _ key: String, maximumBytes: Int
    ) throws -> String {
        let value = try string(object, key)
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw PrinterProfileJSONError.invalidValue(key)
        }
        return value
    }

    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        try integerValue(required(object, key), key)
    }

    private static func integerValue(_ raw: Any, _ key: String) throws -> Int {
        guard let value = raw as? TokenPreservingJSON.Number,
              let exact = value.integerValue else { throw PrinterProfileJSONError.invalidType(key) }
        return exact
    }

    private static func optionalInteger(
        _ object: [String: Any], _ key: String
    ) throws -> Int? {
        let value = try required(object, key)
        return value is NSNull ? nil : try integerValue(value, key)
    }

    private static func number(_ object: [String: Any], _ key: String) throws -> Double {
        guard let value = try required(object, key) as? TokenPreservingJSON.Number,
              let parsed = value.doubleValue else { throw PrinterProfileJSONError.invalidType(key) }
        return parsed
    }

    private static func enumeration<T: RawRepresentable>(
        _ object: [String: Any], _ key: String, _: T.Type
    ) throws -> T where T.RawValue == String {
        guard let result = T(rawValue: try string(object, key)) else {
            throw PrinterProfileJSONError.invalidValue(key)
        }
        return result
    }

    private static func optionalEnumeration<T: RawRepresentable>(
        _ object: [String: Any], _ key: String, _: T.Type
    ) throws -> T? where T.RawValue == String {
        let raw = try required(object, key)
        if raw is NSNull { return nil }
        guard let text = raw as? String, let result = T(rawValue: text) else {
            throw PrinterProfileJSONError.invalidValue(key)
        }
        return result
    }

    private static func rawEnumeration<T: RawRepresentable>(
        _ raw: Any, _ key: String, _: T.Type
    ) throws -> T where T.RawValue == String {
        guard let text = raw as? String, let result = T(rawValue: text) else {
            throw PrinterProfileJSONError.invalidValue(key)
        }
        return result
    }
}
