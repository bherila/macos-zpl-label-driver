import CoreFoundation
import Foundation

enum PrivateOffsetJSON {
    enum Error: Swift.Error { case invalidOffsets }
    static func encode(_ value: OffsetControlRequest?) -> Any {
        guard let value else { return NSNull() }
        return ["blackMarkOffsetDots": value.blackMarkOffsetDots.map { $0 as Any } ?? NSNull(),
                "shiftLeftDots": value.shiftLeftDots.map { $0 as Any } ?? NSNull(),
                "labelTopDots": value.labelTopDots.map { $0 as Any } ?? NSNull()]
    }
    static func decode(_ raw: Any) throws -> OffsetControlRequest? {
        if raw is NSNull { return nil }
        guard let object = raw as? [String: Any], Set(object.keys) == ["blackMarkOffsetDots", "shiftLeftDots", "labelTopDots"] else {
            throw Error.invalidOffsets
        }
        func value(_ key: String) throws -> Int? {
            guard let raw = object[key] else { throw Error.invalidOffsets }
            if raw is NSNull { return nil }
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, (-9_999...9_999).contains(number.doubleValue),
                  number.doubleValue == Double(number.intValue) else { throw Error.invalidOffsets }
            return number.intValue
        }
        return try .init(blackMarkOffsetDots: value("blackMarkOffsetDots"), shiftLeftDots: value("shiftLeftDots"),
                         labelTopDots: value("labelTopDots"))
    }
}
