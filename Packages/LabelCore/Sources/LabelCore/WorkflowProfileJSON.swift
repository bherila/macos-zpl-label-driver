import CoreFoundation
import Foundation

public enum WorkflowProfileJSONError: Error, Equatable, Sendable {
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

/// Exact version-1 import/export contract. Unknown keys are rejected at every
/// level, so imported profiles cannot smuggle paths, documents, or commands.
public enum WorkflowProfileJSON {
    public static let maximumBytes = 256 * 1024

    public static func decode(_ data: Data, maximumBytes: Int = maximumBytes) throws -> WorkflowProfile {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw WorkflowProfileJSONError.invalidLimit
        }
        guard data.count <= maximumBytes else {
            throw WorkflowProfileJSONError.inputTooLarge
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw WorkflowProfileJSONError.malformedJSON
        }
        do {
            let root = try object(
                raw,
                allowed: ["schemaVersion", "id", "revision", "outputStock", "pages"],
                required: ["schemaVersion", "id", "revision", "outputStock", "pages"]
            )
            guard try integer(root, "schemaVersion") == 1 else {
                throw WorkflowProfileJSONError.unsupportedSchema
            }
            let output = try object(
                required(root, "outputStock"),
                allowed: ["id", "widthMillimeters", "heightMillimeters"],
                required: ["id", "widthMillimeters", "heightMillimeters"]
            )
            let stock = PhysicalSize(
                width: try Millimeters(number(output, "widthMillimeters")),
                height: try Millimeters(number(output, "heightMillimeters"))
            )
            let pagesRaw = try array(root, "pages")
            guard !pagesRaw.isEmpty, pagesRaw.count <= 1_000 else {
                throw WorkflowProfileJSONError.invalidValue("pages")
            }
            let pages = try pagesRaw.map(decodePage)
            return try WorkflowProfile(
                schemaVersion: 1,
                id: try string(root, "id"),
                revision: try integer(root, "revision"),
                outputStockID: try string(output, "id"),
                outputStock: stock,
                pageRules: pages
            )
        } catch let error as WorkflowProfileJSONError {
            throw error
        } catch {
            throw WorkflowProfileJSONError.invalidValue("profile")
        }
    }

