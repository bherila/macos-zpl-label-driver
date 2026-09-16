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
            "capabilities": encodeCapabilities(profile.capabilities),
            "installedHardware": encodeInstalled(profile.installedHardware),
            "media": encodeMedia(profile.media),
            "connection": encodeConnection(profile.connection),
        ]
        if profile.schemaVersion == 2 {
            root["configuredDefaults"] = [
                "thermalMethod": profile.configuredDefaults.thermalMethod.map { $0.rawValue as Any } ?? NSNull(),
                "finishing": profile.configuredDefaults.finishing.map { $0.rawValue as Any } ?? NSNull(),
                "printSpeedIps": profile.configuredDefaults.printSpeedIps.map { $0 as Any } ?? NSNull(),
            ]
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
        do { raw = try JSONSerialization.jsonObject(with: data) }
        catch { throw PrinterProfileJSONError.malformedJSON }
        do {
            guard let dictionary = raw as? [String: Any] else {
                throw PrinterProfileJSONError.invalidType("object")
            }
            let version = try integer(dictionary, "schemaVersion")
            guard (1...2).contains(version) else { throw PrinterProfileJSONError.unsupportedSchema }
            var keys: Set<String> = [
                "schemaVersion", "revision", "capabilities", "installedHardware",
                "media", "connection",
            ]
            if version == 2 { keys.insert("configuredDefaults") }
            let root = try object(raw, allowed: keys)
            var defaults = PrinterControlDefaults()
            if version == 2 {
                let value = try object(required(root, "configuredDefaults"),
                    allowed: ["thermalMethod", "finishing", "printSpeedIps"])
                if !(try required(value, "thermalMethod") is NSNull) {
                    defaults.thermalMethod = try enumeration(value, "thermalMethod", ThermalMethod.self)
                }
                if !(try required(value, "finishing") is NSNull) {
                    defaults.finishing = try enumeration(value, "finishing", FinishingMode.self)
                }
                defaults.printSpeedIps = try optionalInteger(value, "printSpeedIps")
            }
            return try PrinterProfile(
                schemaVersion: version,
                revision: integer(root, "revision"),
                capabilities: decodeCapabilities(try required(root, "capabilities")),
                installedHardware: decodeInstalled(try required(root, "installedHardware")),
                media: decodeMedia(try required(root, "media")),
                connection: decodeConnection(try required(root, "connection")),
                configuredDefaults: defaults
            )
        } catch let error as PrinterProfileJSONError { throw error }
        catch { throw PrinterProfileJSONError.invalidValue("profile") }
    }

    private static func encodeCapabilities(_ value: PrinterCapabilities) -> [String: Any] {
        var tracking: [String: Any] = [:]
        for choice in [MediaTracking.gap, .blackMark, .continuous] {
            tracking[choice.rawValue] = value.tracking[choice].map(encodeFact) ?? NSNull()
        }
        return [
            "model": value.model,
            "thermalTransfer": encodeFact(value.thermalTransfer),
            "cutter": encodeFact(value.cutter),
            "peeler": encodeFact(value.peeler),
            "rewind": encodeFact(value.rewind),
            "tracking": tracking,
            "printSpeedChoicesIps": value.printSpeedChoicesIps.sorted(),
            "darkness": encodeFact(value.darkness),
        ]
    }

    private static func validateForEncoding(_ profile: PrinterProfile) throws {
        let capabilities = profile.capabilities
        for fact in [
            capabilities.thermalTransfer, capabilities.cutter, capabilities.peeler,
            capabilities.rewind, capabilities.darkness,
        ] + Array(capabilities.tracking.values) {
            try validateEvidence(fact.evidence)
        }
        try validateEvidence(profile.installedHardware.cutter.evidence)
        try validateEvidence(profile.installedHardware.peeler.evidence)
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

    private static func decodeCapabilities(_ raw: Any) throws -> PrinterCapabilities {
        let value = try object(raw, allowed: [
            "model", "thermalTransfer", "cutter", "peeler", "rewind", "tracking",
            "printSpeedChoicesIps", "darkness",
        ])
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
            darkness: try decodeFact(required(value, "darkness"))
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
        case .unobserved:
            return ["kind": "unobserved", "sourceID": NSNull()]
        }
    }

    private static func decodeEvidence(_ raw: Any) throws -> CapabilityEvidence {
        let value = try object(raw, allowed: ["kind", "sourceID"])
        switch try string(value, "kind") {
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
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue >= Double(Int.min), number.doubleValue < Double(Int.max),
              number.doubleValue == Double(number.intValue) else {
            throw PrinterProfileJSONError.invalidType(key)
        }
        return number.intValue
    }

    private static func optionalInteger(
        _ object: [String: Any], _ key: String
    ) throws -> Int? {
        let value = try required(object, key)
        return value is NSNull ? nil : try integerValue(value, key)
    }

    private static func number(_ object: [String: Any], _ key: String) throws -> Double {
        guard let value = try required(object, key) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            throw PrinterProfileJSONError.invalidType(key)
        }
        return value.doubleValue
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
