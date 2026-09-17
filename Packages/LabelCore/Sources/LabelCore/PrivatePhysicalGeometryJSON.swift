import CoreFoundation
import Foundation

/// Shared exact shape for private geometry defaults, distinct from ticket setting modes.
enum PrivatePhysicalGeometryJSON {
    enum Error: Swift.Error { case invalidGeometry }
    static func encode(_ value: MediaGeometryRequest?) -> Any {
        guard let value else { return NSNull() }
        return ["widthDots": value.widthDots.map { $0 as Any } ?? NSNull(),
                "lengthDots": value.lengthDots.map { $0 as Any } ?? NSNull(),
                "originXDot": value.originXDot.map { $0 as Any } ?? NSNull(),
                "originYDot": value.originYDot.map { $0 as Any } ?? NSNull()]
    }
    static func decode(_ raw: Any) throws -> MediaGeometryRequest? {
        if raw is NSNull { return nil }
        guard let object = raw as? [String: Any], Set(object.keys) == ["widthDots", "lengthDots", "originXDot", "originYDot"] else {
            throw Error.invalidGeometry
        }
        func value(_ key: String) throws -> Int? {
            guard let raw = object[key] else { throw Error.invalidGeometry }
            if raw is NSNull { return nil }
            guard let number = raw as? TokenPreservingJSON.Number,
                  let exact = number.integerValue, (-32_000...32_000).contains(exact) else { throw Error.invalidGeometry }
            return exact
        }
        return try .init(widthDots: value("widthDots"), lengthDots: value("lengthDots"),
                         originXDot: value("originXDot"), originYDot: value("originYDot"))
    }
}