    public static func encode(_ profile: WorkflowProfile, maximumBytes: Int = maximumBytes) throws -> Data {
        guard (1...Self.maximumBytes).contains(maximumBytes) else {
            throw WorkflowProfileJSONError.invalidLimit
        }
        let pages: [[String: Any]] = profile.pageRules.map(encodePage)
        let root: [String: Any] = [
            "schemaVersion": profile.schemaVersion,
            "id": profile.id,
            "revision": profile.revision,
            "outputStock": [
                "id": profile.outputStockID,
                "widthMillimeters": profile.outputStock.width.value,
                "heightMillimeters": profile.outputStock.height.value,
            ],
            "pages": pages,
        ]
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        } catch {
            throw WorkflowProfileJSONError.invalidValue("profile")
        }
        guard data.count <= maximumBytes else { throw WorkflowProfileJSONError.outputTooLarge }
        return data
    }

    private static func decodePage(_ raw: Any) throws -> WorkflowPageRule {
        let page = try object(
            raw,
            allowed: ["sourcePage", "expectedInput", "disposition", "structuralAnchors"],
            required: ["sourcePage", "expectedInput", "disposition", "structuralAnchors"]
        )
        let input = try object(
            required(page, "expectedInput"),
            allowed: ["widthMillimeters", "heightMillimeters", "toleranceMillimeters"],
            required: ["widthMillimeters", "heightMillimeters", "toleranceMillimeters"]
        )
        let expected = try ExpectedInputPage(
            uprightPhysicalSize: PhysicalSize(
                width: try Millimeters(number(input, "widthMillimeters")),
                height: try Millimeters(number(input, "heightMillimeters"))
            ),
            toleranceMillimeters: try number(input, "toleranceMillimeters")
        )
        let dispositionRaw = try object(
            required(page, "disposition"),
            allowed: ["kind", "regions", "reason"],
            required: ["kind"]
        )
        let disposition: WorkflowPageDisposition
        switch try string(dispositionRaw, "kind") {
        case "extract":
            guard dispositionRaw["reason"] == nil else { throw WorkflowProfileJSONError.unknownField }
            let regionsRaw = try array(dispositionRaw, "regions")
            guard !regionsRaw.isEmpty, regionsRaw.count <= 256 else {
                throw WorkflowProfileJSONError.invalidValue("regions")
            }
            disposition = .extract(try regionsRaw.map(decodeRegion))
        case "skip":
            guard dispositionRaw["regions"] == nil,
                  let reason = NonLabelPageReason(rawValue: try string(dispositionRaw, "reason")) else {
                throw WorkflowProfileJSONError.invalidValue("disposition")
            }
            disposition = .skip(reason)
        default:
            throw WorkflowProfileJSONError.invalidValue("disposition")
        }
        let anchorsRaw = try array(page, "structuralAnchors")
        guard anchorsRaw.count <= 64 else { throw WorkflowProfileJSONError.invalidValue("structuralAnchors") }
        return try WorkflowPageRule(
            sourcePage: integer(page, "sourcePage"),
            expectedInput: expected,
            disposition: disposition,
            structuralAnchors: anchorsRaw.map(decodeAnchor)
        )
    }

    private static func decodeRegion(_ raw: Any) throws -> ExtractionRegion {
        let region = try object(
            raw,
            allowed: ["id", "x", "y", "width", "height", "rotation", "scalePolicy", "outputOrder"],
            required: ["id", "x", "y", "width", "height", "rotation", "scalePolicy", "outputOrder"]
        )
        guard let rotation = ExtractionRotation(rawValue: try integer(region, "rotation")),
              let scale = ExtractionScalePolicy(rawValue: try string(region, "scalePolicy")) else {
            throw WorkflowProfileJSONError.invalidValue("region")
        }
        return try ExtractionRegion(
            id: string(region, "id"),
            normalizedRect: NormalizedRect(
                x: number(region, "x"), y: number(region, "y"),
                width: number(region, "width"), height: number(region, "height")
            ),
            rotation: rotation,
            scalePolicy: scale,
            outputOrder: integer(region, "outputOrder")
        )
    }

    private static func decodeAnchor(_ raw: Any) throws -> StructuralAnchorExpectation {
        let anchor = try object(
            raw,
            allowed: ["id", "kind", "x", "y", "width", "height", "maximumCoordinateDeviation"],
            required: ["id", "kind", "x", "y", "width", "height", "maximumCoordinateDeviation"]
        )
        guard let kind = StructuralAnchorKind(rawValue: try string(anchor, "kind")) else {
            throw WorkflowProfileJSONError.invalidValue("anchor")
        }
        return try StructuralAnchorExpectation(
            id: string(anchor, "id"),
            kind: kind,
            normalizedRect: NormalizedRect(
                x: number(anchor, "x"), y: number(anchor, "y"),
                width: number(anchor, "width"), height: number(anchor, "height")
            ),
            maximumCoordinateDeviation: number(anchor, "maximumCoordinateDeviation")
        )
    }

    private static func encodePage(_ rule: WorkflowPageRule) -> [String: Any] {
        let disposition: [String: Any]
        switch rule.disposition {
        case let .extract(regions):
            disposition = ["kind": "extract", "regions": regions.map(encodeRegion)]
        case let .skip(reason):
            disposition = ["kind": "skip", "reason": reason.rawValue]
        }
        return [
            "sourcePage": rule.sourcePage,
            "expectedInput": [
                "widthMillimeters": rule.expectedInput.uprightPhysicalSize.width.value,
                "heightMillimeters": rule.expectedInput.uprightPhysicalSize.height.value,
                "toleranceMillimeters": rule.expectedInput.toleranceMillimeters,
            ],
            "disposition": disposition,
            "structuralAnchors": rule.structuralAnchors.map(encodeAnchor),
        ]
    }

    private static func encodeRegion(_ region: ExtractionRegion) -> [String: Any] {
        [
            "id": region.id,
            "x": region.normalizedRect.x,
            "y": region.normalizedRect.y,
            "width": region.normalizedRect.width,
            "height": region.normalizedRect.height,
            "rotation": region.rotation.rawValue,
            "scalePolicy": region.scalePolicy.rawValue,
            "outputOrder": region.outputOrder,
        ]
    }

    private static func encodeAnchor(_ anchor: StructuralAnchorExpectation) -> [String: Any] {
        [
            "id": anchor.id,
            "kind": anchor.kind.rawValue,
            "x": anchor.normalizedRect.x,
            "y": anchor.normalizedRect.y,
            "width": anchor.normalizedRect.width,
            "height": anchor.normalizedRect.height,
            "maximumCoordinateDeviation": anchor.maximumCoordinateDeviation,
        ]
    }

    private static func object(
        _ raw: Any,
        allowed: Set<String>,
        required requiredKeys: Set<String>
    ) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw WorkflowProfileJSONError.invalidType("object")
        }
        guard Set(value.keys).isSubset(of: allowed) else { throw WorkflowProfileJSONError.unknownField }
        if let missing = requiredKeys.subtracting(value.keys).sorted().first {
            throw WorkflowProfileJSONError.missingField(missing)
        }
        return value
    }

    private static func required(_ object: [String: Any], _ key: String) throws -> Any {
        guard let value = object[key] else { throw WorkflowProfileJSONError.missingField(key) }
        return value
    }

    private static func array(_ object: [String: Any], _ key: String) throws -> [Any] {
        guard let value = try required(object, key) as? [Any] else {
            throw WorkflowProfileJSONError.invalidType(key)
        }
        return value
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try required(object, key) as? String else {
            throw WorkflowProfileJSONError.invalidType(key)
        }
        return value
    }

    private static func number(_ object: [String: Any], _ key: String) throws -> Double {
        guard let value = try required(object, key) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            throw WorkflowProfileJSONError.invalidType(key)
        }
        return value.doubleValue
    }

    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        let value = try number(object, key)
        guard value.rounded(.towardZero) == value,
              value >= Double(Int.min), value < Double(Int.max) else {
            throw WorkflowProfileJSONError.invalidType(key)
        }
        return Int(value)
    }
}
